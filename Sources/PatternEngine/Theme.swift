import Foundation

/// Which variant of a theme is being rendered.
///
/// Named `Appearance` rather than `ColorScheme` because SwiftUI already owns
/// that name, and the settings UI imports both modules.
public enum Appearance: String, Sendable, Codable, CaseIterable {
    case light
    case dark

    public var isDark: Bool { self == .dark }
}

/// The user picks two colours; everything else is derived.
///
/// Four independent colour wells would let anyone build a wallpaper that makes
/// desktop icon labels unreadable, and preventing that is the app's job, not
/// the user's.
public struct Theme: Codable, Equatable, Sendable {
    /// The background. In the dark appearance only, when `lightBase` is set.
    public var base: RGBA
    /// The background in the light appearance. `nil` keeps the theme the same
    /// whatever the system appearance is.
    public var lightBase: RGBA?
    /// The only colour allowed to be high contrast.
    public var accent: RGBA
    /// How far marks travel from the background, in perceptual lightness.
    /// Clamped to `Theme.contrastRange` and again by `CompositionBudget`.
    public var contrast: Double
    /// Colour of a unit already behind us, when deriving it from `base` will
    /// not do.
    ///
    /// Derivation moves one way along a lightness ramp, which cannot express a
    /// theme whose two mark colours sit on opposite sides of the background —
    /// black behind and white ahead, on teal.
    public var elapsedOverride: RGBA?
    /// Colour of a unit still ahead. Same reasoning as `elapsedOverride`.
    public var remainingOverride: RGBA?

    /// Below 0.2 a mark on black is #333 on #000 and reads as almost nothing.
    public static let contrastRange: ClosedRange<Double> = 0.04 ... 0.55

    public init(
        base: RGBA,
        lightBase: RGBA? = nil,
        accent: RGBA,
        contrast: Double,
        elapsedOverride: RGBA? = nil,
        remainingOverride: RGBA? = nil
    ) {
        self.base = base
        self.lightBase = lightBase
        self.accent = accent
        self.contrast = contrast.clamped(to: Theme.contrastRange)
        self.elapsedOverride = elapsedOverride
        self.remainingOverride = remainingOverride
    }

    /// How opaque a custom theme's marks still ahead are, relative to its
    /// marks already behind.
    public static let customRemainingOpacity = 0.3

    /// A fixed theme with these two colours, the way the Custom editor
    /// builds one: marks still ahead are `marks` at reduced opacity.
    public static func custom(background: RGBA, marks: RGBA, accent: RGBA) -> Theme {
        Theme(
            base: background,
            accent: accent,
            contrast: contrastRange.upperBound,
            elapsedOverride: marks,
            remainingOverride: marks.withAlpha(marks.alpha * customRemainingOpacity)
        )
    }

    /// Whether the theme switches with the system appearance.
    public var followsAppearance: Bool { lightBase != nil }

    /// True when the mark colours are stated outright rather than derived.
    public var isLiteral: Bool { elapsedOverride != nil || remainingOverride != nil }

    /// Missing or malformed fields decode to the default theme's values.
    public init(from decoder: any Decoder) throws {
        let fallback = ThemeLibrary.system
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        self.init(
            base: container.lenient(.base, fallback.base),
            lightBase: container.lenient(.lightBase, nil),
            accent: container.lenient(.accent, fallback.accent),
            contrast: container.lenient(.contrast, fallback.contrast),
            elapsedOverride: container.lenient(.elapsedOverride, fallback.elapsedOverride),
            remainingOverride: container.lenient(.remainingOverride, fallback.remainingOverride)
        )
    }

    // MARK: - Derivation

    /// The concrete colours for one appearance. Marks are the background mixed
    /// toward white on a dark background and toward black on a light one.
    public func resolved(
        for appearance: Appearance,
        maxContrast: Double,
        remainingIntensity: Double
    ) -> ResolvedTheme {
        let contrast = min(self.contrast, maxContrast)
        let background = appearance.isDark ? base : (lightBase ?? base)
        let ink = background.luminance < 0.5 ? RGBA(1, 1, 1) : RGBA(0, 0, 0)
        let weight = min(max(remainingIntensity, 0), 1)
        return ResolvedTheme(
            background: background,
            elapsed: elapsedOverride ?? background.mixed(with: ink, amount: contrast),
            remaining: remainingOverride ?? background.mixed(with: ink, amount: contrast * weight),
            accent: accent,
            contrast: contrast,
            ink: ink
        )
    }
}

/// A theme resolved for one appearance. Patterns only ever see this.
public struct ResolvedTheme: Sendable, Equatable {
    public let background: RGBA
    /// Colour of a unit of time already behind us.
    public let elapsed: RGBA
    /// Colour of a unit still ahead.
    public let remaining: RGBA
    public let accent: RGBA
    /// The contrast actually used, after clamping.
    public let contrast: Double
    /// The end of the ramp: white on a dark background, black on a light one.
    public let ink: RGBA

    /// Any intensity along the ramp, capped by construction: a pattern cannot
    /// exceed the budget by passing a large number.
    public func mark(_ intensity: Double) -> RGBA {
        background.mixed(with: ink, amount: contrast * intensity.clamped(to: 0 ... 1))
    }
}

public extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
