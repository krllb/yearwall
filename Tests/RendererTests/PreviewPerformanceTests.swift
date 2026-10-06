import CoreGraphics
import XCTest
@testable import PatternEngine
@testable import Renderer
@testable import TimeModel

/// The live preview redraws synchronously on every config change, with no
/// debounce, so one draw has to fit in a frame.
final class PreviewPerformanceTests: XCTestCase {
    /// A 528pt card on the 2x display the settings window opens on.
    private let cardWidth = 528
    private let cardHeight = 341

    private func timeDraw(patternID: String, mode: TimeMode, total: Int) -> Double {
        var config = WallpaperConfig.default
        config.patternID = patternID
        config.mode = mode
        let canvas = CanvasSpec(
            pixelWidth: cardWidth * 2, pixelHeight: cardHeight * 2, scale: 2, appearance: .dark
        )
        let composition = Composition(config: config, canvas: canvas)
        let progress = TimeModel.Progress(
            mode: mode, elapsed: total / 2, total: total, todayIndex: total / 2, dayKey: "2026-09-09"
        )
        let context = CGContext(
            data: nil, width: canvas.pixelWidth, height: canvas.pixelHeight, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        let renderer = WallpaperRenderer()

        // Warm up, then take the best of five: this measures the draw, not the
        // first-touch page faults.
        renderer.draw(config: config, progress: progress, composition: composition, into: context)
        var best = Double.infinity
        for _ in 0 ..< 5 {
            let start = DispatchTime.now().uptimeNanoseconds
            renderer.draw(config: config, progress: progress, composition: composition, into: context)
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        return best
    }

    func testPreviewDrawFitsInAFrame() {
        let cases: [(name: String, id: String, mode: TimeMode, total: Int)] = [
            ("grid/year", GridPattern.id, .year, 365),
            ("phyllotaxis/year", PhyllotaxisPattern.id, .year, 365),
            ("grid/life", GridPattern.id, .life, 4160),
            ("phyllotaxis/life", PhyllotaxisPattern.id, .life, 4160),
        ]
        for testCase in cases {
            let milliseconds = timeDraw(patternID: testCase.id, mode: testCase.mode, total: testCase.total)
            print(String(format: "preview draw %@: %.2f ms", testCase.name, milliseconds))
            // 16ms is the target in an optimised build; the ceiling here is
            // loose enough to survive an unoptimised test run and still catch a
            // pattern that has become pathological.
            XCTAssertLessThan(milliseconds, 50, "\(testCase.name) is too slow to redraw synchronously")
        }
    }
}
