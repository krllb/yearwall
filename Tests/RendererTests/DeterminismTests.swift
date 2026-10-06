import CoreGraphics
import XCTest
@testable import PatternEngine
@testable import Renderer
@testable import TimeModel

final class DeterminismTests: XCTestCase {
    private let renderer = WallpaperRenderer()

    private func makeConfig(
        patternID: String = PatternLibrary.defaultID,
        installSeed: UInt64 = 0xC0FF_EE00_1234,
        theme: Theme = ThemeLibrary.system
    ) -> WallpaperConfig {
        var config = WallpaperConfig.default
        config.patternID = patternID
        config.installSeed = installSeed
        config.customiseTheme { $0 = theme }
        return config
    }

    private func makeCanvas(appearance: Appearance = .dark) -> CanvasSpec {
        CanvasSpec(pixelWidth: 1280, pixelHeight: 800, scale: 2, appearance: appearance)
    }

    private func makeProgress(dayKey: String, todayIndex: Int, total: Int = 365) -> TimeModel.Progress {
        TimeModel.Progress(
            mode: .year, elapsed: todayIndex, total: total, todayIndex: todayIndex, dayKey: dayKey
        )
    }

    // MARK: - Phase 1 acceptance

    /// The whole point of the config extraction: no app, no defaults, no
    /// globals — just three values in and a PNG out.
    func testRenderIsCallableWithNothingRunning() throws {
        let data = try renderer.pngData(
            config: .default,
            progress: makeProgress(dayKey: "2026-09-09", todayIndex: 251),
            canvas: makeCanvas()
        )
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "PNG magic")
    }

    // MARK: - The core promise

    func testSameDaySameConfigProduceByteIdenticalPNGs() throws {
        for descriptor in PatternLibrary.all {
            let config = makeConfig(patternID: descriptor.id)
            let progress = makeProgress(dayKey: "2026-09-09", todayIndex: 251)
            let first = try renderer.pngData(config: config, progress: progress, canvas: makeCanvas())
            let second = try renderer.pngData(config: config, progress: progress, canvas: makeCanvas())
            XCTAssertEqual(first, second, "\(descriptor.id) is not deterministic")
        }
    }

    func testRenderingIsStableAcrossManyRepeats() throws {
        let config = makeConfig()
        let progress = makeProgress(dayKey: "2024-02-29", todayIndex: 59, total: 366)
        let reference = try renderer.pngData(config: config, progress: progress, canvas: makeCanvas())
        for _ in 0 ..< 5 {
            XCTAssertEqual(
                try renderer.pngData(config: config, progress: progress, canvas: makeCanvas()),
                reference
            )
        }
    }

    /// Both days sit inside one grid row. A day that opens a row does not
    /// change the connected grid yet: its lone mark gets no strike.
    func testADifferentDayProducesADifferentImage() throws {
        let config = makeConfig()
        let today = try renderer.pngData(
            config: config, progress: makeProgress(dayKey: "2026-09-08", todayIndex: 250), canvas: makeCanvas()
        )
        let tomorrow = try renderer.pngData(
            config: config, progress: makeProgress(dayKey: "2026-09-09", todayIndex: 251), canvas: makeCanvas()
        )
        XCTAssertNotEqual(today, tomorrow)
    }

    /// Phyllotaxis takes its density and orientation from the install seed.
    /// The grid does not: its mark size is a setting in points, and a seed
    /// that nudged it would make "12pt" mean something else on every Mac.
    func testADifferentInstallSeedProducesADifferentImage() throws {
        let progress = makeProgress(dayKey: "2026-09-09", todayIndex: 251)
        let mine = try renderer.pngData(
            config: makeConfig(patternID: PhyllotaxisPattern.id, installSeed: 1), progress: progress, canvas: makeCanvas()
        )
        let theirs = try renderer.pngData(
            config: makeConfig(patternID: PhyllotaxisPattern.id, installSeed: 2), progress: progress, canvas: makeCanvas()
        )
        XCTAssertNotEqual(mine, theirs)
    }

    /// Every config field that can affect the image must actually affect it,
    /// and each variant must still be reproducible.
    func testEveryConfigChangeIsVisibleAndStillReproducible() throws {
        let progress = makeProgress(dayKey: "2026-09-09", todayIndex: 251)
        let canvas = makeCanvas()
        let base = makeConfig()

        var variants: [(name: String, config: WallpaperConfig)] = []
        for descriptor in PatternLibrary.all where descriptor.id != base.patternID {
            var config = base
            config.patternID = descriptor.id
            variants.append(("pattern \(descriptor.id)", config))
        }
        func colours(_ theme: Theme) -> ResolvedTheme {
            theme.resolved(for: canvas.appearance, maxContrast: 0.55, remainingIntensity: 0.3)
        }
        // System in dark mode is Black: a preset that resolves to the same
        // colours is not expected to change the picture.
        for preset in ThemeLibrary.all where colours(preset.theme) != colours(base.theme) {
            var config = base
            config.adopt(preset: preset)
            variants.append(("theme \(preset.id)", config))
        }
        var lowContrast = base
        lowContrast.customiseTheme { $0.contrast = 0.06 }
        variants.append(("contrast", lowContrast))

        var smaller = base
        smaller.budget.maxMarkSizePoints = 6
        variants.append(("mark size", smaller))

        var wideColumns = base
        wideColumns.budget.columnGapPoints = 14
        variants.append(("column gap", wideColumns))

        var wideRows = base
        wideRows.budget.rowGapPoints = 30
        variants.append(("row gap", wideRows))

        var wideInsets = base
        wideInsets.budget.dockInsetPoints = 240
        variants.append(("dock inset", wideInsets))

        let reference = try renderer.pngData(config: base, progress: progress, canvas: canvas)
        for variant in variants {
            let data = try renderer.pngData(config: variant.config, progress: progress, canvas: canvas)
            XCTAssertNotEqual(data, reference, "\(variant.name) changed nothing")
            XCTAssertEqual(
                data,
                try renderer.pngData(config: variant.config, progress: progress, canvas: canvas),
                "\(variant.name) is not reproducible"
            )
        }
    }

    func testLightAndDarkDiffer() throws {
        let config = makeConfig(patternID: GridPattern.id)
        let progress = makeProgress(dayKey: "2026-09-09", todayIndex: 251)
        XCTAssertNotEqual(
            try renderer.pngData(config: config, progress: progress, canvas: makeCanvas(appearance: .light)),
            try renderer.pngData(config: config, progress: progress, canvas: makeCanvas(appearance: .dark))
        )
    }

    // MARK: - Geometry

    func testImageIsRenderedAtThePixelSizeOfTheCanvas() throws {
        for size in [(1440, 900), (3840, 2160), (5120, 2880), (4112, 2658)] {
            let image = try renderer.render(
                config: makeConfig(),
                progress: makeProgress(dayKey: "2026-09-09", todayIndex: 251),
                canvas: CanvasSpec(pixelWidth: size.0, pixelHeight: size.1, scale: 2, appearance: .dark)
            )
            XCTAssertEqual(image.width, size.0)
            XCTAssertEqual(image.height, size.1)
        }
    }

    // MARK: - "One more filled element"

    func testEachDayAddsInk() throws {
        let config = makeConfig(patternID: GridPattern.id)
        let canvas = makeCanvas()
        let background = Composition(config: config, canvas: canvas).colors.background

        func coverage(todayIndex: Int, dayKey: String) throws -> Double {
            let image = try renderer.render(
                config: config, progress: makeProgress(dayKey: dayKey, todayIndex: todayIndex), canvas: canvas
            )
            return inkCoverage(of: image, background: background)
        }

        XCTAssertGreaterThan(
            try coverage(todayIndex: 100, dayKey: "2026-04-11"),
            try coverage(todayIndex: 99, dayKey: "2026-04-10"),
            "one more day means one more filled dot"
        )
    }

    /// Mean distance from the background colour, 0...1.
    func inkCoverage(of image: CGImage, background: RGBA) -> Double {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var total = 0.0
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let r = Double(buffer[index]) / 255 - background.red
            let g = Double(buffer[index + 1]) / 255 - background.green
            let b = Double(buffer[index + 2]) / 255 - background.blue
            total += (abs(r) + abs(g) + abs(b)) / 3
        }
        return total / Double(width * height)
    }

    // MARK: - Files

    func testFileNameCarriesTheDayAndAContentHash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yearwall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try renderer.renderPNG(
            config: makeConfig(),
            progress: makeProgress(dayKey: "2026-09-09", todayIndex: 251),
            canvas: makeCanvas(),
            tag: "d1-1280x800-dark",
            into: directory
        )

        let name = result.url.lastPathComponent
        XCTAssertTrue(name.hasPrefix("yearwall-2026-09-09-d1-1280x800-dark-"), name)
        XCTAssertTrue(name.hasSuffix("\(result.contentHash).png"), name)
        XCTAssertEqual(result.contentHash.count, 16)
        XCTAssertEqual(try Data(contentsOf: result.url).count, result.byteCount)
    }

    func testTheSameInputsLandOnTheSamePath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yearwall-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        func render() throws -> URL {
            try renderer.renderPNG(
                config: makeConfig(patternID: GridPattern.id),
                progress: makeProgress(dayKey: "2026-09-09", todayIndex: 251),
                canvas: makeCanvas(), tag: "d1", into: directory
            ).url
        }

        XCTAssertEqual(try render(), try render())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }
}
