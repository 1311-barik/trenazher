import Foundation

/// Вид медиафайла упражнения.
public enum MediaKind: String, Codable, Hashable, CaseIterable {
    case photo
    /// Видео, снятое Женей.
    case ownVideo
    /// Чужое обучающее видео.
    case otherVideo

    public var isVideo: Bool { self != .photo }
}

/// Файл из Google Drive, привязанный к упражнению.
public struct MediaItem: Codable, Hashable, Identifiable {
    public var driveFileId: String
    public var title: String
    public var fileExtension: String
    public var kind: MediaKind
    /// md5 или время изменения файла на Drive — меняется, когда Женя заменяет файл.
    public var version: String
    public var byteSize: Int64?

    public var id: String { driveFileId }

    public init(driveFileId: String, title: String, fileExtension: String, kind: MediaKind, version: String, byteSize: Int64? = nil) {
        self.driveFileId = driveFileId
        self.title = title
        self.fileExtension = fileExtension
        self.kind = kind
        self.version = version
        self.byteSize = byteSize
    }

    /// Имя файла в локальном кэше. Версия в имени — чтобы новая версия файла
    /// не затирала старую, пока не докачается.
    public var localFileName: String {
        let ext = fileExtension.isEmpty ? (kind.isVideo ? "mov" : "jpg") : fileExtension.lowercased()
        return "\(driveFileId)_\(StableHash.hex(version)).\(ext)"
    }
}

/// Упражнение — одна строка таблицы «Дрон тренировка».
public struct Exercise: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// Часть тела — раздел таблицы (Руки, Попа, Ноги…). Список не фиксирован: берётся из таблицы.
    public var bodyPart: String
    public var muscleGroup: String?
    /// Дополнительный инвентарь сверх гантелей (колонка «Гантели +»): стул, коврик, стена…
    public var equipment: String?
    /// Текст описания техники.
    public var details: String
    /// Количество подходов — необязательное поле; если пусто, таймер работает без счётчика.
    public var sets: Int?
    public var photos: [MediaItem]
    public var videos: [MediaItem]
    /// Хеш содержимого строки и файлов — меняется при любом изменении упражнения.
    public var version: String

    public init(id: String, name: String, bodyPart: String, muscleGroup: String? = nil, equipment: String? = nil,
                details: String, sets: Int? = nil, photos: [MediaItem] = [], videos: [MediaItem] = [], version: String = "") {
        self.id = id
        self.name = name
        self.bodyPart = bodyPart
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.details = details
        self.sets = sets
        self.photos = photos
        self.videos = videos
        self.version = version
    }

    public var allMedia: [MediaItem] { photos + videos }
}

public enum WorkoutKind: String, Codable, Hashable {
    /// Готовая тренировка из списка Жени.
    case ready
    /// Собранная самостоятельно по частям тела.
    case custom

    public var title: String {
        switch self {
        case .ready: return "Готовая"
        case .custom: return "Своя"
        }
    }
}

/// Готовая тренировка — набор упражнений в порядке выполнения.
public struct Workout: Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String?
    public var exerciseIds: [String]
    public var version: String

    public init(id: String, title: String, summary: String? = nil, exerciseIds: [String], version: String = "") {
        self.id = id
        self.title = title
        self.summary = summary
        self.exerciseIds = exerciseIds
        self.version = version
    }
}

/// Замечание к контенту: что в таблице/папках не удалось разобрать или сопоставить.
public struct ContentIssue: Codable, Hashable {
    public enum Severity: String, Codable, Hashable, Comparable {
        case error, warning, info

        private var rank: Int {
            switch self {
            case .error: return 0
            case .warning: return 1
            case .info: return 2
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    public var severity: Severity
    public var message: String

    public init(_ severity: Severity, _ message: String) {
        self.severity = severity
        self.message = message
    }
}

/// Манифест — весь контент приложения, собранный из таблицы и папок Drive.
public struct ContentManifest: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAt: Date
    /// Части тела в порядке таблицы.
    public var bodyParts: [String]
    public var exercises: [Exercise]
    public var workouts: [Workout]
    public var issues: [ContentIssue]
    /// Версия всего контента — для быстрой проверки «изменилось ли что-то».
    public var contentVersion: String

    public init(schemaVersion: Int = ContentManifest.currentSchemaVersion, generatedAt: Date, bodyParts: [String],
                exercises: [Exercise], workouts: [Workout], issues: [ContentIssue], contentVersion: String) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.bodyParts = bodyParts
        self.exercises = exercises
        self.workouts = workouts
        self.issues = issues
        self.contentVersion = contentVersion
    }

    public static let empty = ContentManifest(generatedAt: Date(timeIntervalSince1970: 0), bodyParts: [], exercises: [],
                                              workouts: [], issues: [], contentVersion: "")

    public var isEmpty: Bool { exercises.isEmpty }

    /// Все медиафайлы манифеста без повторов (один файл может быть у нескольких упражнений).
    public var allMedia: [MediaItem] {
        var seen = Set<String>()
        var result: [MediaItem] = []
        for item in exercises.flatMap(\.allMedia) where seen.insert(item.localFileName).inserted {
            result.append(item)
        }
        return result
    }
}
