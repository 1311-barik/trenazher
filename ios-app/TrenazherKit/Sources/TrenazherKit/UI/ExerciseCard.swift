import SwiftUI

/// Содержимое карточки упражнения в порядке из ТЗ: название → 1–2 фото → описание → видео.
struct ExerciseCardContent: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name)
                        .font(.title2.weight(.bold))
                        .foregroundColor(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    chips
                }
                Spacer(minLength: 0)
                FavoriteButton(itemId: exercise.id, type: .exercise, title: exercise.name)
            }

            PhotoCarousel(photos: exercise.photos)

            if !exercise.details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Техника")
                    Text(exercise.details)
                        .font(.body)
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VideoList(videos: exercise.videos)
        }
    }

    private var chips: some View {
        // Метки переносятся на новую строку на узком экране и при крупном шрифте.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Chip(text: exercise.bodyPart)
                if let group = exercise.muscleGroup, group != exercise.bodyPart {
                    Chip(text: group)
                }
            }
            HStack(spacing: 6) {
                if let equipment = exercise.equipment {
                    Chip(text: "Гантели + \(equipment)", icon: "plus")
                }
                if let sets = exercise.sets {
                    Chip(text: "Подходов: \(sets)", icon: "repeat")
                }
            }
        }
    }
}

/// Карточка упражнения вне тренировки (из избранного или «подробнее» в списке выбора).
struct ExerciseDetailView: View {
    @EnvironmentObject private var sessions: SessionController
    @EnvironmentObject private var router: HomeRouter
    @Environment(\.presentationMode) private var presentationMode
    let exercise: Exercise
    /// Показан поверх экрана (sheet) — нужна кнопка «Закрыть».
    var isModal = false
    var allowsStart = true

    var body: some View {
        VStack(spacing: 0) {
            if isModal {
                HStack {
                    Spacer()
                    Button { presentationMode.wrappedValue.dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel(Text("Закрыть"))
                }
                .padding(.horizontal, Theme.padding)
                .padding(.top, 8)
            }
            ScrollView {
                ExerciseCardContent(exercise: exercise)
                    .padding(Theme.padding)
                    .padding(.bottom, 24)
            }
            if allowsStart {
                BottomBar {
                    Button("Начать с этого упражнения") {
                        if isModal { presentationMode.wrappedValue.dismiss() }
                        sessions.startSingle(exercise)
                        router.popToRoot()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .screen()
        .navigationTitle(exercise.name)
        .inlineNavigationTitle()
    }
}
