import SwiftUI

/// Полноэкранная тренировка: карточки упражнений → «Ещё хочешь?» → добор или итог.
struct WorkoutFlowView: View {
    @EnvironmentObject private var sessions: SessionController

    var body: some View {
        ZStack {
            ScreenBackground()
            if let entry = sessions.finishedEntry {
                WorkoutFinishedView(entry: entry)
            } else if let session = sessions.session {
                switch session.phase {
                case .exercising:
                    ExerciseSessionView(session: session)
                case .askingMore:
                    MoreQuestionView(session: session)
                case .pickingMore:
                    NavigationView {
                        ExercisePickerView(mode: .addMore)
                            .hiddenNavigationBar()
                    }
                    .stackNavigation()
                }
            }
            ToastOverlay()
        }
        .preferredColorScheme(.dark)
        .onAppear { DeviceScreen.keepAwake(true) }
        .onDisappear { DeviceScreen.keepAwake(false) }
    }
}

// MARK: - Карточка во время тренировки

private struct ExerciseSessionView: View {
    @EnvironmentObject private var sessions: SessionController
    @EnvironmentObject private var content: ContentRepository
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var restTimer: RestTimer
    @EnvironmentObject private var notifications: NotificationScheduler
    let session: WorkoutSession
    @State private var confirmDiscard = false

    var body: some View {
        let exercise = sessions.currentExercise
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    if let exercise = exercise {
                        ExerciseCardContent(exercise: exercise)
                    } else {
                        EmptyStateView(icon: "questionmark.folder", title: "Упражнение убрано из таблицы",
                                       message: "Его удалили при обновлении контента. Переходите к следующему — прогресс сохранён.")
                    }
                }
                .padding(Theme.padding)
                .padding(.bottom, 12)
            }
            // Новая карточка открывается сверху, а не с места прокрутки предыдущей.
            .id(session.currentIndex)
            SetsPanel(session: session, exercise: exercise)
        }
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .onAppear {
            // Разрешение на «отдых окончен» спрашиваем в момент, когда оно понятно зачем.
            if settings.settings.restTimerEnabled && notifications.authorization == .notDetermined {
                Task { await notifications.requestAuthorization() }
            }
        }
        .alert(isPresented: $confirmDiscard) {
            Alert(title: Text("Прервать без сохранения?"),
                  message: Text("Отмеченные упражнения и подходы не попадут в историю. Это нельзя отменить."),
                  primaryButton: .destructive(Text("Прервать")) {
                      restTimer.stop()
                      sessions.discard()
                  },
                  secondaryButton: .cancel(Text("Продолжить тренировку")))
        }
    }

    private var header: some View {
        let position = session.position
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    sessions.isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(Text("Свернуть тренировку"))
                .accessibilityHint(Text("Прогресс сохранится, продолжить можно с главного экрана"))

                VStack(spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text("Упражнение \(position.index) из \(position.total)")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)

                Menu {
                    Button("Завершить и сохранить") {
                        restTimer.stop()
                        sessions.finish()
                    }
                    Button("Прервать без сохранения") { confirmDiscard = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: Theme.tapSize, height: Theme.tapSize)
                        .background(Circle().fill(Theme.cardRaised))
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .fixedSize()
                .accessibilityLabel(Text("Завершить тренировку"))
            }
            ProgressView(value: Double(position.index), total: Double(max(position.total, 1)))
                .progressViewStyle(LinearProgressViewStyle(tint: Theme.accent))
                .accessibilityLabel(Text("Прогресс тренировки"))
                .accessibilityValue(Text("\(position.index) из \(position.total)"))
        }
        .padding(.horizontal, Theme.padding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

/// Нижняя панель: подходы, таймер отдыха, переход к следующему упражнению.
private struct SetsPanel: View {
    @EnvironmentObject private var sessions: SessionController
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var restTimer: RestTimer
    let session: WorkoutSession
    let exercise: Exercise?

    private var totalSets: Int? { exercise?.sets }
    private var done: Int { session.currentSetsDone }
    private var allSetsDone: Bool { totalSets.map { done >= $0 } ?? false }
    private var timerEnabled: Bool { settings.settings.restTimerEnabled }
    private var restSeconds: Int { settings.settings.restDurationSeconds }

    var body: some View {
        BottomBar {
            switch restTimer.state {
            case .running:
                RestCountdown()
            case .finished:
                Label("Отдых окончен — следующий подход!", systemImage: "bell.fill")
                    .font(.headline)
                    .foregroundColor(Theme.success)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityAddTraits(.updatesFrequently)
            case .idle:
                setsControls
            }
            navigation
        }
    }

    private var setsControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                setsCounter
                Spacer(minLength: 0)
                if done > 0 {
                    Button {
                        sessions.update { $0.undoSet() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(IconButtonStyle(tint: Theme.textSecondary))
                    .accessibilityLabel(Text("Снять отметку последнего подхода"))
                }
                if timerEnabled {
                    Button {
                        restTimer.start(seconds: restSeconds)
                    } label: {
                        Label("Отдых \(restSeconds) с", systemImage: "timer")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: Theme.tapSize)
                            .background(Capsule().fill(Theme.cardRaised))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityHint(Text("Запустить таймер отдыха вручную"))
                }
            }
            if !allSetsDone {
                Button {
                    Haptics.tap()
                    sessions.update { $0.markSetDone(totalSets: totalSets) }
                    // Отдых — только между подходами: после последнего известного подхода не нужен.
                    let isLastKnownSet = totalSets.map { done + 1 >= $0 } ?? false
                    if timerEnabled && !isLastKnownSet {
                        restTimer.start(seconds: restSeconds)
                    }
                } label: {
                    Label(timerEnabled ? "Подход выполнен · отдых \(restSeconds) с" : "Подход выполнен", systemImage: "checkmark")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var setsCounter: some View {
        if let total = totalSets {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < done ? Theme.success : Color.clear)
                        .overlay(Circle().stroke(index < done ? Theme.success : Theme.textTertiary, lineWidth: 2))
                        .frame(width: 14, height: 14)
                }
                Text("Подход \(min(done + 1, total)) из \(total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Сделано подходов: \(done) из \(total)"))
        } else {
            Text(done == 0 ? "Подходы" : "Отмечено подходов: \(done)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            if session.canGoBack {
                Button {
                    sessions.update { $0.previous() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel(Text("Предыдущее упражнение"))
            }
            Button {
                Haptics.tap()
                sessions.update { $0.next() }
            } label: {
                HStack(spacing: 8) {
                    Text(session.isLastInQueue ? "Закончить список" : "Следующее упражнение")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
            .buttonStyle(PrimaryButtonStyle(color: allSetsDone || totalSets == nil ? Theme.accent : Theme.accent.opacity(0.85)))
        }
    }
}

/// Обратный отсчёт отдыха.
private struct RestCountdown: View {
    @EnvironmentObject private var restTimer: RestTimer
    @ScaledMetric(relativeTo: .largeTitle) private var digitsSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Отдых")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                    Text(Formatters.timer(restTimer.remaining))
                        .font(.system(size: digitsSize, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(Theme.textPrimary)
                        .accessibilityLabel(Text("Осталось \(restTimer.remaining) секунд"))
                }
                Spacer()
                Button("+15 с") { restTimer.extend(by: 15) }
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                    .frame(minWidth: 64, minHeight: Theme.tapSize)
                    .background(Capsule().fill(Theme.cardRaised))
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(Text("Добавить 15 секунд"))
                Button("Пропустить") { restTimer.stop() }
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.tapSize)
                    .background(Capsule().fill(Theme.cardRaised))
                    .buttonStyle(PlainButtonStyle())
            }
            ProgressView(value: restTimer.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: Theme.blue))
        }
    }
}

// MARK: - «Ещё хочешь?»

private struct MoreQuestionView: View {
    @EnvironmentObject private var sessions: SessionController
    let session: WorkoutSession

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 56))
                .foregroundColor(Theme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Ещё хочешь?")
                    .font(.largeTitle.weight(.black))
                    .foregroundColor(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Список закончился: \(RussianPlural.exercises(session.completedExerciseIds.count)) за \(Formatters.duration(Date().timeIntervalSince(session.startedAt))). Если силы остались — добери упражнения из общего списка.")
                    .font(.body)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Button("Да, хочу ещё") { sessions.update { $0.wantMore() } }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.blue))
                Button("Нет, закончить") { sessions.finish() }
                    .buttonStyle(PrimaryButtonStyle())
                Button {
                    sessions.update { $0.previous() }
                } label: {
                    Label("Вернуться к последнему упражнению", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(minHeight: Theme.tapSize)
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 520)
    }
}

// MARK: - Итог

private struct WorkoutFinishedView: View {
    @EnvironmentObject private var sessions: SessionController
    @EnvironmentObject private var userData: UserDataStore
    let entry: HistoryEntry

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.success)
                        .padding(.top, 40)
                        .accessibilityHidden(true)
                    Text("Тренировка завершена")
                        .font(.largeTitle.weight(.black))
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 12) {
                        stat(value: "\(entry.exerciseCount)", label: RussianPlural.form(entry.exerciseCount, "упражнение", "упражнения", "упражнений"))
                        stat(value: Formatters.duration(entry.duration), label: "время")
                    }
                    if !entry.bodyParts.isEmpty {
                        Text(entry.bodyParts.joined(separator: " · "))
                            .font(.headline)
                            .foregroundColor(Theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(entry.exerciseNames.enumerated()), id: \.offset) { index, name in
                            Text("\(index + 1). \(name)")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.padding)
                    .card()
                    Label("Сохранено в историю", systemImage: userData.isCloudSyncEnabled ? "checkmark.icloud" : "checkmark.circle")
                        .font(.footnote)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(Theme.padding)
            }
            BottomBar {
                Button("На главный экран") { sessions.closeFinished() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: Theme.maxContentWidth)
        .onAppear { Haptics.success() }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.weight(.bold))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .card()
        .accessibilityElement(children: .combine)
    }
}
