import Foundation
import TimeModel

/// Everything the wallpaper is a function of, apart from the date itself.
///
/// Rendering reads nothing else: no `UserDefaults`, no `NSApp`, no globals.
/// Two processes handed the same config, the same date and the same canvas
/// produce the same bytes.
public struct WallpaperConfig: Codable, Equatable, Sendable {
    /// Not persisted: the app only counts the days of the year now, and a
    /// stored `.life` would keep an installation on it with no way back.
    /// Settable in memory for `--preview --mode life`.
    public var mode: TimeMode
    /// Only meaningful in `.life`.
    public var birthDate: Date?
    public var lifespanYears: Int
    /// Not persisted: the app only offers the grid, and a stored id would keep
    /// an installation on whatever it picked back when there was a choice.
    /// Settable in memory for `--preview --pattern` and the renderer tests.
    public var patternID: String
    /// Draw the elapsed run as one continuous line through the marks instead
    /// of by weight.
    ///
    /// Every mark is then the same colour and what has passed is shown by a
    /// line struck through it, so a finished month reads as a single bar rather
    /// than as thirty-one separate dots.
    public var connectsElapsedMarks: Bool
    /// Paint the strip under the menu bar black.
    ///
    /// macOS tints the menu bar from whatever is behind it, which on a
    /// saturated wallpaper turns the bar the same colour. A black band gives it
    /// back a neutral background without darkening the rest of the picture.
    public var blacksOutMenuBar: Bool
    /// The preset the theme follows, or `nil` once its colours have been
    /// edited by hand.
    ///
    /// Storing only the values — the model the brief describes — means a build
    /// that retunes a preset cannot reach an installation that already saved
    /// one: the copy in the config keeps winning, with nothing to show for it.
    /// Following the preset by id until the user edits it keeps both properties:
    /// presets stay tunable, and an edited theme stays the user's.
    public private(set) var themePresetID: String?
    /// Read-only from outside: assigning colours while a preset is still being
    /// followed would appear to work and then revert on the next load. Go
    /// through `adopt(preset:)` or `customiseTheme(_:)`.
    public private(set) var theme: Theme
    public var budget: CompositionBudget
    /// Generated once per installation. Fixes the pattern's day-independent
    /// character, and is mixed into every day seed.
    public var installSeed: UInt64

    public init(
        mode: TimeMode = .year,
        birthDate: Date? = nil,
        lifespanYears: Int = ProgressCalculator.defaultLifespanYears,
        patternID: String = PatternLibrary.defaultID,
        connectsElapsedMarks: Bool = true,
        blacksOutMenuBar: Bool = false,
        themePresetID: String? = ThemeLibrary.defaultID,
        theme: Theme = ThemeLibrary.black,
        budget: CompositionBudget = .default,
        installSeed: UInt64 = WallpaperConfig.placeholderSeed
    ) {
        self.mode = mode
        self.birthDate = birthDate
        self.lifespanYears = max(1, lifespanYears)
        self.patternID = patternID
        self.connectsElapsedMarks = connectsElapsedMarks
        self.blacksOutMenuBar = blacksOutMenuBar
        self.themePresetID = themePresetID
        // A followed preset is the source of truth for the colours.
        self.theme = themePresetID.flatMap { ThemeLibrary.preset(id: $0)?.theme } ?? theme
        self.budget = budget
        self.installSeed = installSeed
    }

    /// Stand-in until the store generates a real one on first launch. A fixed
    /// value keeps `.default` usable from tests.
    public static let placeholderSeed: UInt64 = 0x0D07_0A11_0000_0001

    public static let `default` = WallpaperConfig()

    /// What gets written to disk.
    ///
    /// `budget` was left out of this for a while: persisting it froze whatever
    /// the defaults happened to be on the day an installation first saved, so a
    /// later build could change a default and the stored blob would keep
    /// winning — the app on screen and the app in the source disagreed with
    /// nothing to show for it. It is persisted again now that the settings
    /// window edits it, which makes the values the user's rather than the
    /// build's, and `ConfigStore.resetBudget()` is the way back to the
    /// build's.
    private enum CodingKeys: String, CodingKey {
        case birthDate
        case lifespanYears
        case connectsElapsedMarks
        case blacksOutMenuBar
        case themePresetID
        case theme
        case budget
        case installSeed
    }

    // MARK: - Derived

    /// The seed for one day of this installation.
    public func daySeed(dayKey: String) -> UInt64 {
        Seeds.daySeed(dayKey: dayKey, installSeed: installSeed)
    }

    public var character: PatternCharacter {
        PatternCharacter.derived(installSeed: installSeed)
    }

    /// Switches to a preset, and starts following it again.
    public mutating func adopt(preset: ThemeLibrary.Preset) {
        themePresetID = preset.id
        theme = preset.theme
    }

    /// Hand-edits the colours, which stops following any preset.
    public mutating func customiseTheme(_ mutate: (inout Theme) -> Void) {
        themePresetID = nil
        mutate(&theme)
    }

    public func pattern() -> any Pattern {
        PatternLibrary.pattern(id: patternID)
    }

    // MARK: - Lenient decoding

    /// Every field falls back independently. A config written by an older or
    /// newer build, or truncated, still loads.
    public init(from decoder: any Decoder) throws {
        let fallback = WallpaperConfig()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        // An explicit null means "custom colours, follow nothing". A missing
        // key means the blob predates the field, so fall back to the default
        // preset rather than stranding it on stale values.
        let presetID: String?
        if container.contains(.themePresetID) {
            presetID = (try? container.decodeIfPresent(String.self, forKey: .themePresetID)) ?? nil
        } else {
            presetID = fallback.themePresetID
        }
        self.init(
            birthDate: container.lenient(.birthDate, fallback.birthDate),
            lifespanYears: container.lenient(.lifespanYears, fallback.lifespanYears),
            connectsElapsedMarks: container.lenient(.connectsElapsedMarks, fallback.connectsElapsedMarks),
            blacksOutMenuBar: container.lenient(.blacksOutMenuBar, fallback.blacksOutMenuBar),
            themePresetID: presetID,
            theme: container.lenient(.theme, fallback.theme),
            budget: container.lenient(.budget, fallback.budget),
            installSeed: container.lenient(.installSeed, fallback.installSeed)
        )
    }

    /// Written by hand only so `themePresetID` survives as an explicit null;
    /// the synthesised encoder would drop the key and the next load would read
    /// a hand-edited theme as "still following the default preset".
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encode(lifespanYears, forKey: .lifespanYears)
        try container.encode(connectsElapsedMarks, forKey: .connectsElapsedMarks)
        try container.encode(blacksOutMenuBar, forKey: .blacksOutMenuBar)
        try container.encode(themePresetID, forKey: .themePresetID)
        try container.encode(theme, forKey: .theme)
        try container.encode(budget, forKey: .budget)
        try container.encode(installSeed, forKey: .installSeed)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Never throws: an unreadable blob yields the default config.
    public static func decoded(from data: Data) -> WallpaperConfig {
        (try? JSONDecoder().decode(WallpaperConfig.self, from: data)) ?? .default
    }
}
