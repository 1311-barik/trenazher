import SwiftUI

// MARK: - Готовые тренировки

/// Список готовых тренировок (3–4 программы Жени).
struct ReadyWorkoutsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var content: ContentRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if content.workouts.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: "Готовых тренировок пока нет",
                        message: "Женя добавит их в таблицу на лист «Тренировки» — они появятся здесь после обновления. А пока можно собрать свою.",
                        actionTitle: "Собрать свою тренировку"
                    ) { app.router.open(.custom) }
                }
                ForEach(content.workouts) { workout in
                    WorkoutCard(workout: workout)
                }
            }
            .padding(Theme.padding)
        }
        .screen()
        .navigationTitle("Готовые тренировки")
        .inlineNavigationTitle()
    }
}

private struct WorkoutCard: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var content: ContentRepository
    let workout: Workout

    var body: some View {
        let exercises = content.exercises(ids: workout.exerciseIds)
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                HStack(alignment: .top, spacing: 12) {
                    MediaImage(media: exercises.lazy.compactMap(\.photos.first).first, maxPixel: 300)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.title)
                            .font(.title3.weight(.bold))
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        if let summary = workout.summary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Text("\(RussianPlural.exercises(exercises.count)) · \(WorkoutEstimate.text(forExerciseCount: exercises.count))")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityHint(Text("Посмотреть упражнения"))

            HStack(spacing: 10) {
                Button("Начать") { app.startWorkout(workout) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(exercises.isEmpty)
                FavoriteButton(itemId: workout.id, type: .workout, title: workout.title)
            }
        }
        .padding(Theme.padding)
        .card()
    }
}

/// Состав готовой тренировки.
struct WorkoutDetailView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var content: ContentRepository
    let workout: Workout
    @State private var detail: Exercise?

    var body: some View {
        let exercises = content.exercises(ids: workout.exerciseIds)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(workout.title)
                                .font(.title2.weight(.bold))
                                .foregroundColor(Theme.textPrimary)
                            if let summary = workout.summary {
                                Text(summary).font(.subheadline).foregroundColor(Theme.textSecondary)
                            }
                            Text("\(RussianPlural.exercises(exercises.count)) · \(WorkoutEstimate.text(forExerciseCount: exercises.count))")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Spacer()
                        FavoriteButton(itemId: workout.id, type: .workout, title: workout.title)
                    }
                    if exercises.count < workout.exerciseIds.count {
                        Label("Часть упражнений убрана из таблицы — они пропущены.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundColor(Theme.warning)
                    }
                    ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                        Button { detail = exercise } label: {
                            ExerciseListRow(exercise: exercise, number: index + 1, trailing: AnyView(
                                Image(systemName: "info.circle").foregroundColor(Theme.textTertiary).frame(width: Theme.tapSize, height: Theme.tapSize)
                            ))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityHint(Text("Открыть описание"))
                    }
                }
                .padding(Theme.padding)
            }
            BottomBar {
                Button("Начать тренировку") { app.startWorkout(workout) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(exercises.isEmpty)
            }
        }
        .screen()
        .navigationTitle(workout.title)
        .inlineNavigationTitle()
        .sheet(item: $detail) { exercise in
            ExerciseDetailView(exercise: exercise, isModal: true, allowsStart: false).appEnvironment(app)
        }
    }
}

// MARK: - Своя тренировка: шаг 1

/// Выбор частей тела. Рекомендация 2–3 — подсказка, а не ограничение.
struct BodyPartPickerView: View {
    @EnvironmentObject private var content: ContentRepository
    @EnvironmentObject private var draft: CustomWorkoutDraft
    @State private var showExercises = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Рекомендуем выбрать 2–3 части тела — иначе упражнений будет слишком много. Можно выбрать и больше.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(content.bodyParts, id: \.self) { part in
                            BodyPartTile(part: part, count: content.exercises(in: part).count,
                                         cover: content.coverPhoto(for: part),
                                         isSelected: draft.bodyParts.contains(part)) {
                                draft.toggleBodyPart(part, order: content.bodyParts)
                            }
                        }
                    }
                }
                .padding(Theme.padding)
            }
            BottomBar {
                Button(draft.bodyParts.isEmpty ? "Выберите часть тела" : "Далее: упражнения (\(draft.bodyParts.count))") {
                    showExercises = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(draft.bodyParts.isEmpty)
                if !draft.bodyParts.isEmpty || !draft.exerciseIds.isEmpty {
                    Button("Сбросить выбор") { draft.reset() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(minHeight: Theme.tapSize)
                        .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .screen()
        .navigationTitle("Части тела")
        .inlineNavigationTitle()
        .background(
            NavigationLink(destination: ExercisePickerView(mode: .draft), isActive: $showExercises) { EmptyView() }.hidden()
        )
    }
}

private struct BodyPartTile: View {
    let part: String
    let count: Int
    let cover: MediaItem?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    MediaImage(media: cover, maxPixel: 500)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26))
                        .foregroundColor(isSelected ? Theme.blue : .white)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                        .padding(8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(part)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(RussianPlural.exercises(count))
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .card(highlighted: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(part), \(RussianPlural.exercises(count))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Своя тренировка: шаг 2 и добор

/// Список упражнений, сгруппированный по частям тела, с отметками.
/// Режим `.draft` — сборка своей тренировки; `.addMore` — добор после вопроса «Ещё хочешь?».
struct ExercisePickerView: View {
    enum Mode {
        case draft
        case addMore
    }

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var content: ContentRepository
    @EnvironmentObject private var draft: CustomWorkoutDraft
    @EnvironmentObject private var sessions: SessionController
    let mode: Mode

    /// Выбор при доборе — отдельный, черновик своей тренировки не трогаем.
    @State private var extraSelection: [String] = []
    @State private var detail: Exercise?

    var body: some View {
        VStack(spacing: 0) {
            if mode == .addMore {
                addMoreHeader
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(parts, id: \.self) { part in
                        Section(header: sectionHeader(part)) {
                            ForEach(content.exercises(in: part)) { exercise in
                                row(exercise)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.padding)
                .padding(.bottom, 16)
            }
            bottomBar
        }
        .screen()
        .navigationTitle(mode == .draft ? "Упражнения" : "Добор")
        .inlineNavigationTitle()
        .sheet(item: $detail) { exercise in
            ExerciseDetailView(exercise: exercise, isModal: true, allowsStart: false).appEnvironment(app)
        }
    }

    // MARK: Данные

    /// В своей тренировке — выбранные части тела; при доборе — общий список, сначала части этой тренировки.
    private var parts: [String] {
        switch mode {
        case .draft:
            return draft.bodyParts
        case .addMore:
            let sessionParts = sessions.session?.bodyParts ?? []
            return content.bodyParts.filter(sessionParts.contains) + content.bodyParts.filter { !sessionParts.contains($0) }
        }
    }

    private var selection: [String] {
        mode == .draft ? draft.exerciseIds : extraSelection
    }

    private var doneToday: Set<String> {
        mode == .addMore ? (sessions.session?.doneExerciseIdSet ?? []) : []
    }

    private func toggle(_ id: String) {
        Haptics.tap()
        switch mode {
        case .draft:
            draft.toggleExercise(id)
        case .addMore:
            if let index = extraSelection.firstIndex(of: id) {
                extraSelection.remove(at: index)
            } else {
                extraSelection.append(id)
            }
        }
    }

    // MARK: Вид

    private var addMoreHeader: some View {
        HStack {
            Button {
                sessions.update { $0.cancelPicking() }
            } label: {
                Label("Назад", systemImage: "chevron.left")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                    .frame(minHeight: Theme.tapSize)
            }
            .buttonStyle(PlainButtonStyle())
            Spacer()
            Text("Добери упражнения")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, Theme.padding)
        .padding(.vertical, 6)
    }

    private func sectionHeader(_ part: String) -> some View {
        let exercises = content.exercises(in: part)
        let selected = exercises.filter { selection.contains($0.id) }.count
        return HStack {
            Text(part)
                .font(.title3.weight(.bold))
                .foregroundColor(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(selected > 0 ? "выбрано \(selected) из \(exercises.count)" : "\(exercises.count)")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.top, 6)
        .background(Theme.backgroundTop.opacity(0.96))
    }

    private func row(_ exercise: Exercise) -> some View {
        let isSelected = selection.contains(exercise.id)
        return HStack(spacing: 0) {
            Button { toggle(exercise.id) } label: {
                ExerciseListRow(exercise: exercise, badge: doneToday.contains(exercise.id) ? "Сделано сегодня" : nil,
                            trailing: AnyView(SelectionMark(isOn: isSelected)), highlighted: isSelected)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(Text(isSelected ? "Убрать из тренировки" : "Добавить в тренировку"))

            Button { detail = exercise } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(IconButtonStyle(tint: Theme.textSecondary, filled: false))
            .accessibilityLabel(Text("Описание: \(exercise.name)"))
        }
    }

    private var bottomBar: some View {
        let count = selection.count
        return BottomBar {
            if mode == .draft {
                HStack {
                    Text(count == 0 ? "Отметьте упражнения" : "Выбрано: \(count) · \(WorkoutEstimate.text(forExerciseCount: count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    // Рекомендация — нейтральным цветом: это подсказка, а не ошибка.
                    Text("рекомендуем 10–12")
                        .font(.footnote)
                        .foregroundColor(WorkoutEstimate.recommendedRange.contains(count) ? Theme.success : Theme.textTertiary)
                }
                Button(count == 0 ? "Начать тренировку" : "Начать тренировку (\(count))") { app.startCustomWorkout() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(count == 0)
            } else {
                Button(count == 0 ? "Выберите упражнения" : "Продолжить (\(count))") {
                    let parts = content.bodyParts(forExerciseIds: extraSelection)
                    let ordered = self.parts.flatMap { content.exercises(in: $0) }.map(\.id).filter(extraSelection.contains)
                    sessions.update { $0.append(ordered, bodyParts: parts) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(count == 0)
                Button("Нет, закончить тренировку") { sessions.finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(minHeight: Theme.tapSize)
                    .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

/// Строка упражнения: миниатюра, название, группа мышц и инвентарь.
struct ExerciseListRow: View {
    let exercise: Exercise
    var number: Int?
    var badge: String?
    var trailing: AnyView?
    var highlighted = false

    var body: some View {
        HStack(spacing: 12) {
            MediaImage(media: exercise.photos.first, maxPixel: 200)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(number.map { "\($0). \(exercise.name)" } ?? exercise.name)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
                if let badge = badge {
                    Label(badge, systemImage: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Theme.success)
                }
            }
            Spacer(minLength: 0)
            if let trailing = trailing {
                trailing
            }
        }
        .padding(10)
        .frame(minHeight: 76)
        .card(highlighted: highlighted)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let group = exercise.muscleGroup { parts.append(group) }
        if let equipment = exercise.equipment { parts.append("+ \(equipment)") }
        return parts.joined(separator: " · ")
    }
}
