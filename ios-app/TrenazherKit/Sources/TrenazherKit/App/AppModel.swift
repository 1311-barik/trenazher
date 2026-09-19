import Combine
import SwiftUI
import UserNotifications

/// Настройки сборки из Info.plist (значения приходят из Config/*.xcconfig).
public struct AppConfiguration {
    public var google: GoogleContentConfig
    /// «iCloud.<bundle id>». Пусто — избранное и история хранятся только на устройстве.
    public var cloudKitContainerId: String?

    public init(google: GoogleContentConfig, cloudKitContainerId: String?) {
        self.google = google
        self.cloudKitContainerId = cloudKitContainerId
    }

    public static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        func value(_ key: String) -> String {
            let raw = (bundle.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespaces)
            return raw.hasPrefix("$(") ? "" : raw
        }
        let cloud = value("CloudKitContainerID")
        return AppConfiguration(
            google: GoogleContentConfig(apiKey: value("GoogleAPIKey"), spreadsheetId: value("GoogleSpreadsheetID"),
                                        rootFolderId: value("GoogleDriveFolderID")),
            cloudKitContainerId: cloud.isEmpty ? nil : cloud
        )
    }
}

/// Корень приложения: создаёт сервисы и связывает их между собой.
@MainActor
public final class AppModel: ObservableObject {
    public let network: NetworkMonitor
    public let content: ContentRepository
    public let downloader: MediaDownloader
    public let sync: ContentSyncService
    public let userData: UserDataStore
    public let settings: SettingsStore
    public let notifications: NotificationScheduler
    public let sessions: SessionController
    public let draft: CustomWorkoutDraft
    public let restTimer: RestTimer
    public let toasts: ToastCenter
    public let router: HomeRouter

    private let notificationDelegate = ForegroundNotificationDelegate()
    private var subscriptions = Set<AnyCancellable>()

    public init(configuration: AppConfiguration,
                source: ContentSource? = nil,
                network: NetworkMonitor? = nil,
                contentRoot: URL = ContentStore.defaultRootURL(),
                userData: UserDataStore? = nil,
                settings: SettingsStore? = nil,
                sessionFile: URL = SessionController.defaultFileURL(),
                defaults: UserDefaults = .standard,
                notificationCenter: UNUserNotificationCenter? = nil) {
        let http = URLSessionHTTPClient()
        let source = source ?? GoogleContentSource(config: configuration.google, http: http)
        let store = ContentStore(rootURL: contentRoot)
        // iCloud Key-Value — только если подключён iCloud (платный аккаунт разработчика); иначе настройки локальные.
        let settings = settings ?? SettingsStore(defaults: defaults,
                                                 cloud: configuration.cloudKitContainerId == nil ? nil : NSUbiquitousKeyValueStore.default)

        let network = network ?? NetworkMonitor()
        self.network = network
        self.content = ContentRepository(manifest: store.loadManifest() ?? .empty)
        self.downloader = MediaDownloader(store: store, source: source, http: http)
        self.settings = settings
        self.sync = ContentSyncService(repository: content, source: source, downloader: downloader, network: network,
                                       defaults: defaults, prefetchVideos: { settings.device.downloadVideosInAdvance })
        self.userData = userData ?? UserDataStore(cloudKitContainerId: configuration.cloudKitContainerId)
        self.notifications = NotificationScheduler(center: notificationCenter)
        self.sessions = SessionController(fileURL: sessionFile, userData: self.userData, content: content)
        self.draft = CustomWorkoutDraft(defaults: defaults)
        self.restTimer = RestTimer(notifications: notifications)
        self.toasts = ToastCenter()
        self.router = HomeRouter()
        restTimer.onFinish = { Haptics.restFinished() }
        notificationCenter?.delegate = notificationDelegate
        bind()
    }

    /// Рабочая конфигурация приложения.
    public static func live() -> AppModel {
        let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()
        return AppModel(configuration: .fromBundle(), notificationCenter: center)
    }

    private func bind() {
        // Напоминания перепланируются при любом изменении расписания (в том числе пришедшем с iPad).
        settings.$settings.combineLatest(settings.$device)
            .map { shared, device in ReminderInput(settings: shared, onThisDevice: device.remindersOnThisDevice) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] input in
                Task { await self?.notifications.applyReminders(input.settings, onThisDevice: input.onThisDevice) }
            }
            .store(in: &subscriptions)

        // Включили «скачивать видео заранее» — докачиваем.
        settings.$device.map(\.downloadVideosInAdvance).removeDuplicates().dropFirst()
            .sink { [weak self] enabled in
                self?.sync.refreshPendingCount()
                if enabled { self?.sync.startSync() }
            }
            .store(in: &subscriptions)

        // Появился интернет — докачиваем то, что не успели.
        network.$isConnected.removeDuplicates().dropFirst().filter { $0 }
            .sink { [weak self] _ in self?.sync.syncIfNeeded() }
            .store(in: &subscriptions)

        // Контент обновился — чистим черновик от удалённых упражнений.
        content.$manifest.dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async { self.draft.prune(using: self.content) }
            }
            .store(in: &subscriptions)
    }

    private struct ReminderInput: Equatable {
        var settings: AppSettings
        var onThisDevice: Bool

        static func == (lhs: ReminderInput, rhs: ReminderInput) -> Bool {
            lhs.onThisDevice == rhs.onThisDevice
                && lhs.settings.remindersEnabled == rhs.settings.remindersEnabled
                && lhs.settings.reminderHour == rhs.settings.reminderHour
                && lhs.settings.reminderMinute == rhs.settings.reminderMinute
                && lhs.settings.reminderWeekdays == rhs.settings.reminderWeekdays
        }
    }

    // MARK: - Жизненный цикл

    public func onLaunch() {
        sync.syncIfNeeded()
        notifications.refreshAuthorization()
        Task { await notifications.applyReminders(settings.settings, onThisDevice: settings.device.remindersOnThisDevice) }
    }

    public func onBecameActive() {
        restTimer.tick()
        notifications.refreshAuthorization()
        settings.applyRemoteIfNewer()
        userData.reload()
        sync.syncIfNeeded()
    }

    // MARK: - Команды, общие для нескольких экранов

    /// ♡ с подтверждением и возможностью отменить снятие.
    public func toggleFavorite(itemId: String, type: FavoriteItem.ItemType, title: String) {
        let isNowFavorite = userData.toggleFavorite(itemId: itemId, type: type, title: title)
        Haptics.tap()
        if isNowFavorite {
            toasts.show("Добавлено в избранное")
        } else {
            toasts.show("Убрано из избранного", actionTitle: "Отменить") { [weak self] in
                self?.userData.addFavorite(FavoriteItem(itemId: itemId, type: type, title: title))
            }
        }
    }

    /// Удаление записи истории с «Отменить».
    public func deleteHistory(_ entry: HistoryEntry) {
        userData.deleteHistory(id: entry.id)
        toasts.show("Тренировка удалена из истории", actionTitle: "Отменить") { [weak self] in
            self?.userData.addHistory(entry)
        }
    }

    /// Начать тренировку и убрать экраны выбора под экраном тренировки.
    public func startWorkout(_ workout: Workout) {
        sessions.start(workout: workout)
        router.popToRoot()
    }

    public func startCustomWorkout() {
        sessions.startCustom(exerciseIds: draft.orderedSelection(in: content), bodyParts: draft.bodyParts)
        router.popToRoot()
    }

    /// Повторить тренировку из истории: упражнения, которые всё ещё есть в контенте.
    public func repeatWorkout(from entry: HistoryEntry) {
        let ids = entry.exerciseIds.filter { content.exercise(id: $0) != nil }
        guard !ids.isEmpty else {
            toasts.show("Этих упражнений больше нет в таблице")
            return
        }
        sessions.startCustom(exerciseIds: ids, bodyParts: content.bodyParts(forExerciseIds: ids))
        sessions.update { $0.kind = entry.kind; $0.title = entry.title }
        router.popToRoot()
    }
}

/// Навигация с главного экрана. Один NavigationLink на весь экран — надёжнее на iOS 14,
/// и «на главный» делается одной строкой.
@MainActor
public final class HomeRouter: ObservableObject {
    public enum Route: Hashable {
        case ready, custom, favorites, history, settings
    }

    @Published public var route: Route? {
        didSet { if let route = route { lastRoute = route } }
    }

    /// Последний открытый раздел — чтобы при анимации возврата экран не мигал пустотой.
    @Published public private(set) var lastRoute: Route = .ready

    public func open(_ route: Route) { self.route = route }
    public func popToRoot() { route = nil }
}

/// Короткое сообщение внизу экрана, при необходимости — с кнопкой «Отменить».
@MainActor
public final class ToastCenter: ObservableObject {
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
        public let actionTitle: String?
        let action: (() -> Void)?

        public static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    @Published public private(set) var current: Toast?
    private var hideWork: DispatchWorkItem?

    public func show(_ message: String, actionTitle: String? = nil, duration: TimeInterval = 4, action: (() -> Void)? = nil) {
        let toast = Toast(message: message, actionTitle: actionTitle, action: action)
        current = toast
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.current?.id == toast.id { self?.current = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (actionTitle == nil ? min(duration, 2.5) : duration), execute: work)
    }

    public func performAction() {
        current?.action?()
        dismiss()
    }

    public func dismiss() {
        hideWork?.cancel()
        current = nil
    }
}

extension View {
    /// Все сервисы — в окружение. Для sheet/fullScreenCover вызывается повторно, чтобы на iOS 14 ничего не потерялось.
    public func appEnvironment(_ app: AppModel) -> some View {
        environmentObject(app)
            .environmentObject(app.network)
            .environmentObject(app.content)
            .environmentObject(app.downloader)
            .environmentObject(app.sync)
            .environmentObject(app.userData)
            .environmentObject(app.settings)
            .environmentObject(app.notifications)
            .environmentObject(app.sessions)
            .environmentObject(app.draft)
            .environmentObject(app.restTimer)
            .environmentObject(app.toasts)
            .environmentObject(app.router)
    }
}
