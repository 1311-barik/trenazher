import Combine
import Foundation

/// Настройки, общие для iPhone и iPad (синхронизируются через iCloud).
public struct AppSettings: Codable, Equatable {
    public static let restDurationOptions = [30, 60]

    public var restTimerEnabled = true
    /// Длительность отдыха по умолчанию, секунд. Выбрано 60 — Женя упоминала 30 или 60; меняется в Настройках.
    public var restDurationSeconds = 60
    public var remindersEnabled = false
    public var reminderHour = 19
    public var reminderMinute = 0
    /// Дни недели в нумерации Calendar: 1 — воскресенье, 2 — понедельник … 7 — суббота.
    public var reminderWeekdays: Set<Int> = [2, 4, 6]
    /// Когда настройки меняли в последний раз — побеждает более свежая версия с любого устройства.
    public var updatedAt = Date(timeIntervalSince1970: 0)

    public init() {}

    public static let schemaVersion = 1
}

/// Настройки конкретного устройства (не синхронизируются).
public struct DeviceSettings: Codable, Equatable {
    /// Скачивать видео заранее по Wi-Fi, чтобы они работали без интернета.
    public var downloadVideosInAdvance = true
    /// Присылать напоминания на это устройство (чтобы не звенели iPhone и iPad одновременно).
    public var remindersOnThisDevice = true

    public init() {}
}

/// Хранилище «ключ — значение» с синхронизацией. Протокол — чтобы в тестах подменить iCloud.
public protocol KeyValueSyncStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueSyncStore {
    public func set(_ data: Data?, forKey key: String) {
        set(data as Any?, forKey: key)
    }
}

/// Хранилище в памяти — для тестов и превью.
public final class InMemoryKeyValueStore: KeyValueSyncStore {
    private var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] }
    public func set(_ data: Data?, forKey key: String) { values[key] = data }
    public func synchronize() -> Bool { true }
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet {
            guard settings != oldValue, !isApplyingRemote else { return }
            settings.updatedAt = Date()
            persistShared()
        }
    }

    @Published public var device: DeviceSettings {
        didSet {
            guard device != oldValue else { return }
            persist(device, key: Self.deviceKey, to: defaults)
        }
    }

    private let defaults: UserDefaults
    /// nil — синхронизации нет, настройки живут только на этом устройстве.
    private let cloud: KeyValueSyncStore?
    private var isApplyingRemote = false
    private var observer: NSObjectProtocol?

    private static let sharedKey = "settings.shared.v\(AppSettings.schemaVersion)"
    private static let deviceKey = "settings.device.v1"

    public init(defaults: UserDefaults = .standard, cloud: KeyValueSyncStore? = nil) {
        self.defaults = defaults
        self.cloud = cloud
        let local = Self.decode(AppSettings.self, from: defaults.data(forKey: Self.sharedKey))
        let remote = Self.decode(AppSettings.self, from: cloud?.data(forKey: Self.sharedKey))
        settings = Self.newest(local, remote) ?? AppSettings()
        device = Self.decode(DeviceSettings.self, from: defaults.data(forKey: Self.deviceKey)) ?? DeviceSettings()

        if let store = cloud as? NSUbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.applyRemoteIfNewer() }
            }
        }
        cloud?.synchronize()
    }

    /// Общие настройки приходят и на другие устройства (iCloud подключён).
    public var isSyncedAcrossDevices: Bool { cloud != nil }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Пришли настройки с другого устройства — берём, если они новее.
    public func applyRemoteIfNewer() {
        guard let cloud = cloud,
              let remote = Self.decode(AppSettings.self, from: cloud.data(forKey: Self.sharedKey)),
              remote.updatedAt > settings.updatedAt else { return }
        isApplyingRemote = true
        settings = remote
        isApplyingRemote = false
        persist(remote, key: Self.sharedKey, to: defaults)
    }

    private func persistShared() {
        persist(settings, key: Self.sharedKey, to: defaults)
        if let cloud = cloud, let data = try? JSONEncoder().encode(settings) {
            cloud.set(data, forKey: Self.sharedKey)
            cloud.synchronize()
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func newest(_ lhs: AppSettings?, _ rhs: AppSettings?) -> AppSettings? {
        switch (lhs, rhs) {
        case let (l?, r?): return r.updatedAt > l.updatedAt ? r : l
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }
}
