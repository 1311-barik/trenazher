import Foundation

/// Идущая тренировка. Чистая модель без UI — все переходы покрыты тестами.
/// Сохраняется на диск после каждого действия: если приложение закрыли,
/// тренировка продолжится с того же упражнения и тех же отмеченных подходов.
public struct WorkoutSession: Codable, Equatable, Identifiable {
    public enum Phase: String, Codable {
        /// Карточка упражнения.
        case exercising
        /// Список закончился — вопрос «Ещё хочешь?».
        case askingMore
        /// Добор упражнений из общего списка.
        case pickingMore
    }

    public var id: UUID
    public var kind: WorkoutKind
    public var workoutId: String?
    public var title: String
    public var bodyParts: [String]
    /// Упражнения в порядке выполнения (при доборе дописываются в конец; повторы допустимы).
    public private(set) var queue: [String]
    public private(set) var currentIndex: Int
    /// Отмеченные подходы — по позиции в очереди.
    public private(set) var setsDone: [Int]
    /// Пройденные упражнения — по позиции в очереди.
    public private(set) var completed: [Bool]
    public private(set) var phase: Phase
    public var startedAt: Date
    public private(set) var updatedAt: Date

    public init(kind: WorkoutKind, workoutId: String? = nil, title: String, bodyParts: [String], exerciseIds: [String], now: Date = Date()) {
        precondition(!exerciseIds.isEmpty, "Тренировка без упражнений")
        id = UUID()
        self.kind = kind
        self.workoutId = workoutId
        self.title = title
        self.bodyParts = bodyParts
        queue = exerciseIds
        currentIndex = 0
        setsDone = Array(repeating: 0, count: exerciseIds.count)
        completed = Array(repeating: false, count: exerciseIds.count)
        phase = .exercising
        startedAt = now
        updatedAt = now
    }

    public var currentExerciseId: String? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    public var isLastInQueue: Bool { currentIndex >= queue.count - 1 }
    public var canGoBack: Bool { currentIndex > 0 }
    public var position: (index: Int, total: Int) { (currentIndex + 1, queue.count) }
    public var currentSetsDone: Int { setsDone.indices.contains(currentIndex) ? setsDone[currentIndex] : 0 }

    /// Пройденные упражнения (для итога и истории).
    public var completedExerciseIds: [String] {
        queue.indices.filter { completed[$0] }.map { queue[$0] }
    }

    public var doneExerciseIdSet: Set<String> { Set(completedExerciseIds) }

    // MARK: - Действия и обратные действия

    /// «Подход выполнен». Если число подходов известно — не больше него.
    public mutating func markSetDone(totalSets: Int?, now: Date = Date()) {
        guard phase == .exercising, setsDone.indices.contains(currentIndex) else { return }
        if let total = totalSets, setsDone[currentIndex] >= total { return }
        setsDone[currentIndex] += 1
        touch(now)
    }

    /// Снять последнюю отметку подхода (ошибочное нажатие).
    public mutating func undoSet(now: Date = Date()) {
        guard phase == .exercising, setsDone.indices.contains(currentIndex), setsDone[currentIndex] > 0 else { return }
        setsDone[currentIndex] -= 1
        touch(now)
    }

    /// «Следующее упражнение». После последнего — вопрос «Ещё хочешь?».
    public mutating func next(now: Date = Date()) {
        guard phase == .exercising, completed.indices.contains(currentIndex) else { return }
        completed[currentIndex] = true
        if isLastInQueue {
            phase = .askingMore
        } else {
            currentIndex += 1
        }
        touch(now)
    }

    /// Вернуться к предыдущему упражнению (или из вопроса «Ещё хочешь?» — к последнему).
    public mutating func previous(now: Date = Date()) {
        switch phase {
        case .askingMore:
            phase = .exercising
        case .exercising where canGoBack:
            currentIndex -= 1
        default:
            return
        }
        touch(now)
    }

    /// «Да, хочу ещё» — открыть общий список для добора.
    public mutating func wantMore(now: Date = Date()) {
        guard phase == .askingMore else { return }
        phase = .pickingMore
        touch(now)
    }

    /// Передумал добирать — назад к вопросу.
    public mutating func cancelPicking(now: Date = Date()) {
        guard phase == .pickingMore else { return }
        phase = .askingMore
        touch(now)
    }

    /// Добавить выбранные упражнения и продолжить с первого из них.
    public mutating func append(_ exerciseIds: [String], bodyParts newParts: [String] = [], now: Date = Date()) {
        guard phase == .pickingMore else { return }
        guard !exerciseIds.isEmpty else {
            phase = .askingMore
            touch(now)
            return
        }
        let firstNew = queue.count
        queue += exerciseIds
        setsDone += Array(repeating: 0, count: exerciseIds.count)
        completed += Array(repeating: false, count: exerciseIds.count)
        for part in newParts where !bodyParts.contains(part) { bodyParts.append(part) }
        currentIndex = firstNew
        phase = .exercising
        touch(now)
    }

    /// Итог для истории. Если тренировку закончили посреди списка, текущее упражнение
    /// засчитывается, только когда по нему отмечен хотя бы один подход.
    public func historyEntry(names: (String) -> String?, now: Date = Date()) -> HistoryEntry? {
        var ids = completedExerciseIds
        if phase == .exercising, currentSetsDone > 0, let current = currentExerciseId, !completed[currentIndex] {
            ids.append(current)
        }
        guard !ids.isEmpty else { return nil }
        return HistoryEntry(startedAt: startedAt, finishedAt: now, kind: kind, title: title, bodyParts: bodyParts,
                            exerciseIds: ids, exerciseNames: ids.map { names($0) ?? "Упражнение" })
    }

    private mutating func touch(_ now: Date) {
        updatedAt = now
    }
}

/// Оценка длительности для подсказки при выборе: на упражнение 4–6 минут
/// (3–4 подхода с отдыхом). 10–12 упражнений ≈ 40–70 минут — в рамках «от 30 минут до 1,5 часа».
public enum WorkoutEstimate {
    public static let recommendedRange = 10...12

    public static func minutes(forExerciseCount count: Int) -> ClosedRange<Int> {
        (count * 4)...(count * 6)
    }

    public static func text(forExerciseCount count: Int) -> String {
        guard count > 0 else { return "" }
        let range = minutes(forExerciseCount: count)
        return "≈ \(range.lowerBound)–\(range.upperBound) мин"
    }
}
