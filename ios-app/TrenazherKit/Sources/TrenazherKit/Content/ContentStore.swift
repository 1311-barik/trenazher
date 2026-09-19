import Foundation

/// Локальный кэш контента: manifest.json + папка media/.
/// Контента немного (десятки упражнений), поэтому хватает JSON-файла — без Core Data/GRDB.
/// Папка исключена из резервной копии iCloud: всё можно скачать заново.
public final class ContentStore {
    public let rootURL: URL
    public let manifestURL: URL
    public let mediaURL: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    /// driveFileId → имена скачанных файлов (все версии).
    private var index: [String: Set<String>] = [:]

    public init(rootURL: URL) {
        self.rootURL = rootURL
        self.manifestURL = rootURL.appendingPathComponent("manifest.json")
        self.mediaURL = rootURL.appendingPathComponent("media", isDirectory: true)
        try? fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        var root = rootURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        rebuildIndex()
    }

    public static func defaultRootURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Content", isDirectory: true)
    }

    // MARK: - Манифест

    public func loadManifest() -> ContentManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        guard let manifest = try? Self.decoder.decode(ContentManifest.self, from: data),
              manifest.schemaVersion == ContentManifest.currentSchemaVersion else { return nil }
        return manifest
    }

    public func save(_ manifest: ContentManifest) throws {
        let data = try Self.encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Медиа

    public func destinationURL(for media: MediaItem) -> URL {
        mediaURL.appendingPathComponent(media.localFileName)
    }

    /// Скачана ли именно эта версия файла.
    public func hasCurrentVersion(of media: MediaItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return index[media.driveFileId]?.contains(media.localFileName) == true
    }

    /// Лучший доступный локальный файл: текущая версия, а если её ещё нет — предыдущая
    /// (старое фото лучше пустого места, пока новое докачивается).
    public func localURL(for media: MediaItem) -> URL? {
        lock.lock()
        let names = index[media.driveFileId] ?? []
        lock.unlock()
        if names.contains(media.localFileName) { return destinationURL(for: media) }
        guard let fallback = names.sorted().last else { return nil }
        return mediaURL.appendingPathComponent(fallback)
    }

    /// Вызывается после успешной загрузки файла.
    public func registerDownloaded(_ media: MediaItem) {
        lock.lock()
        index[media.driveFileId, default: []].insert(media.localFileName)
        lock.unlock()
    }

    /// Удаляет файлы, которых нет в манифесте (старые версии и удалённые упражнения).
    public func removeUnreferenced(keeping manifest: ContentManifest) {
        let keep = Set(manifest.allMedia.map(\.localFileName))
        for name in (try? fileManager.contentsOfDirectory(atPath: mediaURL.path)) ?? [] where !keep.contains(name) {
            try? fileManager.removeItem(at: mediaURL.appendingPathComponent(name))
        }
        rebuildIndex()
    }

    /// Удаляет все скачанные видео, чтобы освободить место (при просмотре скачаются заново).
    public func removeAllVideos(in manifest: ContentManifest) {
        let videoIds = Set(manifest.allMedia.filter { $0.kind.isVideo }.map(\.driveFileId))
        for name in (try? fileManager.contentsOfDirectory(atPath: mediaURL.path)) ?? [] {
            let fileId = Self.fileId(fromLocalName: name)
            let isVideoExtension = ["mov", "mp4", "m4v"].contains((name as NSString).pathExtension.lowercased())
            if videoIds.contains(fileId) || isVideoExtension {
                try? fileManager.removeItem(at: mediaURL.appendingPathComponent(name))
            }
        }
        rebuildIndex()
    }

    /// Сколько места занимают скачанные файлы.
    public func diskUsage() -> (photos: Int64, videos: Int64) {
        var photos: Int64 = 0
        var videos: Int64 = 0
        for name in (try? fileManager.contentsOfDirectory(atPath: mediaURL.path)) ?? [] {
            let url = mediaURL.appendingPathComponent(name)
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) { videos += size } else { photos += size }
        }
        return (photos, videos)
    }

    /// Свободное место на устройстве с учётом того, что система может освободить.
    public func availableCapacity() -> Int64? {
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    private func rebuildIndex() {
        var newIndex: [String: Set<String>] = [:]
        for name in (try? fileManager.contentsOfDirectory(atPath: mediaURL.path)) ?? [] where !name.hasPrefix(".") {
            newIndex[Self.fileId(fromLocalName: name), default: []].insert(name)
        }
        lock.lock()
        index = newIndex
        lock.unlock()
    }

    /// «<driveFileId>_<хеш версии>.<ext>» → driveFileId. ID Drive может содержать «_», поэтому режем по последнему.
    static func fileId(fromLocalName name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        guard let separator = stem.lastIndex(of: "_") else { return stem }
        return String(stem[..<separator])
    }
}
