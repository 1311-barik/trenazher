import SwiftUI

// MARK: - Избранное

struct FavoritesView: View {
    enum Tab: Hashable { case exercises, workouts }

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var content: ContentRepository
    @State private var tab: Tab = .exercises

    var body: some View {
        let items = userData.favorites.filter { $0.type == (tab == .exercises ? .exercise : .workout) }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Раздел", selection: $tab) {
                    Text("Упражнения").tag(Tab.exercises)
                    Text("Тренировки").tag(Tab.workouts)
                }
                .pickerStyle(SegmentedPickerStyle())

                if items.isEmpty {
                    EmptyStateView(
                        icon: "heart",
                        title: tab == .exercises ? "Нет избранных упражнений" : "Нет избранных тренировок",
                        message: "Нажмите ♡ на карточке упражнения или тренировки — она появится здесь\(userData.isCloudSyncEnabled ? " и на iPad" : "")."
                    )
                }
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(Theme.padding)
        }
        .screen()
        .navigationTitle("Избранное")
        .inlineNavigationTitle()
    }

    @ViewBuilder
    private func row(_ item: FavoriteItem) -> some View {
        switch item.type {
        case .exercise:
            if let exercise = content.exercise(id: item.itemId) {
                HStack(spacing: 0) {
                    NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                        ExerciseListRow(exercise: exercise, trailing: AnyView(EmptyView()))
                    }
                    .buttonStyle(PlainButtonStyle())
                    FavoriteButton(itemId: item.itemId, type: .exercise, title: item.title)
                }
            } else {
                MissingFavoriteRow(item: item)
            }
        case .workout:
            if let workout = content.workout(id: item.itemId) {
                HStack(spacing: 0) {
                    NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title)
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                Text(RussianPlural.exercises(workout.exerciseIds.count))
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                        }
                        .padding(14)
                        .frame(minHeight: 64)
                        .card()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    FavoriteButton(itemId: item.itemId, type: .workout, title: item.title)
                }
            } else {
                MissingFavoriteRow(item: item)
            }
        }
    }
}

/// Отмеченное когда-то упражнение, которого больше нет в таблице: не прячем молча.
private struct MissingFavoriteRow: View {
    @EnvironmentObject private var app: AppModel
    let item: FavoriteItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(Theme.textSecondary)
                Text("Сейчас нет в таблице — возможно, переименовано или убрано")
                    .font(.caption)
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Button("Убрать") { app.toggleFavorite(itemId: item.itemId, type: item.type, title: item.title) }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.blue)
                .frame(minWidth: Theme.tapSize, minHeight: Theme.tapSize)
                .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .card()
    }
}

// MARK: - История

struct HistoryView: View {
    @EnvironmentObject private var userData: UserDataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if userData.history.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "Здесь появятся тренировки",
                                   message: userData.isCloudSyncEnabled
                                       ? "Каждая завершённая тренировка сохраняется автоматически — на iPhone и на iPad."
                                       : "Каждая завершённая тренировка сохраняется здесь автоматически.")
                } else {
                    summary
                    ForEach(groupedByMonth, id: \.title) { group in
                        SectionTitle(title: group.title.capitalized, trailing: "\(group.entries.count)")
                            .padding(.top, 8)
                        ForEach(group.entries) { entry in
                            NavigationLink(destination: HistoryDetailView(entry: entry)) {
                                HistoryRow(entry: entry)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(Theme.padding)
        }
        .screen()
        .navigationTitle("История")
        .inlineNavigationTitle()
    }

    /// Спокойная сводка: факты, без «серий» и штрафов за перерывы.
    private var summary: some View {
        let monthAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let recent = userData.history.filter { $0.finishedAt >= monthAgo }.count
        return HStack(spacing: 12) {
            statTile("\(userData.history.count)", "всего")
            statTile("\(recent)", "за 30 дней")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundColor(Theme.textPrimary)
            Text(label).font(.caption).foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var groupedByMonth: [(title: String, entries: [HistoryEntry])] {
        var result: [(title: String, entries: [HistoryEntry])] = []
        for entry in userData.history {
            let title = Formatters.month.string(from: entry.finishedAt)
            if let last = result.indices.last, result[last].title == title {
                result[last].entries.append(entry)
            } else {
                result.append((title, [entry]))
            }
        }
        return result
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatters.dayTime.string(from: entry.finishedAt))
                    .font(.caption)
                    .foregroundColor(Theme.textTertiary)
                Text(entry.title)
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Text("\(entry.kind.title) · \(RussianPlural.exercises(entry.exerciseCount)) · \(Formatters.duration(entry.duration))")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct HistoryDetailView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.presentationMode) private var presentationMode
    let entry: HistoryEntry
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(entry.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("\(Formatters.dayTime.string(from: entry.startedAt)) · \(Formatters.duration(entry.duration))")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                    HStack(spacing: 6) {
                        Chip(text: entry.kind.title == "Готовая" ? "Готовая тренировка" : "Своя тренировка")
                        ForEach(entry.bodyParts, id: \.self) { Chip(text: $0) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(entry.exerciseNames.enumerated()), id: \.offset) { index, name in
                            Text("\(index + 1). \(name)")
                                .font(.body)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.padding)
                    .card()
                    Button("Удалить из истории") { confirmDelete = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.accent)
                        .frame(minHeight: Theme.tapSize)
                        .buttonStyle(PlainButtonStyle())
                }
                .padding(Theme.padding)
            }
            BottomBar {
                Button("Повторить эту тренировку") { app.repeatWorkout(from: entry) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .screen()
        .navigationTitle("Тренировка")
        .inlineNavigationTitle()
        .alert(isPresented: $confirmDelete) {
            Alert(title: Text("Удалить запись?"),
                  message: Text("Запись исчезнет из истории\(app.userData.isCloudSyncEnabled ? " на всех устройствах" : ""). Сразу после удаления её можно вернуть кнопкой «Отменить»."),
                  primaryButton: .destructive(Text("Удалить")) {
                      presentationMode.wrappedValue.dismiss()
                      app.deleteHistory(entry)
                  },
                  secondaryButton: .cancel(Text("Оставить")))
        }
    }
}
