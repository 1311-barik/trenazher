// Рендер экранов приложения в PNG на Mac — чтобы посмотреть вёрстку без Xcode и симулятора.
// Это macOS-отрисовка того же SwiftUI-кода: шрифты и системные контролы (переключатели,
// сегменты) выглядят по-маковски, но раскладка, тексты и цвета — те же, что на iPhone.
//
//   swift run screen-previews --csv sheet.csv --files files.json --out ./previews
#if os(macOS)
import AppKit
import SwiftUI
@testable import TrenazherKit

struct Arguments {
    var values: [String: String] = [:]
    init(_ raw: [String]) {
        var index = 0
        while index + 1 < raw.count {
            if raw[index].hasPrefix("--") { values[String(raw[index].dropFirst(2))] = raw[index + 1] }
            index += 2
        }
    }
    subscript(_ key: String) -> String? { values[key] }
}

struct Listing: Decodable {
    var photos: [DriveFile]
    var ownVideos: [DriveFile]
    var otherVideos: [DriveFile]
}

@MainActor
func render<V: View>(_ view: V, app: AppModel, name: String, size: CGSize, to folder: URL) {
    let root = view
        .appEnvironment(app)
        .frame(width: size.width, height: size.height)
        .background(ScreenBackground())
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let url = folder.appendingPathComponent("\(name).png")
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    print("✓ \(url.lastPathComponent)")
}

@MainActor
func runPreviews() {
    let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
    guard let csvPath = arguments["csv"], let filesPath = arguments["files"], let outPath = arguments["out"] else {
        print("Использование: screen-previews --csv sheet.csv --files files.json --out ./previews")
        exit(1)
    }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)

    let rows = CSVParser.parse(try! String(contentsOfFile: csvPath, encoding: .utf8))
    let listing = try! JSONDecoder().decode(Listing.self, from: Data(contentsOf: URL(fileURLWithPath: filesPath)))
    // Пример листа «Тренировки», чтобы показать экран готовых тренировок (в таблице Жени его пока нет).
    let workoutRows = [
        ["Тренировка", "Описание", "Упражнение"],
        ["Руки и пресс (пример)", "Пример формата листа «Тренировки»", "Молот"],
        ["", "", "Диагональный молот"], ["", "", "Мертвый жук"], ["", "", "Планка с перетаскиванием гантели"],
    ]
    let snapshot = ContentSnapshot(exerciseRows: rows, workoutRows: workoutRows, photos: listing.photos,
                                   ownVideos: listing.ownVideos, otherVideos: listing.otherVideos)

    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("trenazher-previews-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: "trenazher-previews-\(UUID().uuidString)")!
    let source = StaticContentSource(snapshot: snapshot)
    let app = AppModel(configuration: AppConfiguration(google: GoogleContentConfig(apiKey: "", spreadsheetId: "", rootFolderId: ""), cloudKitContainerId: nil),
                       source: source, network: NetworkMonitor(fixedConnected: true),
                       contentRoot: temp.appendingPathComponent("content"),
                       userData: UserDataStore(cloudKitContainerId: nil, inMemory: true),
                       settings: SettingsStore(defaults: defaults, cloud: InMemoryKeyValueStore()),
                       sessionFile: temp.appendingPathComponent("session.json"), defaults: defaults)
    app.content.apply(ManifestBuilder.build(from: snapshot))

    // Немного истории и избранного — чтобы экраны не были пустыми.
    let now = Date()
    app.userData.addHistory(HistoryEntry(startedAt: now.addingTimeInterval(-86400 - 3000), finishedAt: now.addingTimeInterval(-86400),
                                         kind: .custom, title: "Руки + Живот", bodyParts: ["Руки", "Живот"],
                                         exerciseIds: ["руки/молот", "руки/диагональный молот", "живот/мертвый жук"],
                                         exerciseNames: ["Молот", "Диагональный молот", "Мертвый жук"]))
    app.userData.addHistory(HistoryEntry(startedAt: now.addingTimeInterval(-4 * 86400 - 4200), finishedAt: now.addingTimeInterval(-4 * 86400),
                                         kind: .custom, title: "Попа + Ноги", bodyParts: ["Попа", "Ноги"],
                                         exerciseIds: ["попа/приседание сумо", "ноги/присед у стены"],
                                         exerciseNames: ["Приседание сумо", "Присед у стены"]))
    app.userData.addFavorite(FavoriteItem(itemId: "живот/мертвый жук", type: .exercise, title: "Мертвый жук"))
    app.userData.addFavorite(FavoriteItem(itemId: "руки/молот", type: .exercise, title: "Молот"))

    let out = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let phone = CGSize(width: 390, height: 844)

    render(HomeView(), app: app, name: "01-home", size: phone, to: out)
    render(ReadyWorkoutsView(), app: app, name: "02-ready-workouts", size: phone, to: out)
    app.draft.reset()
    app.draft.toggleBodyPart("Руки", order: app.content.bodyParts)
    app.draft.toggleBodyPart("Живот", order: app.content.bodyParts)
    render(BodyPartPickerView(), app: app, name: "03-body-parts", size: phone, to: out)
    for id in ["руки/молот", "руки/диагональный молот", "живот/мертвый жук"] { app.draft.toggleExercise(id) }
    render(ExercisePickerView(mode: .draft), app: app, name: "04-exercise-picker", size: phone, to: out)

    app.sessions.startCustom(exerciseIds: app.draft.orderedSelection(in: app.content), bodyParts: app.draft.bodyParts)
    app.sessions.update { $0.next() }
    app.sessions.update { $0.markSetDone(totalSets: nil) }
    render(WorkoutFlowView(), app: app, name: "05-workout-card", size: phone, to: out)
    app.restTimer.start(seconds: 60)
    app.restTimer.extend(by: -15)
    render(WorkoutFlowView(), app: app, name: "06-rest-timer", size: phone, to: out)
    app.restTimer.stop()
    app.sessions.update { $0.next() }
    app.sessions.update { $0.next() }
    render(WorkoutFlowView(), app: app, name: "07-more-question", size: phone, to: out)
    app.sessions.update { $0.wantMore() }
    render(ExercisePickerView(mode: .addMore), app: app, name: "08-add-more", size: phone, to: out)
    app.sessions.update { $0.cancelPicking() }
    app.sessions.finish()
    render(WorkoutFlowView(), app: app, name: "09-finished", size: phone, to: out)
    app.sessions.closeFinished()

    render(FavoritesView(), app: app, name: "10-favorites", size: phone, to: out)
    render(HistoryView(), app: app, name: "11-history", size: phone, to: out)
    render(SettingsView(), app: app, name: "12-settings", size: CGSize(width: 390, height: 1300), to: out)
    render(ContentIssuesView(), app: app, name: "13-content-issues", size: phone, to: out)
    render(HomeView(), app: app, name: "14-home-ipad", size: CGSize(width: 820, height: 1180), to: out)

    try? FileManager.default.removeItem(at: temp)
}

@main
enum ScreenPreviewsTool {
    @MainActor
    static func main() {
        runPreviews()
    }
}
#else
@main
enum ScreenPreviewsTool {
    static func main() {
        print("screen-previews работает только на macOS")
    }
}
#endif
