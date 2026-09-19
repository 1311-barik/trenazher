import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var notifications: NotificationScheduler
    @EnvironmentObject private var sync: ContentSyncService
    @EnvironmentObject private var content: ContentRepository
    @EnvironmentObject private var downloader: MediaDownloader
    @EnvironmentObject private var userData: UserDataStore
    @EnvironmentObject private var toasts: ToastCenter
    @State private var confirmDeleteVideos = false
    @State private var usage: (photos: Int64, videos: Int64) = (0, 0)

    /// Пн … Вс в нумерации Calendar.
    private let weekdays: [(value: Int, title: String)] = [(2, "Пн"), (3, "Вт"), (4, "Ср"), (5, "Чт"), (6, "Пт"), (7, "Сб"), (1, "Вс")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                timerSection
                remindersSection
                contentSection
                aboutSection
            }
            .padding(Theme.padding)
        }
        .screen()
        .navigationTitle("Настройки")
        .inlineNavigationTitle()
        .onAppear(perform: refreshUsage)
        .onChange(of: sync.phase) { _ in refreshUsage() }
        .alert(isPresented: $confirmDeleteVideos) {
            Alert(title: Text("Удалить скачанные видео?"),
                  message: Text("Освободится \(Formatters.megabytes(usage.videos)). Упражнения и фото останутся; видео скачается снова при просмотре или обновлении по Wi-Fi."),
                  primaryButton: .destructive(Text("Удалить")) {
                      sync.removeDownloadedVideos()
                      refreshUsage()
                      toasts.show("Скачанные видео удалены")
                  },
                  secondaryButton: .cancel(Text("Отмена")))
        }
    }

    // MARK: Разделы

    private var timerSection: some View {
        SettingsCard(title: "Таймер отдыха", icon: "timer") {
            Toggle("Таймер между подходами", isOn: $settings.settings.restTimerEnabled)
                .toggleStyle(SwitchToggleStyle(tint: Theme.blue))
            if settings.settings.restTimerEnabled {
                Picker("Длительность", selection: $settings.settings.restDurationSeconds) {
                    ForEach(AppSettings.restDurationOptions, id: \.self) { Text("\($0) секунд").tag($0) }
                }
                .pickerStyle(SegmentedPickerStyle())
                Text("Запускается после «Подход выполнен» и кнопкой «Отдых». Время можно продлить на 15 секунд или пропустить.")
                    .settingsHint()
            }
        }
    }

    private var remindersSection: some View {
        SettingsCard(title: "Напоминания", icon: "bell") {
            Toggle("Напоминать о тренировке", isOn: $settings.settings.remindersEnabled)
                .toggleStyle(SwitchToggleStyle(tint: Theme.blue))
            if settings.settings.remindersEnabled {
                DatePicker("Время", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(CompactDatePickerStyle())
                HStack(spacing: 6) {
                    ForEach(weekdays, id: \.value) { day in
                        let isOn = settings.settings.reminderWeekdays.contains(day.value)
                        Button(day.title) {
                            if isOn { settings.settings.reminderWeekdays.remove(day.value) } else { settings.settings.reminderWeekdays.insert(day.value) }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isOn ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapSize)
                        .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? Theme.blue : Theme.cardRaised))
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    }
                }
                if settings.settings.reminderWeekdays.isEmpty {
                    Text("Выберите хотя бы один день — иначе напоминаний не будет.").settingsHint(color: Theme.warning)
                }
                if settings.isSyncedAcrossDevices {
                    Toggle("На этом устройстве", isOn: $settings.device.remindersOnThisDevice)
                        .toggleStyle(SwitchToggleStyle(tint: Theme.blue))
                    Text("Расписание общее для iPhone и iPad. Выключите на одном из них, чтобы напоминание не приходило дважды.")
                        .settingsHint()
                }
                if notifications.authorization == .denied {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Уведомления запрещены в настройках iOS — напоминания не придут.", systemImage: "exclamationmark.triangle")
                            .settingsHint(color: Theme.warning)
                        if SystemSettings.canOpen {
                            Button("Открыть настройки iOS") { SystemSettings.open() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var contentSection: some View {
        SettingsCard(title: "Упражнения и видео", icon: "arrow.triangle.2.circlepath") {
            Text("\(RussianPlural.exercises(content.manifest.exercises.count)) · готовых тренировок: \(content.workouts.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            SyncStatusView(showsButton: true)
            Toggle("Скачивать видео заранее по Wi-Fi", isOn: $settings.device.downloadVideosInAdvance)
                .toggleStyle(SwitchToggleStyle(tint: Theme.blue))
            Text(settings.device.downloadVideosInAdvance
                 ? "Видео будут доступны без интернета. Нужно место на устройстве."
                 : "Видео скачивается при первом просмотре (нужен интернет в этот момент).")
                .settingsHint()
            HStack {
                Text("Занято: фото \(Formatters.megabytes(usage.photos)), видео \(Formatters.megabytes(usage.videos))")
                    .settingsHint()
                Spacer()
            }
            if usage.videos > 0 {
                Button("Удалить скачанные видео") { confirmDeleteVideos = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            NavigationLink(destination: ContentIssuesView()) {
                HStack {
                    Text("Проверка контента")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    let count = content.issues.filter { $0.severity != .info }.count
                    Text(count == 0 ? "всё в порядке" : "замечаний: \(count)")
                        .font(.footnote)
                        .foregroundColor(count == 0 ? Theme.success : Theme.warning)
                    Image(systemName: "chevron.right").foregroundColor(Theme.textTertiary)
                }
                .frame(minHeight: Theme.tapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "Где хранятся данные", icon: userData.isCloudSyncEnabled ? "icloud" : "iphone") {
            Text(userData.isCloudSyncEnabled
                 ? "Избранное, история и настройки сохраняются в iCloud и сами появляются на iPhone и iPad с тем же Apple ID."
                 : "Избранное, история и настройки хранятся на этом устройстве и попадают в его резервную копию iCloud. На другое устройство они сами не переносятся.")
                .settingsHint()
            Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                .settingsHint(color: Theme.textTertiary)
        }
    }

    // MARK: Вспомогательное

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: settings.settings.reminderHour, minute: settings.settings.reminderMinute)) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.settings.reminderHour = components.hour ?? 19
                settings.settings.reminderMinute = components.minute ?? 0
            }
        )
    }

    private func refreshUsage() {
        usage = downloader.store.diskUsage()
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content
                .foregroundColor(Theme.textPrimary)
        }
        .padding(Theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private extension View {
    func settingsHint(color: Color = Theme.textSecondary) -> some View {
        font(.footnote)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Что приложение не смогло разобрать в таблице — с понятным следующим шагом для Жени.
struct ContentIssuesView: View {
    @EnvironmentObject private var content: ContentRepository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Приложение собирает упражнения из таблицы «Дрон тренировка» и папок на Google Drive. Здесь — что не удалось сопоставить. Упражнения при этом всё равно работают, просто без части фото или видео.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if content.issues.isEmpty {
                    EmptyStateView(icon: "checkmark.circle", title: "Замечаний нет", message: "Все файлы из таблицы найдены.")
                }
                group(.error, "Ошибки")
                group(.warning, "Нужно поправить в таблице")
                group(.info, "Для сведения")
            }
            .padding(Theme.padding)
        }
        .screen()
        .navigationTitle("Проверка контента")
        .inlineNavigationTitle()
    }

    @ViewBuilder
    private func group(_ severity: ContentIssue.Severity, _ title: String) -> some View {
        let issues = content.issues.filter { $0.severity == severity }
        if !issues.isEmpty {
            SectionTitle(title: title, trailing: "\(issues.count)")
                .padding(.top, 8)
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Text(issue.message)
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
        }
    }
}
