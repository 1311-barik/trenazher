// swift-tools-version:5.9
import PackageDescription

// Вся логика и экраны приложения живут в этом пакете.
// macOS 11 указан только для того, чтобы пакет собирался и тестировался без Xcode
// (`swift build` / `swift test` через Command Line Tools) — заодно компилятор ловит
// API новее iOS 14 / macOS 11. Само приложение — только iOS/iPadOS (см. ../project.yml).
let package = Package(
    name: "TrenazherKit",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [
        .library(name: "TrenazherKit", targets: ["TrenazherKit"]),
        .executable(name: "content-report", targets: ["ContentReport"]),
        .executable(name: "screen-previews", targets: ["ScreenPreviews"]),
    ],
    targets: [
        .target(name: "TrenazherKit"),
        .executableTarget(name: "ContentReport", dependencies: ["TrenazherKit"]),
        // Рендер экранов в PNG на Mac — посмотреть вёрстку без Xcode и симулятора.
        .executableTarget(name: "ScreenPreviews", dependencies: ["TrenazherKit"]),
        .testTarget(
            name: "TrenazherKitTests",
            dependencies: ["TrenazherKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
