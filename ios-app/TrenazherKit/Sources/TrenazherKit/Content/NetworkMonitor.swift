import Foundation
import Network

/// Есть ли интернет и дорогой ли он (сотовая сеть / режим модема).
@MainActor
public final class NetworkMonitor: ObservableObject {
    @Published public private(set) var isConnected: Bool
    /// Сотовая сеть или точка доступа — видео заранее не качаем.
    @Published public private(set) var isExpensive: Bool

    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "trenazher.network")

    public init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        isConnected = true
        isExpensive = false
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                self?.isConnected = connected
                self?.isExpensive = expensive
            }
        }
        monitor.start(queue: queue)
    }

    /// Фиксированное состояние — для превью и тестов.
    public init(fixedConnected: Bool, expensive: Bool = false) {
        monitor = nil
        isConnected = fixedConnected
        isExpensive = expensive
    }

    deinit {
        monitor?.cancel()
    }
}
