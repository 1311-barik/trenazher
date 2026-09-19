import SwiftUI

/// Цвета и размеры. Схема «Московское Динамо» (синий + красный) — как в прототипе;
/// финальный стиль ещё не подтверждён (ТЗ, раздел 8), поэтому всё собрано в одном месте.
public enum Theme {
    static let backgroundTop = Color(hex: 0x06142F)
    static let backgroundBottom = Color(hex: 0x0C2966)
    static let card = Color(hex: 0x12306B)
    static let cardRaised = Color(hex: 0x1A3D82)
    static let stroke = Color(hex: 0x2C58AC)
    /// Красный «Динамо» — главное действие на экране.
    static let accent = Color(hex: 0xE3222D)
    /// Синий — выбор, прогресс, второстепенные действия.
    static let blue = Color(hex: 0x3D7BF0)
    static let success = Color(hex: 0x3FD08A)
    static let warning = Color(hex: 0xF5B342)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0xB9C8EE)
    static let textTertiary = Color(hex: 0x8C9DCC)

    static let cornerRadius: CGFloat = 16
    /// Минимальная зона касания.
    static let tapSize: CGFloat = 44
    /// Ширина контента на iPad — чтобы строки не растягивались на весь экран.
    static let maxContentWidth: CGFloat = 720
    static let padding: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Фон всех экранов.
struct ScreenBackground: View {
    var body: some View {
        LinearGradient(gradient: Gradient(colors: [Theme.backgroundTop, Theme.backgroundBottom]),
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// Фон экрана + ограничение ширины контента по центру (iPad).
    func screen() -> some View {
        frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(ScreenBackground())
    }

    /// Карточка: заливка + тонкая обводка.
    func card(raised: Bool = false, highlighted: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(raised ? Theme.cardRaised : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(highlighted ? Theme.blue : Theme.stroke, lineWidth: highlighted ? 2 : 1))
    }
}

/// Главная кнопка экрана (красная, во всю ширину).
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isEnabled ? color : Theme.card))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.6))
            .contentShape(Rectangle())
    }
}

/// Второстепенная кнопка (обводка).
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(isEnabled ? Theme.textPrimary : Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardRaised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Круглая кнопка-иконка с зоной касания не меньше 44×44.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: Theme.tapSize, height: Theme.tapSize)
            .background(Circle().fill(filled ? Theme.cardRaised : Color.clear))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
