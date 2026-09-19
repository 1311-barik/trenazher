import Foundation

/// Откуда брать контент.
public protocol ContentSource: AnyObject {
    var isConfigured: Bool { get }
    func fetchSnapshot() async throws -> ContentSnapshot
    func downloadURL(for media: MediaItem) -> URL?
}

/// Настройки доступа к Google. Значения попадают в Info.plist из Config/Secrets.xcconfig.
public struct GoogleContentConfig: Equatable {
    public var apiKey: String
    public var spreadsheetId: String
    public var rootFolderId: String
    public var photosFolderName = "Фото упражнений"
    public var ownVideosFolderName = "Женя видео"
    public var otherVideosFolderName = "Чужие видео"

    public init(apiKey: String, spreadsheetId: String, rootFolderId: String) {
        self.apiKey = apiKey
        self.spreadsheetId = spreadsheetId
        self.rootFolderId = rootFolderId
    }

    public var isConfigured: Bool {
        !apiKey.isEmpty && !spreadsheetId.isEmpty && !rootFolderId.isEmpty && !apiKey.hasPrefix("$(")
    }
}

/// Читает таблицу и папки напрямую через Google Sheets API и Drive API по read-only API-ключу
/// (без OAuth и без своего сервера). Требование: таблица и папка открыты «всем, у кого есть ссылка».
/// Женя правит таблицу → приложение подтягивает изменения при следующей синхронизации.
public final class GoogleContentSource: ContentSource {
    public let config: GoogleContentConfig
    private let http: HTTPClient

    public init(config: GoogleContentConfig, http: HTTPClient) {
        self.config = config
        self.http = http
    }

    public var isConfigured: Bool { config.isConfigured }

    public func fetchSnapshot() async throws -> ContentSnapshot {
        guard isConfigured else { throw ContentError.notConfigured }
        var issues: [ContentIssue] = []

        // 1. Листы таблицы: первый — упражнения, лист со словом «трениров» — готовые тренировки.
        let sheetTitles = try await fetchSheetTitles()
        guard let exerciseSheet = sheetTitles.first else { throw ContentError.notFound("листы в таблице") }
        let workoutSheet = sheetTitles.dropFirst().first { TextNormalizer.key($0).contains("трениров") }
        let exerciseRows = try await fetchValues(sheet: exerciseSheet)
        var workoutRows: [[String]] = []
        if let workoutSheet = workoutSheet {
            workoutRows = try await fetchValues(sheet: workoutSheet)
        }

        // 2. Папки с медиа внутри корневой папки «Андрей тренировка».
        let rootItems = try await listFolder(config.rootFolderId)
        func folder(named name: String) -> String? {
            rootItems.first { $0.isFolder && TextNormalizer.key($0.name) == TextNormalizer.key(name) }?.id
        }
        func files(inFolderNamed name: String) async throws -> [DriveFile] {
            guard let id = folder(named: name) else {
                issues.append(ContentIssue(.error, "В папке на Drive не найдена подпапка «\(name)»."))
                return []
            }
            return try await listFolder(id).filter { !$0.isFolder }
        }
        let photos = try await files(inFolderNamed: config.photosFolderName)
        let ownVideos = try await files(inFolderNamed: config.ownVideosFolderName)
        let otherVideos = try await files(inFolderNamed: config.otherVideosFolderName)

        return ContentSnapshot(exerciseRows: exerciseRows, workoutRows: workoutRows, photos: photos,
                               ownVideos: ownVideos, otherVideos: otherVideos, issues: issues)
    }

    public func downloadURL(for media: MediaItem) -> URL? {
        guard isConfigured else { return nil }
        return url("https://www.googleapis.com/drive/v3/files/\(Self.encode(media.driveFileId))",
                   query: ["alt": "media", "acknowledgeAbuse": "true", "supportsAllDrives": "true"])
    }

    // MARK: - Sheets API

    private struct SpreadsheetDTO: Decodable {
        struct Sheet: Decodable {
            struct Properties: Decodable {
                var title: String
                var index: Int?
            }
            var properties: Properties
        }
        var sheets: [Sheet]
    }

    private struct ValuesDTO: Decodable {
        var values: [[String]]?
    }

    func fetchSheetTitles() async throws -> [String] {
        let url = self.url("https://sheets.googleapis.com/v4/spreadsheets/\(Self.encode(config.spreadsheetId))",
                           query: ["fields": "sheets.properties(title,index)"])
        let dto: SpreadsheetDTO = try await getJSON(url)
        return dto.sheets.sorted { ($0.properties.index ?? 0) < ($1.properties.index ?? 0) }.map(\.properties.title)
    }

    func fetchValues(sheet: String) async throws -> [[String]] {
        // Имя листа в кавычках — на случай пробелов; строки берём как отформатированный текст.
        let range = "'\(sheet.replacingOccurrences(of: "'", with: "''"))'"
        let url = self.url("https://sheets.googleapis.com/v4/spreadsheets/\(Self.encode(config.spreadsheetId))/values/\(Self.encode(range))",
                           query: ["majorDimension": "ROWS", "valueRenderOption": "FORMATTED_VALUE"])
        let dto: ValuesDTO = try await getJSON(url)
        return dto.values ?? []
    }

    // MARK: - Drive API

    private struct FileListDTO: Decodable {
        struct File: Decodable {
            var id: String
            var name: String
            var mimeType: String
            var md5Checksum: String?
            var modifiedTime: String?
            var size: String?
        }
        var files: [File]
        var nextPageToken: String?
    }

    func listFolder(_ folderId: String) async throws -> [DriveFile] {
        var result: [DriveFile] = []
        var pageToken: String?
        repeat {
            var query = [
                "q": "'\(folderId)' in parents and trashed = false",
                "fields": "nextPageToken,files(id,name,mimeType,md5Checksum,modifiedTime,size)",
                "pageSize": "1000",
                "supportsAllDrives": "true",
                "includeItemsFromAllDrives": "true",
            ]
            if let token = pageToken { query["pageToken"] = token }
            let dto: FileListDTO = try await getJSON(url("https://www.googleapis.com/drive/v3/files", query: query))
            result += dto.files.map {
                DriveFile(id: $0.id, name: $0.name, mimeType: $0.mimeType, md5Checksum: $0.md5Checksum,
                          modifiedTime: $0.modifiedTime, size: $0.size.flatMap { Int64($0) })
            }
            pageToken = dto.nextPageToken
        } while pageToken != nil
        return result
    }

    // MARK: - Helpers

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await http.data(from: url)
        } catch {
            throw ContentError.from(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleErrorMapper.error(status: response.statusCode, body: data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ContentError.invalidData(error.localizedDescription)
        }
    }

    private func url(_ base: String, query: [String: String]) -> URL {
        var items = query.map { "\(Self.encode($0.key))=\(Self.encode($0.value))" }.sorted()
        items.append("key=\(Self.encode(config.apiKey))")
        // Кодируем вручную: URLComponents не кодирует «+» и «'», а URL(string:) не принимает кириллицу.
        return URL(string: base + "?" + items.joined(separator: "&"))!
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}

/// Источник контента для превью и тестов: отдаёт заранее заданный снимок.
public final class StaticContentSource: ContentSource {
    public var snapshot: ContentSnapshot?
    public var error: ContentError?

    public init(snapshot: ContentSnapshot?, error: ContentError? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    public var isConfigured: Bool { snapshot != nil || error != nil }

    public func fetchSnapshot() async throws -> ContentSnapshot {
        if let error = error { throw error }
        guard let snapshot = snapshot else { throw ContentError.notConfigured }
        return snapshot
    }

    public func downloadURL(for media: MediaItem) -> URL? {
        URL(string: "https://example.invalid/\(media.driveFileId)")
    }
}
