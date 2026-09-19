import SwiftUI

/// Корневой экран приложения.
public struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var sessions: SessionController
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        ZStack {
            NavigationView {
                HomeView()
            }
            .stackNavigation()
            ToastOverlay()
        }
        .fullScreenCoverCompat(isPresented: $sessions.isPresented) {
            WorkoutFlowView().appEnvironment(app)
        }
        .accentColor(Theme.blue)
        .preferredColorScheme(.dark)
        .onAppear { app.onLaunch() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { app.onBecameActive() }
        }
    }
}

/// Главный экран: продолжение незавершённой тренировки, два основных сценария, разделы.
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var content: ContentRepository
    @EnvironmentObject private var sessions: SessionController
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var router: HomeRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let session = sessions.session, !sessions.isPresented {
                    ResumeCard(session: session)
                }

                if content.isEmpty {
                    FirstLoadView()
                } else {
                    MainActionCard(
                        icon: "list.bullet.rectangle",
                        title: "Готовая тренировка",
                        subtitle: content.workouts.isEmpty ? "Список скоро появится" : "В списке: \(RussianPlural.workouts(content.workouts.count))",
                        accent: Theme.blue
                    ) { router.open(.ready) }

                    MainActionCard(
                        icon: "square.grid.2x2",
                        title: "Собрать свою тренировку",
                        subtitle: "Выбрать части тела и отметить упражнения",
                        accent: Theme.accent
                    ) { router.open(.custom) }
                }

                HStack(spacing: 10) {
                    SmallTile(icon: "heart.fill", title: "Избранное", value: userData.favorites.isEmpty ? nil : "\(userData.favorites.count)") { router.open(.favorites) }
                    SmallTile(icon: "clock.arrow.circlepath", title: "История", value: userData.history.isEmpty ? nil : "\(userData.history.count)") { router.open(.history) }
                    SmallTile(icon: "gearshape.fill", title: "Настройки", value: nil) { router.open(.settings) }
                }

                if let error = userData.storageError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundColor(Theme.warning)
                }

                SyncStatusView()
                    .padding(.top, 4)
            }
            .padding(Theme.padding)
        }
        .screen()
        .navigationTitle("Главная")
        .hiddenNavigationBar()
        .background(
            NavigationLink(destination: destination, isActive: Binding(
                get: { router.route != nil },
                set: { if !$0 { router.route = nil } }
            )) { EmptyView() }
            .hidden()
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ТРЕНАЖЁР")
                .font(.largeTitle.weight(.black))
                .foregroundColor(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(userData.history.isEmpty
                 ? "Выбери готовую тренировку или собери свою"
                 : "Тренировок завершено: \(userData.history.count)")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var destination: some View {
        switch router.lastRoute {
        case .ready: ReadyWorkoutsView()
        case .custom: BodyPartPickerView()
        case .favorites: FavoritesView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

/// «Продолжить тренировку» — если приложение закрыли посреди тренировки.
private struct ResumeCard: View {
    @EnvironmentObject private var sessions: SessionController
    @EnvironmentObject private var content: ContentRepository
    let session: WorkoutSession
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "play.circle.fill").foregroundColor(Theme.success)
                Text("Незавершённая тренировка")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
            }
            Text(details)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Продолжить") { sessions.resume() }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.success.opacity(0.85)))
                Button("Завершить") { sessions.finish() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button("Удалить без сохранения") { confirmDiscard = true }
                .font(.footnote.weight(.semibold))
                .foregroundColor(Theme.textTertiary)
                .frame(minHeight: Theme.tapSize)
                .buttonStyle(PlainButtonStyle())
        }
        .padding(Theme.padding)
        .card(highlighted: true)
        .alert(isPresented: $confirmDiscard) {
            Alert(title: Text("Удалить тренировку?"),
                  message: Text("Отмеченные упражнения и подходы не попадут в историю. Это нельзя отменить."),
                  primaryButton: .destructive(Text("Удалить")) { sessions.discard() },
                  secondaryButton: .cancel(Text("Оставить")))
        }
    }

    private var details: String {
        let current = session.currentExerciseId.flatMap(content.exercise(id:))?.name ?? "—"
        let position = session.position
        let started = Formatters.relative.string(from: session.startedAt)
        return "\(session.title) · начата \(started)\nСейчас: \(current) (\(position.index) из \(position.total))"
    }
}

private struct MainActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundColor(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 104)
            .card(raised: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SmallTile: View {
    let icon: String
    let title: String
    let value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let value = value {
                    Text(value)
                        .font(.caption.weight(.bold))
                        .foregroundColor(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Первый запуск: контента ещё нет — объясняем, что происходит и что делать.
private struct FirstLoadView: View {
    @EnvironmentObject private var sync: ContentSyncService
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        if sync.phase != .idle {
            VStack(spacing: 12) {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text("Загружаю упражнения из таблицы Жени…")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .card()
        } else if !network.isConnected {
            EmptyStateView(icon: "wifi.slash", title: "Нужен интернет",
                           message: "Для первой загрузки упражнений нужен интернет. Потом всё скачанное работает без него.",
                           actionTitle: "Повторить") { sync.startSync() }
        } else if sync.lastError == .notConfigured {
            EmptyStateView(icon: "wrench.and.screwdriver", title: "Контент не подключён",
                           message: "В сборке не указан API-ключ Google или ID таблицы. Это настраивает разработчик (см. README).")
        } else {
            EmptyStateView(icon: "exclamationmark.triangle", title: "Не удалось загрузить упражнения",
                           message: sync.lastError?.errorDescription ?? "Попробуйте ещё раз.",
                           actionTitle: "Повторить") { sync.startSync() }
        }
    }
}

/// Строка состояния контента: обновлено / загружается / офлайн / ошибка.
struct SyncStatusView: View {
    @EnvironmentObject private var sync: ContentSyncService
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var settings: SettingsStore
    var showsButton = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch sync.phase {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.textSecondary))
                    Text("Проверяю обновления…")
                }
            case .downloading(let done, let total) where total > 0:
                Text("Скачиваю фото и видео: \(done) из \(total)")
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(LinearProgressViewStyle(tint: Theme.blue))
            default:
                idleStatus
            }
            if showsButton {
                Button("Обновить контент") { sync.startSync() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(sync.isRunning || !network.isConnected)
            }
        }
        .font(.footnote)
        .foregroundColor(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var idleStatus: some View {
        if let error = sync.lastError, error != .notConfigured {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
                    .foregroundColor(error == .offline ? Theme.textSecondary : Theme.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.errorDescription ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                    if error != .offline && !showsButton {
                        Button("Повторить") { sync.startSync() }
                            .font(.footnote.weight(.bold))
                            .foregroundColor(Theme.blue)
                            .frame(minHeight: Theme.tapSize)
                            .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        } else if !network.isConnected {
            Label("Нет интернета — работает всё, что уже скачано", systemImage: "wifi.slash")
        } else if let date = sync.lastSyncDate {
            VStack(alignment: .leading, spacing: 2) {
                Label("Контент обновлён: \(Formatters.relative.string(from: date))", systemImage: "checkmark.icloud")
                if sync.failedDownloads > 0 {
                    Text("Не скачалось файлов: \(sync.failedDownloads) — попробую при следующем обновлении.")
                } else if sync.pendingDownloads > 0 && !settings.device.downloadVideosInAdvance {
                    Text("Видео скачиваются при первом просмотре.")
                }
            }
        }
    }
}
