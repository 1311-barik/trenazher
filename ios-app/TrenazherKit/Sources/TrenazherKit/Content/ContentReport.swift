import Foundation

/// Отчёт о контенте в Markdown: что приложение поняло из таблицы и папок и что нужно поправить.
/// Используется утилитой content-report и может быть отправлен Жене как есть.
public enum ContentReportFormatter {
    public static func markdown(for manifest: ContentManifest) -> String {
        var lines: [String] = []
        lines.append("# Отчёт по контенту тренажёра")
        lines.append("")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy, HH:mm"
        lines.append("Собрано: \(formatter.string(from: manifest.generatedAt))")
        lines.append("")

        let partsSummary = manifest.bodyParts.map { part in
            "\(part) — \(manifest.exercises.filter { $0.bodyPart == part }.count)"
        }.joined(separator: ", ")
        lines.append("- Упражнений: **\(manifest.exercises.count)** в \(manifest.bodyParts.count) разделах: \(partsSummary).")
        lines.append("- Готовых тренировок: **\(manifest.workouts.count)**.")
        let withPhoto = manifest.exercises.filter { !$0.photos.isEmpty }.count
        let withOwn = manifest.exercises.filter { $0.videos.contains { $0.kind == .ownVideo } }.count
        let withOther = manifest.exercises.filter { $0.videos.contains { $0.kind == .otherVideo } }.count
        lines.append("- С фото: \(withPhoto), с видео Жени: \(withOwn), с чужими видео: \(withOther).")
        lines.append("")

        lines.append("## Упражнения и привязанные файлы")
        lines.append("")
        lines.append("| Раздел | Упражнение | Фото | Видео Жени | Чужие видео |")
        lines.append("|---|---|---|---|---|")
        for exercise in manifest.exercises {
            func cell(_ items: [MediaItem]) -> String {
                items.isEmpty ? "—" : items.map(\.title).joined(separator: "<br>")
            }
            lines.append("| \(exercise.bodyPart) | \(exercise.name) | \(cell(exercise.photos)) | "
                + "\(cell(exercise.videos.filter { $0.kind == .ownVideo })) | \(cell(exercise.videos.filter { $0.kind == .otherVideo })) |")
        }
        lines.append("")

        if !manifest.workouts.isEmpty {
            lines.append("## Готовые тренировки")
            lines.append("")
            for workout in manifest.workouts {
                let names = workout.exerciseIds.compactMap { id in manifest.exercises.first { $0.id == id }?.name }
                lines.append("- **\(workout.title)** (\(RussianPlural.exercises(names.count))): \(names.joined(separator: ", "))")
            }
            lines.append("")
        }

        let groups: [(ContentIssue.Severity, String)] = [
            (.error, "Ошибки — без исправления контент не загрузится"),
            (.warning, "Нужно поправить в таблице"),
            (.info, "Для сведения"),
        ]
        lines.append("## Замечания (\(manifest.issues.count))")
        lines.append("")
        if manifest.issues.isEmpty {
            lines.append("Замечаний нет.")
        }
        for (severity, title) in groups {
            let issues = manifest.issues.filter { $0.severity == severity }
            guard !issues.isEmpty else { continue }
            lines.append("### \(title) (\(issues.count))")
            lines.append("")
            lines += issues.map { "- \($0.message)" }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
