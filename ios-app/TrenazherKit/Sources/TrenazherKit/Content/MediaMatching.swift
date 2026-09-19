import Foundation

/// Файл в папке Google Drive (то, что возвращает Drive API files.list).
public struct DriveFile: Codable, Hashable {
    public var id: String
    /// Имя файла вместе с расширением, как на Drive: «Бицепс. Молот.JPG».
    public var name: String
    public var mimeType: String
    public var md5Checksum: String?
    public var modifiedTime: String?
    public var size: Int64?

    public init(id: String, name: String, mimeType: String = "", md5Checksum: String? = nil, modifiedTime: String? = nil, size: Int64? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.md5Checksum = md5Checksum
        self.modifiedTime = modifiedTime
        self.size = size
    }

    static let mediaExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "mov", "mp4", "m4v"]

    /// Имя без расширения.
    public var baseName: String {
        let ext = (name as NSString).pathExtension
        guard Self.mediaExtensions.contains(ext.lowercased()) else { return TextNormalizer.trimmed(name) }
        return TextNormalizer.trimmed((name as NSString).deletingPathExtension)
    }

    public var fileExtension: String {
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.mediaExtensions.contains(ext) { return ext }
        if mimeType.contains("quicktime") { return "mov" }
        if mimeType.contains("mp4") { return "mp4" }
        if mimeType.contains("png") { return "png" }
        if mimeType.hasPrefix("image/") { return "jpg" }
        return ext
    }

    public var isFolder: Bool { mimeType == "application/vnd.google-apps.folder" }

    func mediaItem(kind: MediaKind) -> MediaItem {
        MediaItem(driveFileId: id, title: baseName, fileExtension: fileExtension, kind: kind,
                  version: md5Checksum ?? modifiedTime ?? id, byteSize: size)
    }
}

/// Что написано в ячейке «Фото» / «Чужое видео» / «Женя видео».
public enum MediaCellDirective: Equatable {
    /// Пусто или «есть» — ищем файл автоматически по названию упражнения.
    /// `expected == true`, если Женя написала «есть»: тогда ненайденный файл — это замечание.
    case auto(expected: Bool)
    /// «нет», «нет и не будет», «-» — файла нет и искать не нужно.
    case none
    /// Явные ссылки на файлы: имена файлов или ссылки на Drive (по одной в строке или через «;»).
    case explicit([MediaReference])
}

public enum MediaReference: Equatable {
    case fileId(String)
    case fileName(String)
}

public enum MediaCellParser {
    private static let presentMarkers: Set<String> = ["есть", "да", "есть файл", "yes"]
    private static let driveIdPatterns = [
        try! NSRegularExpression(pattern: "/d/([A-Za-z0-9_-]{10,})"),
        try! NSRegularExpression(pattern: "[?&]id=([A-Za-z0-9_-]{10,})"),
    ]
    private static let bareIdPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{25,}$")

    public static func parse(_ cell: String) -> MediaCellDirective {
        let text = TextNormalizer.trimmed(cell)
        if text.isEmpty { return .auto(expected: false) }
        if text == "+" { return .auto(expected: true) }
        if ["-", "—", "–"].contains(text) { return .none }
        let key = TextNormalizer.key(text)
        if presentMarkers.contains(key) { return .auto(expected: true) }
        if key == "нет" || key.hasPrefix("нет ") { return .none }

        let tokens = text.components(separatedBy: CharacterSet(charactersIn: "\n;"))
            .map(TextNormalizer.trimmed)
            .filter { !$0.isEmpty }
        let references = tokens.map { token -> MediaReference in
            if let id = driveId(in: token) { return .fileId(id) }
            return .fileName(token)
        }
        return references.isEmpty ? .auto(expected: false) : .explicit(references)
    }

    /// ID файла из ссылки Drive («https://drive.google.com/file/d/<id>/view») или «голый» ID.
    public static func driveId(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        if text.contains("google.com") {
            for pattern in driveIdPatterns {
                if let match = pattern.firstMatch(in: text, range: range), let idRange = Range(match.range(at: 1), in: text) {
                    return String(text[idRange])
                }
            }
            return nil
        }
        if bareIdPattern.firstMatch(in: text, range: range) != nil, !text.contains(" ") {
            return text
        }
        return nil
    }
}

/// Сопоставление файлов из папки Drive с упражнением.
/// Правила однозначные (без «похожих» названий), чтобы файл не прицепился не к тому упражнению:
/// - явная ссылка/имя в ячейке — всегда главнее;
/// - автоматически файл подходит, если его имя без раздела-приставки и без номера
///   совпадает с названием упражнения: «Пресс. Мертвый жук.JPG», «Попа. Болгарские выпады. 1.mov».
public struct MediaMatcher {
    public let files: [DriveFile]
    private let byId: [String: DriveFile]

    public init(files: [DriveFile]) {
        self.files = files.filter { !$0.isFolder }.sorted { naturalLess($0.baseName, $1.baseName) }
        var index: [String: DriveFile] = [:]
        for file in self.files { index[file.id] = file }
        self.byId = index
    }

    /// Все варианты ключа для имени файла: целиком и без ведущих «Раздел.» приставок.
    static func keys(forTitle title: String, stripNumbering: Bool) -> Set<String> {
        var base = title
        if stripNumbering {
            base = numberingSuffix.stringByReplacingMatches(in: base, range: NSRange(base.startIndex..., in: base), withTemplate: "")
        }
        let segments = base.components(separatedBy: ".").map(TextNormalizer.trimmed).filter { !$0.isEmpty }
        var result = Set<String>()
        for start in segments.indices {
            let key = TextNormalizer.key(segments[start...].joined(separator: " "))
            if !key.isEmpty { result.insert(key) }
        }
        return result
    }

    /// «… 2», «…. 1», «… вар 2», «… вариант 3» в конце имени.
    private static let numberingSuffix = try! NSRegularExpression(pattern: "[\\s.]*((вар|вариант)\\.?\\s*)?\\d+\\s*$", options: [.caseInsensitive])

    /// Автопоиск по названию упражнения.
    public func autoMatches(forExerciseNamed name: String) -> [DriveFile] {
        let target = TextNormalizer.key(name)
        guard !target.isEmpty else { return [] }
        return files.filter { Self.keys(forTitle: $0.baseName, stripNumbering: true).contains(target) }
    }

    /// Похожие файлы — только как подсказка в отчёте для Жени. Приложение по ним ничего не привязывает:
    /// решение за человеком, который впишет имя файла в ячейку.
    public func suggestions(forExerciseNamed name: String, limit: Int = 2) -> [DriveFile] {
        let target = Self.stems(name)
        guard !target.isEmpty else { return [] }
        let scored: [(file: DriveFile, score: Double)] = files.compactMap { file in
            let segments = file.baseName.components(separatedBy: ".").map(TextNormalizer.trimmed).filter { !$0.isEmpty }
            var best = 0.0
            for start in segments.indices {
                let candidate = Self.stems(segments[start...].joined(separator: " "))
                guard !candidate.isEmpty else { continue }
                let common = Double(target.intersection(candidate).count)
                let dice = 2 * common / Double(target.count + candidate.count)
                let coverage = common / Double(candidate.count)
                best = max(best, (dice + coverage) / 2)
            }
            return best >= 0.5 ? (file, best) : nil
        }
        return scored.sorted { $0.score == $1.score ? naturalLess($0.file.baseName, $1.file.baseName) : $0.score > $1.score }
            .prefix(limit).map(\.file)
    }

    private static let stopWords: Set<String> = ["в", "во", "с", "со", "на", "из", "за", "под", "от", "к", "ко", "и", "для", "по", "до", "у"]

    /// Грубые основы слов: «гантелей» и «гантели» → «ганте», «лёжа» и «лежа» → «леж».
    static func stems(_ text: String) -> Set<String> {
        var result = Set<String>()
        for token in TextNormalizer.key(text).split(separator: " ") {
            let word = String(token)
            if stopWords.contains(word) || word.allSatisfy(\.isNumber) { continue }
            let length: Int = word.count <= 3 ? word.count : max(3, min(5, word.count - 1))
            result.insert(String(word.prefix(length)))
        }
        return result
    }

    public enum Resolution: Equatable {
        case found(DriveFile)
        case notFound
        case ambiguous([DriveFile])
    }

    /// Поиск по явной ссылке из ячейки.
    public func resolve(_ reference: MediaReference) -> Resolution {
        switch reference {
        case .fileId(let id):
            return byId[id].map(Resolution.found) ?? .notFound
        case .fileName(let name):
            let target = TextNormalizer.key(stripExtension(name))
            let exact = files.filter { TextNormalizer.key($0.baseName) == target }
            if exact.count == 1 { return .found(exact[0]) }
            if exact.count > 1 { return .ambiguous(exact) }
            // Разрешаем писать имя без приставки раздела: «Молот 2» вместо «Бицепс. Молот 2».
            let partial = files.filter { Self.keys(forTitle: $0.baseName, stripNumbering: false).contains(target) }
            if partial.count == 1 { return .found(partial[0]) }
            if partial.count > 1 { return .ambiguous(partial) }
            return .notFound
        }
    }

    private func stripExtension(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        return DriveFile.mediaExtensions.contains(ext) ? (name as NSString).deletingPathExtension : name
    }
}

/// Сравнение строк «как в Finder»: «Молот 2» < «Молот 10».
func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
    lhs.compare(rhs, options: [.numeric, .caseInsensitive], range: nil, locale: Locale(identifier: "ru_RU")) == .orderedAscending
}
