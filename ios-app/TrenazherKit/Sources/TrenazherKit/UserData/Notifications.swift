import Foundation
import UserNotifications

/// Локальные уведомления: напоминания о тренировке по расписанию и «отдых окончен».
/// Сервер не нужен — всё планируется на самом устройстве.
@MainActor
public final class NotificationScheduler: ObservableObject {
    public enum Authorization: Equatable {
        case unknown, notDetermined, allowed, denied
    }

    @Published public private(set) var authorization: Authorization = .unknown

    /// nil в тестах и утилитах командной строки: там UNUserNotificationCenter недоступен.
    private let center: UNUserNotificationCenter?
    private static let reminderPrefix = "reminder."
    private static let restIdentifier = "rest.end"

    public init(center: UNUserNotificationCenter?) {
        self.center = center
        refreshAuthorization()
    }

    public func refreshAuthorization() {
        guard let center = center else { return }
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .notDetermined: self?.authorization = .notDetermined
                case .denied: self?.authorization = .denied
                default: self?.authorization = .allowed
                }
            }
        }
    }

    /// Запрос разрешения. Возвращает, разрешены ли уведомления.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard let center = center else { return false }
        let granted: Bool = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        authorization = granted ? .allowed : .denied
        return granted
    }

    /// Перепланирует напоминания под текущие настройки.
    public func applyReminders(_ settings: AppSettings, onThisDevice: Bool) async {
        guard let center = center else { return }
        let pending: [UNNotificationRequest] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) })

        guard settings.remindersEnabled, onThisDevice, !settings.reminderWeekdays.isEmpty else { return }
        if authorization != .allowed {
            guard await requestAuthorization() else { return }
        }
        for weekday in settings.reminderWeekdays.sorted() {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = settings.reminderHour
            components.minute = settings.reminderMinute
            let content = UNMutableNotificationContent()
            content.title = "Время тренировки"
            content.body = "Выбери готовую тренировку или собери свою — займёт пару касаний."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "\(Self.reminderPrefix)\(weekday)", content: content, trigger: trigger))
        }
    }

    /// Уведомление об окончании отдыха — на случай, если приложение свёрнуто.
    public func scheduleRestEnd(after seconds: TimeInterval) {
        guard let center = center, authorization == .allowed, seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Отдых окончен"
        content.body = "Пора делать следующий подход."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.restIdentifier, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    public func cancelRestEnd() {
        center?.removePendingNotificationRequests(withIdentifiers: [Self.restIdentifier])
        center?.removeDeliveredNotifications(withIdentifiers: [Self.restIdentifier])
    }
}

/// Показывает уведомления и при открытом приложении (кроме «отдых окончен» — таймер и так на экране).
public final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "rest.end" {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}
