import Foundation

/// Текущий контент для экранов: упражнения, части тела, готовые тренировки.
@MainActor
public final class ContentRepository: ObservableObject {
    @Published public private(set) var manifest: ContentManifest

    private var exercisesById: [String: Exercise] = [:]
    private var exercisesByPart: [String: [Exercise]] = [:]
    private var workoutsById: [String: Workout] = [:]

    public init(manifest: ContentManifest = .empty) {
        self.manifest = manifest
        rebuildIndexes()
    }

    public func apply(_ manifest: ContentManifest) {
        self.manifest = manifest
        rebuildIndexes()
    }

    public var isEmpty: Bool { manifest.isEmpty }
    public var bodyParts: [String] { manifest.bodyParts }
    public var workouts: [Workout] { manifest.workouts }
    public var issues: [ContentIssue] { manifest.issues }

    public func exercise(id: String) -> Exercise? { exercisesById[id] }
    public func workout(id: String) -> Workout? { workoutsById[id] }
    public func exercises(in bodyPart: String) -> [Exercise] { exercisesByPart[bodyPart] ?? [] }

    public func exercises(ids: [String]) -> [Exercise] { ids.compactMap { exercisesById[$0] } }

    /// Первое фото раздела — для плитки выбора части тела.
    public func coverPhoto(for bodyPart: String) -> MediaItem? {
        exercises(in: bodyPart).lazy.compactMap(\.photos.first).first
    }

    /// Части тела, к которым относятся упражнения тренировки (в порядке таблицы).
    public func bodyParts(forExerciseIds ids: [String]) -> [String] {
        let parts = Set(ids.compactMap { exercisesById[$0]?.bodyPart })
        return manifest.bodyParts.filter(parts.contains)
    }

    private func rebuildIndexes() {
        var byId: [String: Exercise] = [:]
        var byPart: [String: [Exercise]] = [:]
        for exercise in manifest.exercises {
            byId[exercise.id] = exercise
            byPart[exercise.bodyPart, default: []].append(exercise)
        }
        exercisesById = byId
        exercisesByPart = byPart
        workoutsById = Dictionary(manifest.workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
