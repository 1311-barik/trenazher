import Combine
import Foundation

/// Управляет идущей тренировкой: старт, переходы, сохранение прогресса, завершение.
@MainActor
public final class SessionController: ObservableObject {
    @Published public private(set) var session: WorkoutSession? {
        didSet { persist() }
    }

    /// Показан ли экран тренировки. Можно свернуть тренировку и вернуться к ней с главного экрана.
    @Published public var isPresented = false
    /// Итог только что завершённой тренировки — для экрана завершения.
    @Published public private(set) var finishedEntry: HistoryEntry?

    private let fileURL: URL
    private let userData: UserDataStore
    private let content: ContentRepository

    public init(fileURL: URL = SessionController.defaultFileURL(), userData: UserDataStore, content: ContentRepository) {
        self.fileURL = fileURL
        self.userData = userData
        self.content = content
        session = Self.load(from: fileURL)
    }

    public nonisolated static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Session", isDirectory: true)
            .appendingPathComponent("current.json")
    }

    public var hasUnfinishedSession: Bool { session != nil }

    // MARK: - Старт

    public func start(workout: Workout) {
        let ids = workout.exerciseIds.filter { content.exercise(id: $0) != nil }
        guard !ids.isEmpty else { return }
        begin(WorkoutSession(kind: .ready, workoutId: workout.id, title: workout.title,
                             bodyParts: content.bodyParts(forExerciseIds: ids), exerciseIds: ids))
    }

    public func startCustom(exerciseIds: [String], bodyParts: [String]) {
        guard !exerciseIds.isEmpty else { return }
        let title = bodyParts.isEmpty ? "Своя тренировка" : bodyParts.joined(separator: " + ")
        begin(WorkoutSession(kind: .custom, title: title, bodyParts: bodyParts, exerciseIds: exerciseIds))
    }

    /// Одно упражнение из избранного — тоже маленькая тренировка.
    public func startSingle(_ exercise: Exercise) {
        begin(WorkoutSession(kind: .custom, title: exercise.name, bodyParts: [exercise.bodyPart], exerciseIds: [exercise.id]))
    }

    private func begin(_ newSession: WorkoutSession) {
        finishedEntry = nil
        session = newSession
        isPresented = true
    }

    public func resume() {
        guard session != nil else { return }
        finishedEntry = nil
        isPresented = true
    }

    // MARK: - Переходы

    public func update(_ change: (inout WorkoutSession) -> Void) {
        guard var current = session else { return }
        change(&current)
        session = current
    }

    public var currentExercise: Exercise? {
        session?.currentExerciseId.flatMap(content.exercise(id:))
    }

    // MARK: - Завершение

    /// «Нет, закончить» или «Завершить и сохранить»: запись уходит в историю.
    @discardableResult
    public func finish(now: Date = Date()) -> HistoryEntry? {
        guard let current = session else { return nil }
        let entry = current.historyEntry(names: { self.content.exercise(id: $0)?.name }, now: now)
        if let entry = entry {
            userData.addHistory(entry)
        }
        finishedEntry = entry
        session = nil
        if entry == nil { isPresented = false }
        return entry
    }

    /// Прервать без сохранения (с подтверждением в интерфейсе).
    public func discard() {
        session = nil
        finishedEntry = nil
        isPresented = false
    }

    /// Закрыть экран завершения.
    public func closeFinished() {
        finishedEntry = nil
        isPresented = false
    }

    // MARK: - Хранение

    private func persist() {
        do {
            if let session = session {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(session).write(to: fileURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            // Не критично: тренировка продолжается в памяти, потеряется только восстановление после закрытия.
        }
    }

    private static func load(from url: URL) -> WorkoutSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkoutSession.self, from: data)
    }
}

/// Черновик своей тренировки: выбранные части тела и упражнения.
/// Переживает выход с экрана и перезапуск — выбор не теряется (мастер можно покинуть без потери черновика).
@MainActor
public final class CustomWorkoutDraft: ObservableObject {
    @Published public var bodyParts: [String] { didSet { persist() } }
    @Published public var exerciseIds: [String] { didSet { persist() } }

    private let defaults: UserDefaults
    private static let key = "draft.custom.v1"

    private struct Stored: Codable {
        var bodyParts: [String]
        var exerciseIds: [String]
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        bodyParts = stored?.bodyParts ?? []
        exerciseIds = stored?.exerciseIds ?? []
    }

    public func toggleBodyPart(_ part: String, order: [String]) {
        if let index = bodyParts.firstIndex(of: part) {
            bodyParts.remove(at: index)
        } else {
            bodyParts.append(part)
            bodyParts.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        }
    }

    public func toggleExercise(_ id: String) {
        if let index = exerciseIds.firstIndex(of: id) {
            exerciseIds.remove(at: index)
        } else {
            exerciseIds.append(id)
        }
    }

    public func isSelected(_ id: String) -> Bool { exerciseIds.contains(id) }

    /// Упражнения в порядке показа: по разделам, внутри — как в таблице.
    public func orderedSelection(in content: ContentRepository) -> [String] {
        let selected = Set(exerciseIds)
        return bodyParts.flatMap { content.exercises(in: $0) }.map(\.id).filter(selected.contains)
    }

    /// Убирает то, чего уже нет в контенте или в выбранных разделах.
    public func prune(using content: ContentRepository) {
        let parts = bodyParts.filter(content.bodyParts.contains)
        if parts != bodyParts { bodyParts = parts }
        let valid = Set(parts.flatMap { content.exercises(in: $0) }.map(\.id))
        let ids = exerciseIds.filter(valid.contains)
        if ids != exerciseIds { exerciseIds = ids }
    }

    public func reset() {
        bodyParts = []
        exerciseIds = []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Stored(bodyParts: bodyParts, exerciseIds: exerciseIds)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
