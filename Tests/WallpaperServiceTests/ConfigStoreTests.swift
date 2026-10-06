import XCTest
@testable import PatternEngine
@testable import WallpaperService

@MainActor
final class ConfigStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "yearwall-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstRunStartsFromTheDefaultsWithAFreshInstallSeed() {
        let store = ConfigStore(defaults: defaults)
        XCTAssertEqual(store.config.mode, WallpaperConfig.default.mode)
        XCTAssertEqual(store.config.patternID, WallpaperConfig.default.patternID)
        XCTAssertNotEqual(store.config.installSeed, WallpaperConfig.placeholderSeed)
        XCTAssertNotNil(defaults.data(forKey: ConfigStore.defaultsKey), "first run must persist")
    }

    func testEachInstallGetsItsOwnSeed() {
        let first = ConfigStore(defaults: defaults).config.installSeed
        let other = UserDefaults(suiteName: "yearwall-tests-\(UUID().uuidString)")!
        defer { other.removePersistentDomain(forName: other.description) }
        XCTAssertNotEqual(first, ConfigStore(defaults: other).config.installSeed)
    }

    func testChangesArePersistedAsOneBlob() {
        let store = ConfigStore(defaults: defaults)
        store.update {
            $0.blacksOutMenuBar = true
            $0.adopt(preset: ThemeLibrary.preset(id: "paper")!)
        }

        // One key, not seven. Read the suite's own domain: the shared
        // dictionary representation is full of system-wide globals.
        let ourKeys = defaults.persistentDomain(forName: suiteName)?.keys.sorted() ?? []
        XCTAssertEqual(ourKeys, [ConfigStore.defaultsKey])

        let reloaded = ConfigStore(defaults: defaults)
        XCTAssertTrue(reloaded.config.blacksOutMenuBar)
        XCTAssertEqual(reloaded.config.theme, ThemeLibrary.paper)
        XCTAssertEqual(reloaded.config.themePresetID, "paper")
        XCTAssertEqual(reloaded.config.installSeed, store.config.installSeed)
    }

    func testACorruptBlobDoesNotWedgeTheApp() {
        defaults.set(Data("{ this is not json".utf8), forKey: ConfigStore.defaultsKey)
        let store = ConfigStore(defaults: defaults)
        XCTAssertEqual(store.config.patternID, WallpaperConfig.default.patternID)
        XCTAssertNotEqual(store.config.installSeed, WallpaperConfig.placeholderSeed)
    }

    func testResettingTheBudgetLeavesEverythingElseAlone() {
        let store = ConfigStore(defaults: defaults)
        store.update {
            $0.budget.contentScale = 0.2
            $0.blacksOutMenuBar = true
        }
        store.resetBudget()

        XCTAssertEqual(store.config.budget, .default)
        XCTAssertTrue(store.config.blacksOutMenuBar, "only the grid numbers reset")
    }

    func testResettingKeepsTheInstallSeed() {
        let store = ConfigStore(defaults: defaults)
        let seed = store.config.installSeed
        store.update { $0.blacksOutMenuBar = true }
        store.resetToDefaults()

        XCTAssertEqual(store.config.installSeed, seed)
        XCTAssertEqual(store.config.blacksOutMenuBar, WallpaperConfig.default.blacksOutMenuBar)
    }
}
