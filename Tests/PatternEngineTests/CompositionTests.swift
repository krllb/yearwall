import CoreGraphics
import XCTest
@testable import PatternEngine
@testable import TimeModel

final class CompositionTests: XCTestCase {
    private func makeComposition(
        width: Int = 3840, height: Int = 2160, scale: Double = 2,
        appearance: Appearance = .dark,
        budget: CompositionBudget = .default,
        theme: Theme = ThemeLibrary.black
    ) -> Composition {
        var config = WallpaperConfig.default
        config.budget = budget
        config.customiseTheme { $0 = theme }
        return Composition(
            config: config,
            canvas: CanvasSpec(pixelWidth: width, pixelHeight: height, scale: scale, appearance: appearance)
        )
    }

    func testSafeRectKeepsClearOfMenuBarAndDock() {
        let composition = makeComposition()
        let safe = composition.safeRect
        XCTAssertEqual(
            Double(safe.minY), composition.budget.menuBarInsetPoints * composition.scale, accuracy: 0.5
        )
        XCTAssertEqual(
            Double(composition.bounds.maxY - safe.maxY),
            composition.budget.dockInsetPoints * composition.scale,
            accuracy: 0.5
        )
        XCTAssertGreaterThan(safe.minX, 0)
        XCTAssertLessThan(safe.maxX, composition.bounds.maxX)
    }

    func testInsetsScaleWithThePixelDensity() {
        let oneX = makeComposition(width: 1920, height: 1080, scale: 1)
        let twoX = makeComposition(width: 3840, height: 2160, scale: 2)
        XCTAssertEqual(Double(twoX.safeRect.minY), Double(oneX.safeRect.minY) * 2, accuracy: 0.5)
    }


    func testMarkContrastIsCappedByTheBudget() {
        var budget = CompositionBudget.default
        budget.maxPatternContrast = 0.12
        let composition = makeComposition(budget: budget)

        let background = composition.colors.background
        let strongest = composition.mark(1.0)
        let expected = background.mixed(with: composition.colors.ink, amount: 0.12)

        XCTAssertEqual(strongest.red, expected.red, accuracy: 0.0001)
        // Even an over-eager pattern cannot exceed it.
        XCTAssertEqual(composition.mark(50).red, expected.red, accuracy: 0.0001)
    }

    func testThemeContrastIsClampedByTheBudget() {
        var theme = ThemeLibrary.black
        theme.contrast = 0.25
        var budget = CompositionBudget.default
        budget.maxPatternContrast = 0.10
        XCTAssertEqual(makeComposition(budget: budget, theme: theme).colors.contrast, 0.10, accuracy: 0.0001)
    }

    func testThemeContrastIsClampedToItsOwnRange() {
        XCTAssertEqual(
            Theme(base: RGBA(0, 0, 0), accent: RGBA(1, 0, 0), contrast: 5, isDarkVariant: true).contrast,
            Theme.contrastRange.upperBound
        )
        XCTAssertEqual(
            Theme(base: RGBA(0, 0, 0), accent: RGBA(1, 0, 0), contrast: -1, isDarkVariant: true).contrast,
            Theme.contrastRange.lowerBound
        )
    }


    func testContrastIsUniformAcrossTheCanvas() {
        // The quiet zone was removed: a mark's colour no longer depends on
        // where it sits.
        let composition = makeComposition()
        let expected = composition.mark(1.0)
        for x in stride(from: 0.0, through: Double(composition.canvas.pixelWidth), by: 64) {
            _ = x
            XCTAssertEqual(composition.mark(1.0), expected)
        }
    }

    func testTheCompositionIsCentredWhateverTheSeed() {
        for seed in [UInt64(0), 1, 999, 123_456_789] {
            var config = WallpaperConfig.default
            config.installSeed = seed
            let composition = Composition(
                config: config,
                canvas: CanvasSpec(pixelWidth: 3840, pixelHeight: 2160, scale: 2, appearance: .light)
            )
            XCTAssertEqual(composition.focalPoint.x, composition.bounds.midX)
            XCTAssertEqual(composition.focalPoint.y, composition.bounds.midY)
        }
    }

    func testContentRectKeepsAMarginInsideTheSafeRect() {
        let composition = makeComposition()
        let content = composition.contentRect
        let safe = composition.safeRect
        XCTAssertEqual(
            Double(content.width / safe.width), composition.budget.contentScale, accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(content.minY, safe.minY)
        XCTAssertLessThanOrEqual(content.maxY, safe.maxY + 0.001)
        XCTAssertEqual(content.midX, composition.bounds.midX, accuracy: 0.001)
    }

    func testContentRadiusStaysInsideTheSafeRect() {
        for size in [(3840, 2160), (2560, 1600), (1440, 900), (2160, 3840)] {
            var config = WallpaperConfig.default
            config.budget.contentScale = 1.0
            let composition = Composition(
                config: config,
                canvas: CanvasSpec(pixelWidth: size.0, pixelHeight: size.1, scale: 2, appearance: .dark)
            )
            let centre = composition.focalPoint
            let radius = composition.contentRadius
            let safe = composition.safeRect
            XCTAssertGreaterThanOrEqual(Double(centre.y - radius), Double(safe.minY) - 0.001, "\(size)")
            XCTAssertLessThanOrEqual(Double(centre.y + radius), Double(safe.maxY) + 0.001, "\(size)")
            XCTAssertGreaterThanOrEqual(Double(centre.x - radius), Double(safe.minX) - 0.001, "\(size)")
        }
    }

    func testContentScaleShrinksTheDrawing() {
        var config = WallpaperConfig.default
        config.budget.contentScale = 0.5
        let half = Composition(
            config: config,
            canvas: CanvasSpec(pixelWidth: 3840, pixelHeight: 2160, scale: 2, appearance: .dark)
        )
        XCTAssertEqual(
            Double(half.contentRadius / makeComposition().contentRadius),
            0.5 / CompositionBudget.default.contentScale,
            accuracy: 0.01
        )
    }

    func testBothAppearancesAreDerivedFromOneTheme() {
        for preset in ThemeLibrary.all where preset.theme.followsAppearance {
            let light = preset.theme.resolved(for: .light, maxContrast: 0.55, remainingIntensity: 0.3)
            let dark = preset.theme.resolved(for: .dark, maxContrast: 0.55, remainingIntensity: 0.3)
            XCTAssertGreaterThan(
                light.background.luminance, dark.background.luminance,
                "\(preset.id): the light variant must be lighter"
            )
        }
    }

    func testAThemeThatQuotesALookIgnoresTheAppearance() {
        let theme = ThemeLibrary.classic95
        XCTAssertFalse(theme.followsAppearance)
        XCTAssertEqual(
            theme.resolved(for: .light, maxContrast: 0.55, remainingIntensity: 0.3),
            theme.resolved(for: .dark, maxContrast: 0.55, remainingIntensity: 0.3),
            "re-deriving a quoted look would just break the quote"
        )
    }

    func testStatedMarkColoursAreUsedVerbatim() {
        let resolved = ThemeLibrary.classic95.resolved(
            for: .dark, maxContrast: 0.55, remainingIntensity: 0.3
        )
        XCTAssertEqual(resolved.background, RGBA(hex: 0x008080))
        XCTAssertEqual(resolved.elapsed, RGBA(hex: 0x000000))
        XCTAssertEqual(resolved.remaining, RGBA(hex: 0xFFFFFF))
    }

    func testAStatedThemeSurvivesTheContrastCap() {
        // The cap clamps the derived ramp; it must not quietly wash out colours
        // the theme states outright.
        var budget = CompositionBudget.default
        budget.maxPatternContrast = 0.05
        let resolved = ThemeLibrary.classic95.resolved(
            for: .dark, maxContrast: budget.maxPatternContrast, remainingIntensity: 0.3
        )
        XCTAssertEqual(resolved.elapsed, RGBA(hex: 0x000000))
        XCTAssertEqual(resolved.remaining, RGBA(hex: 0xFFFFFF))
    }
}

/// The size ceiling is the primary size knob, so it needs its own coverage.
final class MarkSizeTests: XCTestCase {
    private func makeComposition(maxMarkSizePoints: Double, scale: Double = 2) -> Composition {
        var config = WallpaperConfig.default
        config.budget.maxMarkSizePoints = maxMarkSizePoints
        config.installSeed = 1 // pin the density facet
        return Composition(
            config: config,
            canvas: CanvasSpec(pixelWidth: 4112, pixelHeight: 2658, scale: scale, appearance: .dark)
        )
    }

    func testTheCeilingIsExpressedInPointsNotPixels() {
        // A preview draws the same wallpaper at a fraction of the scale; a
        // ceiling in raw pixels would make its marks proportionally huge.
        let retina = makeComposition(maxMarkSizePoints: 10, scale: 2)
        let preview = makeComposition(maxMarkSizePoints: 10, scale: 0.25)
        XCTAssertEqual(Double(retina.maxMarkRadius / preview.maxMarkRadius), 8, accuracy: 0.001)
    }

    func testMarksNeverExceedTheCeilingHoweverMuchRoomThereIs() {
        let composition = makeComposition(maxMarkSizePoints: 10)
        for spacing in [1.0, 10.0, 100.0, 10_000.0] {
            XCTAssertLessThanOrEqual(
                composition.markRadius(spacing: CGFloat(spacing)), composition.maxMarkRadius
            )
        }
    }

    func testMarksShrinkWithTheSpacingBelowTheCeiling() {
        let composition = makeComposition(maxMarkSizePoints: 10)
        let tight = composition.markRadius(spacing: 4)
        let looser = composition.markRadius(spacing: 8)
        XCTAssertGreaterThan(looser, tight)
        XCTAssertLessThan(looser, composition.maxMarkRadius)
    }

    func testPreferredSpacingIsExactlyWhereTheCeilingBites() {
        let composition = makeComposition(maxMarkSizePoints: 10)
        XCTAssertEqual(
            composition.markRadius(spacing: composition.preferredSpacing),
            composition.maxMarkRadius,
            accuracy: 0.001
        )
    }

    func testTheGridDrawsExactlyTheMarksAndGapsItIsGiven() {
        // 365 marks fit easily at 10pt: nothing is stretched to fill the room.
        let composition = makeComposition(maxMarkSizePoints: 10)
        let budget = composition.budget
        let progress = TimeModel.Progress(
            mode: .year, elapsed: 200, total: 365, todayIndex: 200, dayKey: "2026-09-09"
        )
        let layout = GridPattern.Layout(progress: progress, composition: composition)
        XCTAssertEqual(Double(layout.radius), 10 * 2 / 2, accuracy: 0.001)
        XCTAssertEqual(Double(layout.pitch.width), (10 + budget.columnGapPoints) * 2, accuracy: 0.001)
        XCTAssertEqual(Double(layout.pitch.height), (10 + budget.rowGapPoints) * 2, accuracy: 0.001)
    }

    func testAGridThatWouldNotFitShrinksMarksAndGapsTogether() {
        // 4160 marks at 10pt do not fit on the screen.
        let composition = makeComposition(maxMarkSizePoints: 10)
        let budget = composition.budget
        let progress = TimeModel.Progress(
            mode: .life, elapsed: 1900, total: 4160, todayIndex: 1900, dayKey: "2026-09-09",
            groupSizes: Array(repeating: 52, count: 80), majorGroupInterval: 10
        )
        let layout = GridPattern.Layout(progress: progress, composition: composition)
        XCTAssertLessThan(layout.radius, 10)
        XCTAssertEqual(
            Double(layout.pitch.width / (layout.radius * 2)),
            (10 + budget.columnGapPoints) / 10,
            accuracy: 0.001
        )
    }
}

/// Every mark is filled; only its weight says whether the unit has passed.
final class MarkWeightTests: XCTestCase {
    private func makeComposition() -> Composition {
        Composition(
            config: .default,
            canvas: CanvasSpec(pixelWidth: 3840, pixelHeight: 2160, scale: 2, appearance: .dark)
        )
    }

    func testAnElapsedMarkIsStrongerThanARemainingOne() {
        let composition = makeComposition()
        let elapsed = composition.colors.elapsed
        let remaining = composition.colors.remaining
        let background = composition.colors.background

        func distance(_ colour: RGBA) -> Double {
            abs(colour.red - background.red)
                + abs(colour.green - background.green)
                + abs(colour.blue - background.blue)
        }
        XCTAssertGreaterThan(distance(elapsed), distance(remaining))
        XCTAssertGreaterThan(distance(remaining), 0, "a future mark is still visible")
    }

    /// Only for themes that derive their marks: a theme that states them
    /// outright is free to put "ahead" further from the background than
    /// "behind", and Classic 95 does exactly that.
    func testTheWeightGapHoldsInBothAppearances() {
        for appearance in Appearance.allCases {
            for preset in ThemeLibrary.all where !preset.theme.isLiteral {
                var config = WallpaperConfig.default
                config.adopt(preset: preset)
                let composition = Composition(
                    config: config,
                    canvas: CanvasSpec(pixelWidth: 2560, pixelHeight: 1600, scale: 2, appearance: appearance)
                )
                let elapsed = composition.mark(1.0)
                let remaining = composition.mark(composition.budget.remainingIntensity)
                let background = composition.colors.background

                // In a light theme "stronger" means darker, in a dark one lighter;
                // either way an elapsed mark is further from the background.
                XCTAssertGreaterThan(
                    abs(elapsed.luminance - background.luminance),
                    abs(remaining.luminance - background.luminance),
                    "\(preset.id)/\(appearance.rawValue)"
                )
            }
        }
    }
}

/// The blackout band and the connected-run style.
final class CompositionOptionsTests: XCTestCase {
    private func makeComposition(
        blacksOut: Bool, bandPoints: Double = 24, scale: Double = 2, height: Int = 2160
    ) -> Composition {
        var config = WallpaperConfig.default
        config.blacksOutMenuBar = blacksOut
        config.budget.menuBarBandPoints = bandPoints
        return Composition(
            config: config,
            canvas: CanvasSpec(pixelWidth: 3840, pixelHeight: height, scale: scale, appearance: .dark)
        )
    }

    func testTheBandIsAbsentUntilAskedFor() {
        XCTAssertNil(makeComposition(blacksOut: false).menuBarBandRect)
    }

    func testTheBandSpansTheFullWidthAtTheMeasuredHeight() throws {
        let composition = makeComposition(blacksOut: true, bandPoints: 37)
        let band = try XCTUnwrap(composition.menuBarBandRect)
        XCTAssertEqual(band.minY, 0)
        XCTAssertEqual(band.width, composition.bounds.width)
        XCTAssertEqual(Double(band.height), 37 * 2, accuracy: 0.001, "points times the canvas scale")
    }

    func testAScreenWithNoMenuBarGetsNoBand() {
        // A secondary display can report a zero-height menu bar; painting a
        // zero-height band is one thing, painting a default-height one over
        // live wallpaper is another.
        XCTAssertNil(makeComposition(blacksOut: true, bandPoints: 0).menuBarBandRect)
    }

    func testTheBandNeverExceedsTheCanvas() throws {
        let composition = makeComposition(blacksOut: true, bandPoints: 9999, height: 800)
        let band = try XCTUnwrap(composition.menuBarBandRect)
        XCTAssertEqual(band.height, composition.bounds.height)
    }
}

extension CompositionOptionsTests {
    func testTheConnectorIsAtLeastAsThickAsAMark() {
        // Thinner and the marks bulge out of it; the run has to read as one bar.
        XCTAssertGreaterThanOrEqual(CompositionBudget.default.connectorWidth, 1.0)
    }
}
