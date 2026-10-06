// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yearwall",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yearwall", targets: ["Yearwall"]),
        .library(name: "YearwallKit", targets: ["TimeModel", "PatternEngine", "Renderer", "WallpaperService"]),
    ],
    targets: [
        .target(name: "TimeModel"),
        .target(name: "PatternEngine", dependencies: ["TimeModel"]),
        .target(name: "Renderer", dependencies: ["TimeModel", "PatternEngine"]),
        .target(name: "WallpaperService", dependencies: ["TimeModel", "PatternEngine", "Renderer"]),
        .executableTarget(
            name: "Yearwall",
            dependencies: ["TimeModel", "PatternEngine", "Renderer", "WallpaperService"],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist into the bare executable so `swift run` already behaves
                // as an LSUIElement accessory app (no Dock icon).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Yearwall/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "TimeModelTests", dependencies: ["TimeModel"]),
        .testTarget(name: "PatternEngineTests", dependencies: ["PatternEngine", "TimeModel"]),
        .testTarget(name: "RendererTests", dependencies: ["Renderer", "PatternEngine", "TimeModel"]),
        .testTarget(name: "WallpaperServiceTests", dependencies: ["WallpaperService", "PatternEngine", "TimeModel"]),
    ],
    swiftLanguageModes: [.v6]
)
