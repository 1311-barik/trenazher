import Foundation

/// Строка листа упражнений после разбора (до сопоставления файлов).
public struct ExerciseRow: Equatable {
    /// Номер строки в таблице (с 1) — для понятных сообщений Жене.
    public var rowNumber: Int
    public var bodyPart: String
    public var muscleGroup: String?
    public var name: String
    public var equipment: String?
    public var details: String
    public var sets: Int?
    public var photoCell: String
    public var otherVideoCell: String
    public var ownVideoCell: String
}

/// Разбор листа «Дрон тренировка» в том виде, в каком его ведёт Женя:
/// часть тела и группа мышц пишутся только в первой строке раздела (ниже — пусто),
/// разделы разделены пустыми строками. Колонки ищутся по заголовкам, поэтому
/// порядок колонок можно менять и добавлять новые (например «Подходы»).
public enum ExerciseSheetParser {
    enum Column: CaseIterable {
        case bodyPart, muscleGroup, name, equipment, details, photos, otherVideos, ownVideos, sets
    }

    /// Раскладка колонок в таблице на 2026-09-18 — запасной вариант, если заголовки не найдены.
    static let fallbackLayout: [Column: Int] = [
        .bodyPart: 0, .muscleGroup: 1, .name: 2, .equipment: 3, .details: 4, .photos: 5, .otherVideos: 6, .ownVideos: 7,
    ]

    /// Определяет колонку по тексту заголовка. Порядок проверок важен: «Фото упражнений» — это фото, а не название.
    static func column(forHeader header: String) -> Column? {
        let key = TextNormalizer.key(header)
        guard !key.isEmpty else { return nil }
        if key.contains("фото") { return .photos }
        if key.contains("чуж") { return .otherVideos }
        if key.contains("жен") { return .ownVideos }
        if key.contains("описан") || key.contains("техник") { return .details }
        if key.contains("подход") { return .sets }
        if key.contains("тела") || key.contains("раздел") { return .bodyPart }
        if key.contains("мышц") { return .muscleGroup }
        if key.contains("гантел") || key.contains("инвентар") || key.contains("оборудован") { return .equipment }
        if key.contains("упражнен") || key == "название" { return .name }
        return nil
    }

    public static func parse(_ rows: [[String]]) -> (rows: [ExerciseRow], issues: [ContentIssue]) {
        var issues: [ContentIssue] = []

        // Ищем строку заголовков: первая строка, где есть колонка «Упражнение».
        var layout: [Column: Int] = [:]
        var headerIndex: Int?
        for (index, row) in rows.prefix(10).enumerated() {
            var candidate: [Column: Int] = [:]
            for (columnIndex, cell) in row.enumerated() {
                if let column = column(forHeader: cell), candidate[column] == nil {
                    candidate[column] = columnIndex
                }
            }
            if candidate[.name] != nil {
                layout = candidate
                headerIndex = index
                break
            }
        }
        if headerIndex == nil {
            layout = fallbackLayout
            issues.append(ContentIssue(.warning, "В таблице упражнений не найдена строка заголовков с колонкой «Упражнение» — использую порядок колонок по умолчанию (A–H)."))
        }
        guard let nameColumn = layout[.name] else { return ([], issues) }

        var result: [ExerciseRow] = []
        var currentBodyPart: String?
        var currentGroup: String?
        let firstDataRow = (headerIndex ?? -1) + 1

        for index in firstDataRow..<max(firstDataRow, rows.count) {
            let row = rows[index]
            func cell(_ column: Column) -> String {
                guard let columnIndex = layout[column], columnIndex < row.count else { return "" }
                return row[columnIndex]
            }

            let bodyPart = TextNormalizer.trimmed(cell(.bodyPart))
            let group = TextNormalizer.trimmed(cell(.muscleGroup))
            if !bodyPart.isEmpty {
                // Новый раздел: группа мышц берётся только из этой же строки.
                currentBodyPart = bodyPart
                currentGroup = group.isEmpty ? nil : group
            } else if !group.isEmpty {
                currentGroup = group
            }

            guard nameColumn < row.count else { continue }
            let name = TextNormalizer.displayName(row[nameColumn])
            guard !name.isEmpty else { continue }
            let rowNumber = index + 1

            guard let part = currentBodyPart else {
                issues.append(ContentIssue(.warning, "Строка \(rowNumber): у упражнения «\(name)» не указана часть тела — упражнение пропущено."))
                continue
            }

            var sets: Int?
            if let rawSets = TextNormalizer.nonEmpty(cell(.sets)) {
                sets = leadingInteger(rawSets)
                if sets == nil || sets == 0 {
                    sets = nil
                    issues.append(ContentIssue(.warning, "Строка \(rowNumber), «\(name)»: не понял число подходов «\(rawSets)» — таймер будет без счётчика."))
                }
            }

            result.append(ExerciseRow(
                rowNumber: rowNumber,
                bodyPart: part,
                muscleGroup: currentGroup,
                name: name,
                equipment: TextNormalizer.nonEmpty(cell(.equipment)),
                details: TextNormalizer.paragraphText(cell(.details)),
                sets: sets,
                photoCell: cell(.photos),
                otherVideoCell: cell(.otherVideos),
                ownVideoCell: cell(.ownVideos)
            ))
        }

        if result.isEmpty {
            issues.append(ContentIssue(.error, "В таблице не найдено ни одного упражнения."))
        }
        return (result, issues)
    }

    static func leadingInteger(_ text: String) -> Int? {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Готовая тренировка в листе «Тренировки» (формат предложен Жене, см. docs):
/// колонки «Тренировка», «Описание», «Упражнение»; название и описание — только
/// в первой строке тренировки, ниже — по одному упражнению в строке.
public struct WorkoutRow: Equatable {
    public var title: String
    public var summary: String?
    public var exercises: [(rowNumber: Int, name: String)]

    public static func == (lhs: WorkoutRow, rhs: WorkoutRow) -> Bool {
        lhs.title == rhs.title && lhs.summary == rhs.summary
            && lhs.exercises.map(\.name) == rhs.exercises.map(\.name)
    }
}

public enum WorkoutSheetParser {
    public static func parse(_ rows: [[String]]) -> (workouts: [WorkoutRow], issues: [ContentIssue]) {
        var titleColumn: Int?
        var summaryColumn: Int?
        var exerciseColumn: Int?
        var headerIndex: Int?

        for (index, row) in rows.prefix(10).enumerated() {
            for (columnIndex, cell) in row.enumerated() {
                let key = TextNormalizer.key(cell)
                if key.contains("упражнен"), exerciseColumn == nil { exerciseColumn = columnIndex }
                else if key.contains("описан"), summaryColumn == nil { summaryColumn = columnIndex }
                else if key.contains("трениров") || key == "название", titleColumn == nil { titleColumn = columnIndex }
            }
            if titleColumn != nil, exerciseColumn != nil {
                headerIndex = index
                break
            }
            titleColumn = nil
            summaryColumn = nil
            exerciseColumn = nil
        }

        guard let header = headerIndex, let titleIndex = titleColumn, let exerciseIndex = exerciseColumn else {
            if rows.contains(where: { $0.contains { !TextNormalizer.trimmed($0).isEmpty } }) {
                return ([], [ContentIssue(.warning, "Лист «Тренировки»: не найдены заголовки «Тренировка» и «Упражнение» — готовые тренировки не загружены.")])
            }
            return ([], [])
        }

        var workouts: [WorkoutRow] = []
        for index in (header + 1)..<max(header + 1, rows.count) {
            let row = rows[index]
            func cell(_ column: Int?) -> String {
                guard let column = column, column < row.count else { return "" }
                return TextNormalizer.trimmed(row[column])
            }
            let title = TextNormalizer.displayName(cell(titleIndex))
            if !title.isEmpty {
                workouts.append(WorkoutRow(title: title, summary: TextNormalizer.nonEmpty(cell(summaryColumn)), exercises: []))
            } else if let summary = TextNormalizer.nonEmpty(cell(summaryColumn)), !workouts.isEmpty, workouts[workouts.count - 1].summary == nil {
                workouts[workouts.count - 1].summary = summary
            }
            let exercise = TextNormalizer.displayName(cell(exerciseIndex))
            if !exercise.isEmpty, !workouts.isEmpty {
                workouts[workouts.count - 1].exercises.append((index + 1, exercise))
            }
        }
        return (workouts, [])
    }
}
