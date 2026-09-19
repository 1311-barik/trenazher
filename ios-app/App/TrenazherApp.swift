import SwiftUI
import TrenazherKit

/// Точка входа. Вся логика и экраны — в пакете TrenazherKit.
@main
struct TrenazherApp: App {
    @StateObject private var app = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(app)
        }
    }
}
