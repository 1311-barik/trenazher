import SwiftUI
#if os(iOS)
import AudioToolbox
import AVFoundation
import UIKit
#endif

// Всё платформенное — здесь. Приложение работает только на iOS/iPadOS;
// ветки для macOS нужны, чтобы пакет собирался и тестировался без Xcode.

extension View {
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    func hiddenNavigationBar() -> some View {
        #if os(iOS)
        return navigationBarHidden(true)
        #else
        return self
        #endif
    }

    /// Навигация «стопкой» и на iPad (без боковой панели split view).
    func stackNavigation() -> some View {
        #if os(iOS)
        return navigationViewStyle(StackNavigationViewStyle())
        #else
        return self
        #endif
    }

    /// Полноэкранный показ (iOS 14+). На macOS — обычный sheet, только для сборки.
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        return fullScreenCover(isPresented: isPresented, content: content)
        #else
        return sheet(isPresented: isPresented, content: content)
        #endif
    }

    func fullScreenCoverCompat<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        return fullScreenCover(item: item, content: content)
        #else
        return sheet(item: item, content: content)
        #endif
    }

    /// Листание фото свайпом.
    func pagedTabStyle(showsIndex: Bool) -> some View {
        #if os(iOS)
        return tabViewStyle(PageTabViewStyle(indexDisplayMode: showsIndex ? .always : .never))
        #else
        return self
        #endif
    }
}

enum Haptics {
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Сигнал «отдых окончен»: звук + вибрация.
    static func restFinished() {
        #if os(iOS)
        AudioServicesPlaySystemSound(1007)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

enum DeviceScreen {
    /// Не гасить экран во время тренировки.
    static func keepAwake(_ enabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = enabled
        #endif
    }
}

enum SystemSettings {
    static var canOpen: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// Открыть настройки приложения в iOS (например, чтобы разрешить уведомления).
    static func open() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

enum AudioSessionConfigurator {
    /// Звук видео слышен даже при выключенном беззвучном режиме.
    static func prepareForVideo() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
