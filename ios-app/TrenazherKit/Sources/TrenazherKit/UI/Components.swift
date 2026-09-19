import SwiftUI

/// Заголовок раздела в списке.
struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundColor(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

/// Пустое состояние с понятным следующим шагом.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// Отметка выбора: форма (кружок/галочка), а не только цвет.
struct SelectionMark: View {
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 26, weight: .regular))
            .foregroundColor(isOn ? Theme.blue : Theme.textTertiary)
            .frame(width: Theme.tapSize, height: Theme.tapSize)
            .accessibilityHidden(true)
    }
}

/// Небольшая метка: группа мышц, инвентарь, «сделано».
struct Chip: View {
    let text: String
    var icon: String?
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.caption2.weight(.bold))
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.cardRaised))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Кнопка ♡ — одинаковая везде: на карточке, в списках, в избранном.
struct FavoriteButton: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var userData: UserDataStore
    let itemId: String
    let type: FavoriteItem.ItemType
    let title: String

    var body: some View {
        let isOn = userData.isFavorite(itemId, type: type)
        Button {
            app.toggleFavorite(itemId: itemId, type: type, title: title)
        } label: {
            Image(systemName: isOn ? "heart.fill" : "heart")
        }
        .buttonStyle(IconButtonStyle(tint: isOn ? Theme.accent : Theme.textPrimary))
        .accessibilityLabel(Text(isOn ? "Убрать из избранного" : "Добавить в избранное"))
    }
}

/// Сообщение внизу экрана с «Отменить».
struct ToastOverlay: View {
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = toasts.current {
                HStack(spacing: 12) {
                    Text(toast.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let actionTitle = toast.actionTitle {
                        Button(actionTitle) { toasts.performAction() }
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(Theme.blue)
                            .frame(minHeight: Theme.tapSize)
                            .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x0A1A3D)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
                .frame(maxWidth: Theme.maxContentWidth)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: toasts.current)
    }
}

/// Нижняя панель с кнопками поверх прокручиваемого контента.
struct BottomBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(.horizontal, Theme.padding)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundBottom.opacity(0.97).ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
    }
}

enum Formatters {
    static let dayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE, d MMMM · HH:mm"
        return formatter
    }()

    static let relative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) мин" }
        return "\(minutes / 60) ч \(minutes % 60) мин"
    }

    static func megabytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 МБ" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func timer(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
