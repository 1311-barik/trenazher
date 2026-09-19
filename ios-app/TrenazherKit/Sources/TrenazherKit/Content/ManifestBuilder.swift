import Foundation

/// Сырые данные из Google: строки листов и содержимое трёх папок.
public struct ContentSnapshot: Equatable {
    public var exerciseRows: [[String]]
    public var workoutRows: [[String]]
    public var photos: [DriveFile]
    public var ownVideos: [DriveFile]
    public var otherVideos: [DriveFile]
    /// Замечания, появившиеся при загрузке (например, не найдена папка).
    public var issues: [ContentIssue]

    public init(exerciseRows: [[String]], workoutRows: [[String]] = [], photos: [DriveFile] = [], ownVideos: [DriveFile] = [],
                otherVideos: [DriveFile] = [], issues: [ContentIssue] = []) {
        self.exerciseRows = exerciseRows
        self.workoutRows = workoutRows
        self.photos = photos
        self.ownVideos = ownVideos
        self.otherVideos = otherVideos
        self.issues = issues
    }
}

/// Собирает манифест из таблицы и папок. Чистая функция — легко тестируется
/// и одинаково работает в приложении и в утилите content-report.
public enum ManifestBuilder {
    public static func build(from snapshot: ContentSnapshot, now: Date = Date()) -> ContentManifest {
        var issues = snapshot.issues
        let parsed = ExerciseSheetParser.parse(snapshot.exerciseRows)
        issues += parsed.issues

        let folders: [(kind: MediaKind, column: String, matcher: MediaMatcher)] = [
            (.photo, "Фото", MediaMatcher(files: snapshot.photos)),
            (.ownVideo, "Женя видео", MediaMatcher(files: snapshot.ownVideos)),
            (.otherVideo, "Чужое видео", MediaMatcher(files: snapshot.otherVideos)),
        ]
        var usedFileIds = Set<String>()
        var exercises: [Exercise] = []
        var bodyParts: [String] = []
        var takenIds = Set<String>()

        for row in parsed.rows {
            if !bodyParts.contains(row.bodyPart) { bodyParts.append(row.bodyPart) }

            var media: [MediaKind: [MediaItem]] = [:]
            for folder in folders {
                let cell: String
                switch folder.kind {
                case .photo: cell = row.photoCell
                case .ownVideo: cell = row.ownVideoCell
                case .otherVideo: cell = row.otherVideoCell
                }
                let files = resolve(cell: cell, column: folder.column, row: row, matcher: folder.matcher, issues: &issues)
                usedFileIds.formUnion(files.map(\.id))
                media[folder.kind] = files.map { $0.mediaItem(kind: folder.kind) }
            }

            // ID стабилен, пока не меняются название и часть тела — на него ссылаются избранное и история.
            var id = "\(TextNormalizer.key(row.bodyPart))/\(TextNormalizer.key(row.name))"
            if takenIds.contains(id) {
                issues.append(ContentIssue(.warning, "Строка \(row.rowNumber): упражнение «\(row.name)» в разделе «\(row.bodyPart)» встречается повторно."))
                id += "#\(row.rowNumber)"
            }
            takenIds.insert(id)

            let photos = media[.photo] ?? []
            // Сначала видео Жени, потом чужие — как в описании карточки.
            let videos = (media[.ownVideo] ?? []) + (media[.otherVideo] ?? [])
            let version = StableHash.hex([row.name, row.bodyPart, row.muscleGroup ?? "", row.equipment ?? "", row.details,
                                          row.sets.map(String.init) ?? ""] + (photos + videos).map { "\($0.driveFileId):\($0.version)" })
            exercises.append(Exercise(id: id, name: row.name, bodyPart: row.bodyPart, muscleGroup: row.muscleGroup,
                                      equipment: row.equipment, details: row.details, sets: row.sets,
                                      photos: photos, videos: videos, version: version))
        }

        let workouts = buildWorkouts(from: snapshot.workoutRows, exercises: exercises, issues: &issues)

        // Файлы, которые лежат в папках, но ни к чему не привязаны, — подсказка для Жени.
        for folder in folders {
            for file in folder.matcher.files where !usedFileIds.contains(file.id) {
                issues.append(ContentIssue(.info, "Файл «\(file.baseName)» в папке «\(folderTitle(folder.kind))» не привязан ни к одному упражнению."))
            }
        }

        let contentVersion = StableHash.hex(exercises.map(\.version) + workouts.map(\.version) + bodyParts)
        let sortedIssues = issues.enumerated().sorted { lhs, rhs in
            lhs.element.severity == rhs.element.severity ? lhs.offset < rhs.offset : lhs.element.severity < rhs.element.severity
        }.map(\.element)
        return ContentManifest(generatedAt: now, bodyParts: bodyParts, exercises: exercises, workouts: workouts,
                               issues: sortedIssues, contentVersion: contentVersion)
    }

    static func folderTitle(_ kind: MediaKind) -> String {
        switch kind {
        case .photo: return "Фото упражнений"
        case .ownVideo: return "Женя видео"
        case .otherVideo: return "Чужие видео"
        }
    }

    private static func resolve(cell: String, column: String, row: ExerciseRow, matcher: MediaMatcher, issues: inout [ContentIssue]) -> [DriveFile] {
        let place = "Строка \(row.rowNumber), «\(row.name)», колонка «\(column)»"
        switch MediaCellParser.parse(cell) {
        case .none:
            return []
        case .auto(let expected):
            let found = matcher.autoMatches(forExerciseNamed: row.name)
            if found.isEmpty && expected {
                let hint = matcher.suggestions(forExerciseNamed: row.name).map { "«\($0.baseName)»" }.joined(separator: " или ")
                let suggestion = hint.isEmpty ? "" : " Возможно, подходит: \(hint)."
                issues.append(ContentIssue(.warning, "\(place): написано «есть», но файл с таким названием не найден.\(suggestion) Впишите в ячейку имя файла или ссылку на него."))
            }
            return found
        case .explicit(let references):
            var files: [DriveFile] = []
            for reference in references {
                switch matcher.resolve(reference) {
                case .found(let file):
                    if !files.contains(file) { files.append(file) }
                case .notFound:
                    issues.append(ContentIssue(.warning, "\(place): файл «\(describe(reference))» не найден в папке «\(folderTitle(for: column))»."))
                case .ambiguous(let candidates):
                    let names = candidates.prefix(3).map { "«\($0.baseName)»" }.joined(separator: ", ")
                    issues.append(ContentIssue(.warning, "\(place): под «\(describe(reference))» подходит несколько файлов (\(names)) — уточните имя."))
                }
            }
            return files
        }
    }

    private static func folderTitle(for column: String) -> String {
        switch column {
        case "Фото": return folderTitle(.photo)
        case "Женя видео": return folderTitle(.ownVideo)
        default: return folderTitle(.otherVideo)
        }
    }

    private static func describe(_ reference: MediaReference) -> String {
        switch reference {
        case .fileId(let id): return "ссылка …\(id.suffix(6))"
        case .fileName(let name): return name
        }
    }

    private static func buildWorkouts(from rows: [[String]], exercises: [Exercise], issues: inout [ContentIssue]) -> [Workout] {
        guard !rows.isEmpty else { return [] }
        let parsed = WorkoutSheetParser.parse(rows)
        issues += parsed.issues

        var byName: [String: [Exercise]] = [:]
        for exercise in exercises {
            byName[TextNormalizer.key(exercise.name), default: []].append(exercise)
        }

        var workouts: [Workout] = []
        var takenIds = Set<String>()
        for row in parsed.workouts {
            var ids: [String] = []
            for entry in row.exercises {
                if let exercise = lookup(entry.name, in: byName, exercises: exercises) {
                    ids.append(exercise.id)
                } else {
                    issues.append(ContentIssue(.warning, "Лист «Тренировки», строка \(entry.rowNumber): упражнение «\(entry.name)» не найдено в таблице упражнений."))
                }
            }
            guard !ids.isEmpty else {
                issues.append(ContentIssue(.warning, "Тренировка «\(row.title)» пропущена: в ней нет ни одного найденного упражнения."))
                continue
            }
            // Новая версия («Спина v2») — отдельная тренировка со своим ID, старая не перезаписывается.
            var id = "workout/\(TextNormalizer.key(row.title))"
            if takenIds.contains(id) {
                issues.append(ContentIssue(.warning, "Тренировка «\(row.title)» встречается дважды — названия должны отличаться."))
                id += "#\(workouts.count)"
            }
            takenIds.insert(id)
            let version = StableHash.hex([row.title, row.summary ?? ""] + ids)
            workouts.append(Workout(id: id, title: row.title, summary: row.summary, exerciseIds: ids, version: version))
        }
        return workouts
    }

    /// Упражнение по названию; можно уточнить разделом: «Попа. Приседания».
    private static func lookup(_ name: String, in byName: [String: [Exercise]], exercises: [Exercise]) -> Exercise? {
        if let found = byName[TextNormalizer.key(name)]?.first { return found }
        let parts = name.components(separatedBy: ".").map(TextNormalizer.trimmed).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let part = TextNormalizer.key(parts[0])
        let exerciseName = TextNormalizer.key(parts.dropFirst().joined(separator: " "))
        return exercises.first { TextNormalizer.key($0.bodyPart) == part && TextNormalizer.key($0.name) == exerciseName }
    }
}
