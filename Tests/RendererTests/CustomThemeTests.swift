import CoreGraphics
import XCTest
@testable import PatternEngine
@testable import Renderer
@testable import TimeModel

final class CustomThemeTests: XCTestCase {
    private let renderer = WallpaperRenderer()
    private let canvas = CanvasSpec(pixelWidth: 640, pixelHeight: 400, scale: 1, appearance: .dark)
    private let progress = TimeModel.Progress(
        mode: .year, elapsed: 279, total: 365, todayIndex: 279, dayKey: "2026-10-07",
        groupSizes: [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    )

    private func customConfig(marks: RGBA, backdrop: String? = nil) -> WallpaperConfig {
        var config = WallpaperConfig.default
        config.customiseTheme { $0 = .custom(background: RGBA(0, 0, 0), marks: marks, accent: $0.accent) }
        config.backdropName = backdrop
        return config
    }

    private func pixel(_ image: CGImage, _ point: CGPoint) -> [UInt8] {
        let data = CFDataGetBytePtr(image.dataProvider!.data!)!
        let offset = Int(point.y) * image.bytesPerRow + Int(point.x) * 4
        return (0 ..< 4).map { data[offset + $0] }
    }

    func testCustomMarksAheadAreFainter() {
        let theme = Theme.custom(background: RGBA(0, 0, 0), marks: RGBA(1, 1, 1, 0.6), accent: RGBA(1, 0, 0))
        XCTAssertEqual(theme.elapsedOverride, RGBA(1, 1, 1, 0.6))
        XCTAssertEqual(theme.remainingOverride?.alpha ?? 0, 0.18, accuracy: 0.0001)
        XCTAssertFalse(theme.followsAppearance)
    }

    func testBackdropIsOnlyUsedByACustomTheme() {
        var config = customConfig(marks: RGBA(1, 1, 1), backdrop: "picture.png")
        XCTAssertEqual(config.activeBackdropName, "picture.png")
        config.adopt(preset: ThemeLibrary.preset(id: "black")!)
        XCTAssertNil(config.activeBackdropName)
        XCTAssertEqual(config.backdropName, "picture.png", "kept for switching back to Custom")
    }

    func testBackdropNameRoundTrips() throws {
        let config = customConfig(marks: RGBA(1, 1, 1), backdrop: "picture.png")
        XCTAssertEqual(WallpaperConfig.decoded(from: try config.encoded()).backdropName, "picture.png")
    }

    func testBackdropReplacesTheBackground() throws {
        let red = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        red.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        red.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let backdrop = red.makeImage()!

        let image = try renderer.render(
            config: customConfig(marks: RGBA(1, 1, 1), backdrop: "red"),
            progress: progress, canvas: canvas, backdrop: backdrop
        )
        XCTAssertEqual(pixel(image, CGPoint(x: 5, y: 5)), [255, 0, 0, 255])

        var preset = customConfig(marks: RGBA(1, 1, 1), backdrop: "red")
        preset.adopt(preset: ThemeLibrary.preset(id: "black")!)
        let plain = try renderer.render(config: preset, progress: progress, canvas: canvas, backdrop: backdrop)
        XCTAssertEqual(pixel(plain, CGPoint(x: 5, y: 5)), [0, 0, 0, 255], "a preset ignores the picture")
    }

    /// A translucent colour must not get darker where a mark sits on the line.
    func testTranslucentLineHasOneOpacity() throws {
        let config = customConfig(marks: RGBA(1, 1, 1, 0.5))
        let image = try renderer.render(config: config, progress: progress, canvas: canvas)
        let layout = GridPattern.Layout(progress: progress, composition: Composition(config: config, canvas: canvas))
        let onMark = layout.center(of: 5)
        let between = CGPoint(x: (layout.center(of: 5).x + layout.center(of: 6).x) / 2, y: onMark.y)
        XCTAssertEqual(pixel(image, onMark), pixel(image, between))
        XCTAssertEqual(Double(pixel(image, onMark)[0]), 128, accuracy: 2)
    }
}
