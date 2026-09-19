import Combine
import Foundation

/// Таймер отдыха между подходами. Считает от времени окончания, а не тиками —
/// поэтому не «отстаёт», если приложение свернули.
@MainActor
public final class RestTimer: ObservableObject {
    public enum State: Equatable {
        case idle
        case running(endsAt: Date, total: Int)
        /// Отдых закончился — короткое сообщение на экране.
        case finished
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var remaining: Int = 0

    private var ticker: AnyCancellable?
    private var finishedReset: AnyCancellable?
    private let notifications: NotificationScheduler?
    private let now: () -> Date
    /// Вызывается, когда отдых закончился при открытом приложении (звук/вибрация).
    public var onFinish: (() -> Void)?

    public init(notifications: NotificationScheduler?, now: @escaping () -> Date = Date.init) {
        self.notifications = notifications
        self.now = now
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var progress: Double {
        guard case .running(_, let total) = state, total > 0 else { return 0 }
        return Double(total - remaining) / Double(total)
    }

    public func start(seconds: Int) {
        guard seconds > 0 else { return }
        finishedReset = nil
        let end = now().addingTimeInterval(TimeInterval(seconds))
        state = .running(endsAt: end, total: seconds)
        remaining = seconds
        notifications?.scheduleRestEnd(after: TimeInterval(seconds))
        ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    /// «+15 с».
    public func extend(by seconds: Int) {
        guard case .running(let end, let total) = state else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        state = .running(endsAt: newEnd, total: total + seconds)
        notifications?.cancelRestEnd()
        notifications?.scheduleRestEnd(after: newEnd.timeIntervalSince(now()))
        tick()
    }

    /// «Пропустить» — отдых прерван, без сигнала.
    public func stop() {
        ticker = nil
        finishedReset = nil
        notifications?.cancelRestEnd()
        state = .idle
        remaining = 0
    }

    /// Пересчёт после возврата из фона.
    public func tick() {
        guard case .running(let end, _) = state else { return }
        let left = Int(ceil(end.timeIntervalSince(now())))
        if left <= 0 {
            ticker = nil
            remaining = 0
            state = .finished
            notifications?.cancelRestEnd()
            onFinish?()
            finishedReset = Just(()).delay(for: .seconds(3), scheduler: RunLoop.main).sink { [weak self] in
                Task { @MainActor [weak self] in
                    if self?.state == .finished { self?.state = .idle }
                }
            }
        } else {
            remaining = left
        }
    }
}
