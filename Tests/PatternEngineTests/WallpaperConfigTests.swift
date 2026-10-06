import XCTest
@testable import PatternEngine
@testable import TimeModel

final class WallpaperConfigTests: XCTestCase {
    func testRoundTrip() throws {
        var config = WallpaperConfig.default
        config.birthDate = Date(timeIntervalSinceReferenceDate: 123_456)
        config.adopt(preset: ThemeLibrary.preset(id: "terracotta")!)
        config.installSeed = 0xABCD_EF01_2345_6789

        XCTAssertEqual(WallpaperConfig.decoded(from: try config.encoded()), config)
    }

    /// The budget is editable in the settings window, so it is stored: the
    /// values become the user's rather than the build's.
    func testTheBudgetIsPersisted() throws {
        var config = WallpaperConfig.default
        config.budget.contentScale = 0.11
        config.budget.rowGapPoints = 21.5

        let reloaded = WallpaperConfig.decoded(from: try config.encoded())
        XCTAssertEqual(reloaded.budget.contentScale, 0.11)
        XCTAssertEqual(reloaded.budget.rowGapPoints, 21.5)
    }

    /// The flip side, and the reason the reset button exists: a stored budget
    /// outlives every later change to the defaults.
    func testAStoredBudgetOutlivesTheDefaults() {
        let stored = #"{"installSeed":5,"budget":{"contentScale":0.05}}"#
        let config = WallpaperConfig.decoded(from: Data(stored.utf8))
        XCTAssertEqual(config.budget.contentScale, 0.05)
        // Fields it did not mention still track the build.
        XCTAssertEqual(config.budget.rowGapPoints, CompositionBudget.default.rowGapPoints)
    }

    func testEncodingIsStableSoFingerprintsAre() throws {
        let config = WallpaperConfig.default
        XCTAssertEqual(try config.encoded(), try config.encoded())
    }

    // MARK: - Lenient decoding

    func testAnEmptyObjectDecodesToTheDefaults() {
        XCTAssertEqual(WallpaperConfig.decoded(from: Data("{}".utf8)), .default)
    }

    func testGarbageDecodesToTheDefaults() {
        XCTAssertEqual(WallpaperConfig.decoded(from: Data("not json at all".utf8)), .default)
        XCTAssertEqual(WallpaperConfig.decoded(from: Data()), .default)
        XCTAssertEqual(WallpaperConfig.decoded(from: Data("[1,2,3]".utf8)), .default)
    }

    /// The blob a crash mid-write, or a half-finished sync, would leave behind.
    func testATruncatedBlobKeepsTheFieldsItStillHas() throws {
        var config = WallpaperConfig.default
        config.installSeed = 0x1234_5678_9ABC_DEF0
        let full = String(decoding: try config.encoded(), as: UTF8.self)

        // Cut the JSON short and close the object, the way a partial write plus
        // recovery would leave it.
        let cut = full.prefix(full.count / 2)
        let truncated = Data((cut.prefix(while: { $0 != "\n" }) + "\"}").utf8)

        let decoded = WallpaperConfig.decoded(from: truncated)
        // Whatever survived is honoured; whatever did not falls back.
        XCTAssertTrue(PatternLibrary.all.contains { $0.id == decoded.patternID })
        XCTAssertEqual(decoded.lifespanYears, WallpaperConfig.default.lifespanYears)
        XCTAssertTrue(Theme.contrastRange.contains(decoded.theme.contrast))
    }

    func testUnknownFieldsAreIgnoredAndMissingOnesFallBack() {
        let json = """
        {
          "installSeed": 99,
          "somethingFromTheFuture": {"a": 1}
        }
        """
        let config = WallpaperConfig.decoded(from: Data(json.utf8))
        XCTAssertEqual(config.installSeed, 99)
        XCTAssertEqual(config.budget, .default)
        XCTAssertEqual(config.theme, WallpaperConfig.default.theme)
        XCTAssertEqual(config.mode, .year)
    }

    func testAFieldOfTheWrongTypeFallsBackWithoutLosingTheRest() {
        let json = """
        {"installSeed": 7, "mode": "sideways", "lifespanYears": "many"}
        """
        let config = WallpaperConfig.decoded(from: Data(json.utf8))
        XCTAssertEqual(config.mode, .year)
        XCTAssertEqual(config.lifespanYears, WallpaperConfig.default.lifespanYears)
        XCTAssertEqual(config.installSeed, 7, "a bad neighbour must not cost us the install seed")
    }

    /// Settings no longer offer a pattern or a mode, so a choice saved while
    /// they did must not keep an installation off the year grid.
    func testRetiredChoicesAreNotRestored() throws {
        let stored = #"{"patternID": "phyllotaxis", "mode": "life", "installSeed": 3}"#
        let config = WallpaperConfig.decoded(from: Data(stored.utf8))
        XCTAssertEqual(config.patternID, GridPattern.id)
        XCTAssertEqual(config.mode, .year)
        XCTAssertEqual(config.installSeed, 3)

        var inMemory = WallpaperConfig.default
        inMemory.patternID = PhyllotaxisPattern.id
        inMemory.mode = .life
        let reloaded = WallpaperConfig.decoded(from: try inMemory.encoded())
        XCTAssertEqual(reloaded.patternID, GridPattern.id)
        XCTAssertEqual(reloaded.mode, .year)
    }

    func testAnUnknownPatternIDStillResolvesToAPattern() {
        var config = WallpaperConfig.default
        config.patternID = "does-not-exist"
        XCTAssertNotNil(config.pattern())
    }

    // MARK: - Derived values

    func testDaySeedComesFromTheConfig() {
        var config = WallpaperConfig.default
        config.installSeed = 4242
        XCTAssertEqual(
            config.daySeed(dayKey: "2026-09-09"),
            Seeds.daySeed(dayKey: "2026-09-09", installSeed: 4242)
        )
    }

    func testDefaultsAreSane() {
        let config = WallpaperConfig.default
        XCTAssertEqual(config.mode, .year)
        XCTAssertNil(config.birthDate)
        XCTAssertEqual(config.lifespanYears, 80)
        XCTAssertTrue(PatternLibrary.all.contains { $0.id == config.patternID })
        XCTAssertEqual(config.theme, ThemeLibrary.black)
        XCTAssertEqual(config.themePresetID, ThemeLibrary.defaultID)
    }

    // MARK: - Themes follow their preset until edited

    func testAFollowedPresetIsRefreshedFromTheLibrary() {
        // A build that retunes a preset must reach an installation that already
        // saved one, otherwise the stored copy wins for ever.
        let stale = #"{"themePresetID":"paper","theme":{"base":{"red":1,"green":0,"blue":0,"alpha":1},"accent":{"red":0,"green":1,"blue":0,"alpha":1},"contrast":0.04,"isDarkVariant":true},"installSeed":3}"#
        let config = WallpaperConfig.decoded(from: Data(stale.utf8))
        XCTAssertEqual(config.theme, ThemeLibrary.paper, "the stale copy must not win")
    }

    func testEditingTheColoursStopsFollowingThePreset() throws {
        var config = WallpaperConfig.default
        XCTAssertNotNil(config.themePresetID)

        config.customiseTheme { $0.contrast = 0.07 }
        XCTAssertNil(config.themePresetID)
        XCTAssertEqual(config.theme.contrast, 0.07)

        let reloaded = WallpaperConfig.decoded(from: try config.encoded())
        XCTAssertNil(reloaded.themePresetID)
        XCTAssertEqual(reloaded.theme.contrast, 0.07, "a custom theme is the user's, not the library's")
    }

    func testAdoptingAPresetStartsFollowingItAgain() {
        var config = WallpaperConfig.default
        config.customiseTheme { $0.contrast = 0.07 }
        config.adopt(preset: ThemeLibrary.preset(id: "deep")!)

        XCTAssertEqual(config.themePresetID, "deep")
        XCTAssertEqual(config.theme, ThemeLibrary.deep)
    }

    func testAStatedThemeRoundTrips() throws {
        var config = WallpaperConfig.default
        config.adopt(preset: ThemeLibrary.preset(id: "classic95")!)
        let reloaded = WallpaperConfig.decoded(from: try config.encoded())

        XCTAssertEqual(reloaded.theme.elapsedOverride, RGBA(hex: 0x000000))
        XCTAssertEqual(reloaded.theme.remainingOverride, RGBA(hex: 0xFFFFFF))
        XCTAssertFalse(reloaded.theme.followsAppearance)
    }

    func testAnUnknownPresetIDFallsBackToTheStoredColours() {
        let retired = #"{"themePresetID":"retired","theme":{"base":{"red":0.5,"green":0.5,"blue":0.5,"alpha":1},"accent":{"red":1,"green":0,"blue":0,"alpha":1},"contrast":0.2,"isDarkVariant":true},"installSeed":3}"#
        let config = WallpaperConfig.decoded(from: Data(retired.utf8))
        XCTAssertEqual(config.theme.base, RGBA(0.5, 0.5, 0.5, 1))
    }

}
