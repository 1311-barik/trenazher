import Foundation

/// Скачивание отдельных файлов: общий для фоновой синхронизации и для «видео по тапу».
/// Один и тот же файл одновременно качается только один раз.
@MainActor
public final class MediaDownloader: ObservableObject {
    /// Прогресс текущих загрузок: driveFileId → 0…1.
    @Published public private(set) var progress: [String: Double] = [:]

    public let store: ContentStore
    private let source: ContentSource
    private let http: HTTPClient
    private var inFlight: [String: Task<URL, Error>] = [:]
    /// Запас свободного места, который не трогаем.
    private let reserveBytes: Int64 = 300 * 1024 * 1024

    public init(store: ContentStore, source: ContentSource, http: HTTPClient) {
        self.store = store
        self.source = source
        self.http = http
    }

    /// Лучший локальный файл (текущая версия или предыдущая, если новая ещё не скачана).
    public func localURL(for media: MediaItem) -> URL? {
        store.localURL(for: media)
    }

    public func isDownloading(_ media: MediaItem) -> Bool {
        inFlight[media.localFileName] != nil
    }

    /// Скачивает текущую версию файла (если её ещё нет) и возвращает локальный URL.
    @discardableResult
    public func fetch(_ media: MediaItem) async throws -> URL {
        if store.hasCurrentVersion(of: media) { return store.destinationURL(for: media) }
        if let running = inFlight[media.localFileName] { return try await running.value }

        guard let remote = source.downloadURL(for: media) else { throw ContentError.notConfigured }
        if let size = media.byteSize, let available = store.availableCapacity(), available - size < reserveBytes {
            throw ContentError.outOfSpace
        }
        let destination = store.destinationURL(for: media)
        let fileId = media.driveFileId
        progress[fileId] = 0
        let http = self.http
        let report: (Double) -> Void = { [weak self] value in
            Task { @MainActor in
                // Не воскрешаем запись, если загрузка уже закончилась.
                if self?.progress[fileId] != nil { self?.progress[fileId] = value }
            }
        }
        let task = Task<URL, Error> {
            try await http.download(from: remote, to: destination, progress: report)
            return destination
        }
        inFlight[media.localFileName] = task
        defer {
            inFlight[media.localFileName] = nil
            progress[fileId] = nil
        }
        do {
            let url = try await task.value
            store.registerDownloaded(media)
            return url
        } catch {
            throw ContentError.from(error)
        }
    }
}

/// Синхронизация контента: таблица → манифест → фото → видео.
/// Если связь оборвалась, уже скачанные файлы остаются, а при следующем запуске
/// докачиваются только недостающие — так приложение «продолжает с того же места».
@MainActor
public final class ContentSyncService: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case checking
        case downloading(done: Int, total: Int)
    }

    @Published public private(set) var phase: Phase = .idle
    /// Последняя ошибка — показывается рядом со статусом, контент при этом остаётся прежним.
    @Published public private(set) var lastError: ContentError?
    @Published public private(set) var lastSyncDate: Date?
    /// Сколько файлов не удалось скачать в последний раз (повторим при следующей синхронизации).
    @Published public private(set) var failedDownloads = 0
    /// Сколько файлов текущего манифеста ещё не скачано.
    @Published public private(set) var pendingDownloads = 0

    private let repository: ContentRepository
    private let source: ContentSource
    private let downloader: MediaDownloader
    private let network: NetworkMonitor
    private let defaults: UserDefaults
    private let prefetchVideos: () -> Bool
    private var runningTask: Task<Void, Never>?

    private static let lastSyncKey = "content.lastSyncDate"
    /// Автосинхронизация не чаще, чем раз в это время.
    public var autoSyncInterval: TimeInterval = 60 * 30

    public init(repository: ContentRepository, source: ContentSource, downloader: MediaDownloader, network: NetworkMonitor,
                defaults: UserDefaults = .standard, prefetchVideos: @escaping () -> Bool) {
        self.repository = repository
        self.source = source
        self.downloader = downloader
        self.network = network
        self.defaults = defaults
        self.prefetchVideos = prefetchVideos
        lastSyncDate = defaults.object(forKey: Self.lastSyncKey) as? Date
        refreshPendingCount()
    }

    public var isRunning: Bool { runningTask != nil }
    public var isConfigured: Bool { source.isConfigured }

    /// Синхронизация при запуске / возврате в приложение — только если давно не обновлялись
    /// или что-то осталось недокачанным.
    public func syncIfNeeded() {
        let stale = lastSyncDate.map { Date().timeIntervalSince($0) > autoSyncInterval } ?? true
        if stale || pendingDownloads > 0 || repository.isEmpty {
            startSync()
        }
    }

    /// Ручное «Обновить контент».
    public func startSync() {
        guard runningTask == nil else { return }
        runningTask = Task { [weak self] in
            await self?.performSync()
            self?.runningTask = nil
        }
    }

    public func waitForCurrentSync() async {
        await runningTask?.value
    }

    public func cancel() {
        runningTask?.cancel()
    }

    func performSync() async {
        guard source.isConfigured else {
            lastError = .notConfigured
            return
        }
        guard network.isConnected else {
            lastError = .offline
            return
        }
        lastError = nil
        phase = .checking

        // 1. Манифест. Ошибка здесь не трогает текущий контент.
        do {
            let snapshot = try await source.fetchSnapshot()
            let manifest = ManifestBuilder.build(from: snapshot)
            if manifest.contentVersion != repository.manifest.contentVersion || manifest.issues != repository.manifest.issues {
                try downloader.store.save(manifest)
                repository.apply(manifest)
            }
        } catch {
            lastError = ContentError.from(error)
            phase = .idle
            refreshPendingCount()
            return
        }

        // 2. Файлы: сначала фото (маленькие и нужны в списках), потом видео.
        let queue = downloadQueue()
        var done = 0
        var failed = 0
        phase = .downloading(done: 0, total: queue.count)
        for media in queue {
            if Task.isCancelled { break }
            do {
                try await downloader.fetch(media)
            } catch {
                let contentError = ContentError.from(error)
                failed += 1
                if contentError.stopsSync {
                    lastError = contentError
                    break
                }
            }
            done += 1
            phase = .downloading(done: done, total: queue.count)
        }

        failedDownloads = failed
        if failed == 0 && !Task.isCancelled && lastError == nil {
            downloader.store.removeUnreferenced(keeping: repository.manifest)
        }
        if lastError == nil {
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: Self.lastSyncKey)
        }
        phase = .idle
        refreshPendingCount()
    }

    /// Что нужно докачать: все фото; видео — только если включено «скачивать заранее» и сеть не сотовая.
    func downloadQueue() -> [MediaItem] {
        let missing = repository.manifest.allMedia.filter { !downloader.store.hasCurrentVersion(of: $0) }
        let photos = missing.filter { !$0.kind.isVideo }
        guard prefetchVideos(), !network.isExpensive else { return photos }
        // Сначала видео Жени — они короче и важнее.
        let videos = missing.filter(\.kind.isVideo).sorted { lhs, rhs in
            lhs.kind == rhs.kind ? (lhs.byteSize ?? 0) < (rhs.byteSize ?? 0) : lhs.kind == .ownVideo
        }
        return photos + videos
    }

    public func refreshPendingCount() {
        let includeVideos = prefetchVideos()
        pendingDownloads = repository.manifest.allMedia.filter {
            (includeVideos || !$0.kind.isVideo) && !downloader.store.hasCurrentVersion(of: $0)
        }.count
    }

    /// Удалить скачанные видео (кнопка в Настройках при нехватке места).
    public func removeDownloadedVideos() {
        downloader.store.removeAllVideos(in: repository.manifest)
        refreshPendingCount()
    }
}
