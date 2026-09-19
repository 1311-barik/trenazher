import Foundation
import Testing
@testable import TrenazherKit

/// Реальная выгрузка таблицы «Дрон тренировка» и список файлов папок Drive на 2026-09-18.
enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }

    static var sheetRows: [[String]] {
        CSVParser.parse(try! String(contentsOf: url("drone-trenirovka-2026-09-18.csv"), encoding: .utf8))
    }

    struct Listing: Decodable {
        var photos: [DriveFile]
        var ownVideos: [DriveFile]
        var otherVideos: [DriveFile]
    }

    static var listing: Listing {
        try! JSONDecoder().decode(Listing.self, from: Data(contentsOf: url("drive-files-2026-09-18.json")))
    }

    static var snapshot: ContentSnapshot {
        let files = listing
        return ContentSnapshot(exerciseRows: sheetRows, photos: files.photos, ownVideos: files.ownVideos, otherVideos: files.otherVideos)
    }
}

@Suite("Разбор таблицы упражнений")
struct SheetParserTests {
    @Test func parsesRealSheet() {
        let (rows, issues) = ExerciseSheetParser.parse(Fixtures.sheetRows)
        #expect(rows.count == 40)
        #expect(issues.isEmpty)
        // Часть тела и группа мышц записаны только в первой строке раздела — должны протянуться вниз.
        let hammer = rows.first { $0.name == "Молот" }
        #expect(hammer?.bodyPart == "Руки")
        #expect(hammer?.muscleGroup == "Бицепс")
        // Новый раздел сбрасывает группу мышц: у «Грудь» группы нет, а не «Комплексные упражнения на плечи».
        #expect(rows.first { $0.name == "Жим гантелей лёжа — обычный" }?.muscleGroup == nil)
        // Точка в конце названия убирается.
        #expect(rows.contains { $0.name == "Медвежья планка в динамике" })
        #expect(rows.first { $0.name == "Подъем гантели из-за головы" }?.equipment == "стул")
        #expect(rows.first { $0.name == "Молот" }?.details.hasPrefix("Исходное положение:\nРуки вдоль тела") == true)
    }

    @Test func bodyPartsFollowSheetOrder() {
        let manifest = ManifestBuilder.build(from: Fixtures.snapshot)
        #expect(manifest.bodyParts == ["Руки", "Попа", "Ноги", "Живот", "Плечи", "Грудь", "Спина", "Смесь мышц"])
    }

    @Test func findsColumnsByHeaderInAnyOrder() {
        let rows = [
            ["Упражнение", "Подходы", "Часть тела", "Текст описания"],
            ["Молот", "3", "Руки", "Описание"],
            ["Классика", "4 подхода", "", "Ещё"],
        ]
        let (parsed, issues) = ExerciseSheetParser.parse(rows)
        #expect(issues.isEmpty)
        #expect(parsed.map(\.sets) == [3, 4])
        #expect(parsed.map(\.bodyPart) == ["Руки", "Руки"])
    }

    @Test func reportsRowWithoutBodyPart() {
        let (parsed, issues) = ExerciseSheetParser.parse([["Часть тела", "Упражнение"], ["", "Сироткa"]])
        #expect(parsed.isEmpty)
        #expect(issues.contains { $0.message.contains("не указана часть тела") })
    }

    @Test func parsesCSVWithMultilineQuotedFields() {
        let rows = CSVParser.parse("a,\"b\nc\",\"d \"\"e\"\"\"\r\n,,x\n")
        #expect(rows == [["a", "b\nc", "d \"e\""], ["", "", "x"]])
    }
}

@Suite("Ячейки с файлами и сопоставление")
struct MediaMatchingTests {
    @Test func parsesCellDirectives() {
        #expect(MediaCellParser.parse("") == .auto(expected: false))
        #expect(MediaCellParser.parse(" есть ") == .auto(expected: true))
        #expect(MediaCellParser.parse("нет и не будет") == .none)
        #expect(MediaCellParser.parse("Бицепс. Молот; Бицепс. Молот 2") == .explicit([.fileName("Бицепс. Молот"), .fileName("Бицепс. Молот 2")]))
        #expect(MediaCellParser.parse("https://drive.google.com/file/d/1Mj3NYgGAkacWrYlBO1Y9GscOlASpNxLk/view?usp=drivesdk")
                == .explicit([.fileId("1Mj3NYgGAkacWrYlBO1Y9GscOlASpNxLk")]))
        #expect(MediaCellParser.parse("https://drive.google.com/open?id=1Mj3NYgGAkacWrYlBO1Y9GscOlASpNxLk")
                == .explicit([.fileId("1Mj3NYgGAkacWrYlBO1Y9GscOlASpNxLk")]))
    }

    @Test func autoMatchStripsSectionPrefixAndNumbering() {
        let matcher = MediaMatcher(files: [
            DriveFile(id: "1", name: "Бицепс. Молот 2.JPG"),
            DriveFile(id: "2", name: "Бицепс. Молот.JPG"),
            DriveFile(id: "3", name: "Бицепс. Диагональный молот.JPG"),
            DriveFile(id: "4", name: "Попа. Болгарские выпады. 1.mov"),
            DriveFile(id: "5", name: "Попа. Румынка вар 2.mov"),
        ])
        // «Молот» не цепляет «Диагональный молот», порядок — естественный.
        #expect(matcher.autoMatches(forExerciseNamed: "Молот").map(\.id) == ["2", "1"])
        #expect(matcher.autoMatches(forExerciseNamed: "Болгарские выпады").map(\.id) == ["4"])
        #expect(matcher.autoMatches(forExerciseNamed: "Румынка").map(\.id) == ["5"])
        #expect(matcher.autoMatches(forExerciseNamed: "Диагональный молот").map(\.id) == ["3"])
    }

    @Test func explicitNameMayOmitSectionPrefix() {
        let matcher = MediaMatcher(files: [
            DriveFile(id: "1", name: "Бицепс. Молот 2.JPG"),
            DriveFile(id: "2", name: "Трицепс. Молот 2.JPG"),
            DriveFile(id: "3", name: "Трицепс. Французский жим.JPG"),
        ])
        #expect(matcher.resolve(.fileName("бицепс. молот 2.jpg")) == .found(DriveFile(id: "1", name: "Бицепс. Молот 2.JPG")))
        #expect(matcher.resolve(.fileName("Французский жим")) == .found(DriveFile(id: "3", name: "Трицепс. Французский жим.JPG")))
        if case .ambiguous(let files) = matcher.resolve(.fileName("Молот 2")) {
            #expect(files.count == 2)
        } else {
            Issue.record("Ожидалась неоднозначность")
        }
        #expect(matcher.resolve(.fileName("Жим лёжа")) == .notFound)
    }

    @Test func explicitCellWinsOverAutoMatch() {
        let rows = [
            ["Часть тела", "Упражнение", "Фото"],
            ["Руки", "Молот", "Бицепс. Молот 2"],
        ]
        let photos = [DriveFile(id: "a", name: "Бицепс. Молот.JPG"), DriveFile(id: "b", name: "Бицепс. Молот 2.JPG")]
        let manifest = ManifestBuilder.build(from: ContentSnapshot(exerciseRows: rows, photos: photos))
        #expect(manifest.exercises.first?.photos.map(\.driveFileId) == ["b"])
    }

    @Test func realContentMatchesOnlyUnambiguousFiles() {
        let manifest = ManifestBuilder.build(from: Fixtures.snapshot)
        func exercise(_ name: String) -> Exercise { manifest.exercises.first { $0.name == name }! }

        #expect(exercise("Мертвый жук").photos.map(\.title) == ["Пресс. Мертвый жук"])
        #expect(exercise("Мертвый жук").videos.map(\.kind) == [.ownVideo, .otherVideo])
        #expect(exercise("Молот").photos.map(\.title) == ["Бицепс. Молот", "Бицепс. Молот 2"])
        // Видео Жени идут первыми.
        #expect(exercise("Подъем рук вперед").videos.first?.kind == .ownVideo)
        // Не угадываем: «Классика подъем гантели…» ≠ «Бицепс. Классика» — нужна явная ссылка в ячейке.
        #expect(exercise("Классика подъем гантели со сгибанием локтя").photos.isEmpty)
        // «нет и не будет» — видео Жени не ищем и не жалуемся.
        #expect(!manifest.issues.contains { $0.message.contains("Болгарские выпады") && $0.message.contains("Женя видео") })
        // Для «есть» без файла — замечание с подсказкой, которую человек может принять или отвергнуть.
        #expect(manifest.issues.contains {
            $0.severity == .warning && $0.message.contains("«Шраги с гантелями», колонка «Фото»") && $0.message.contains("«Спина. Шраги»")
        })
    }

    @Test func versionChangesWhenFileIsReplaced() {
        let rows = [["Часть тела", "Упражнение"], ["Руки", "Молот"]]
        let old = ManifestBuilder.build(from: ContentSnapshot(exerciseRows: rows, photos: [DriveFile(id: "1", name: "Руки. Молот.jpg", md5Checksum: "aaa")]))
        let new = ManifestBuilder.build(from: ContentSnapshot(exerciseRows: rows, photos: [DriveFile(id: "1", name: "Руки. Молот.jpg", md5Checksum: "bbb")]))
        #expect(old.exercises[0].id == new.exercises[0].id)
        #expect(old.exercises[0].version != new.exercises[0].version)
        #expect(old.contentVersion != new.contentVersion)
        #expect(old.exercises[0].photos[0].localFileName != new.exercises[0].photos[0].localFileName)
    }
}

@Suite("Готовые тренировки")
struct WorkoutSheetTests {
    @Test func buildsWorkoutsFromSheet() {
        let workoutRows = [
            ["Тренировка", "Описание", "Упражнение"],
            ["Руки и пресс", "Короткая, 40 минут", "Молот"],
            ["", "", "Мертвый жук"],
            ["", "", "Несуществующее"],
            [],
            ["Спина v2", "", "Спина. Вокруг света"],
        ]
        var snapshot = Fixtures.snapshot
        snapshot.workoutRows = workoutRows
        let manifest = ManifestBuilder.build(from: snapshot)
        #expect(manifest.workouts.map(\.title) == ["Руки и пресс", "Спина v2"])
        #expect(manifest.workouts[0].summary == "Короткая, 40 минут")
        #expect(manifest.workouts[0].exerciseIds == ["руки/молот", "живот/мертвый жук"])
        #expect(manifest.workouts[1].exerciseIds == ["спина/вокруг света"])
        #expect(manifest.issues.contains { $0.message.contains("«Несуществующее» не найдено") })
    }
}

@Suite("Локальный кэш")
struct ContentStoreTests {
    @Test func keepsPreviousVersionUntilNewOneIsDownloaded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentStore(rootURL: root)
        let v1 = MediaItem(driveFileId: "abc_1", title: "Фото", fileExtension: "jpg", kind: .photo, version: "v1")
        var v2 = v1
        v2.version = "v2"

        try Data("old".utf8).write(to: store.destinationURL(for: v1))
        store.registerDownloaded(v1)
        #expect(store.hasCurrentVersion(of: v1))
        #expect(!store.hasCurrentVersion(of: v2))
        // Новая версия ещё не скачана — показываем старую.
        #expect(store.localURL(for: v2) == store.destinationURL(for: v1))

        try Data("new".utf8).write(to: store.destinationURL(for: v2))
        store.registerDownloaded(v2)
        let manifest = ContentManifest(generatedAt: Date(), bodyParts: ["Руки"],
                                       exercises: [Exercise(id: "x", name: "X", bodyPart: "Руки", details: "", photos: [v2])],
                                       workouts: [], issues: [], contentVersion: "1")
        store.removeUnreferenced(keeping: manifest)
        #expect(!FileManager.default.fileExists(atPath: store.destinationURL(for: v1).path))
        #expect(store.localURL(for: v2) == store.destinationURL(for: v2))
        #expect(ContentStore.fileId(fromLocalName: v2.localFileName) == "abc_1")
    }

    @Test func manifestRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentStore(rootURL: root)
        let manifest = ManifestBuilder.build(from: Fixtures.snapshot)
        try store.save(manifest)
        let loaded = store.loadManifest()
        #expect(loaded?.exercises == manifest.exercises)
        #expect(loaded?.contentVersion == manifest.contentVersion)
    }
}
