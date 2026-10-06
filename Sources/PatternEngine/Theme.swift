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
    /// The background anchor.
    public var base: RGBA
    /// The only colour allowed to be high contrast.
    public var accent: RGBA
    /// How far marks travel from the background, in perceptual lightness.
    /// Clamped to `Theme.contrastRange` and again by `CompositionBudget`.
    public var contrast: Double
    /// Which variant `base` and `accent` were authored for. The other variant
    /// is derived from the same two colours.
    public var isDarkVariant: Bool
    /// Colour of a unit already behind us, when deriving it from `base` will
    /// not do.
    ///
    /// Derivation moves one way along a lightness ramp, which cannot express a
    /// theme whose two mark colours sit on opposite sides of the background —
    /// black behind and white ahead, on teal.
    public var elapsedOverride: RGBA?
    /// Colour of a unit still ahead. Same reasoning as `elapsedOverride`.
    public var remainingOverride: RGBA?
    /// Whether the light and dark variants are derived from these colours.
    ///
    /// A theme quoting a specific look rather than describing a palette has no
    /// second variant to derive: re-deriving it would just break the quote.
    public var followsAppearance: Bool

    /// The v0 brief capped pattern contrast at roughly 20%, on the theory that
    /// a wallpaper should stay behind its icons. In practice 20% of the way
    /// from black to white is #333 on #000, which reads as almost nothing.
    /// Raised on the owner's call; the ceiling is still enforced, just higher.
    public static let contrastRange: ClosedRange<Double> = 0.04 ... 0.55

    public init(
        base: RGBA,
        accent: RGBA,
        contrast: Double,
        isDarkVariant: Bool,
        elapsedOverride: RGBA? = nil,
        remainingOverride: RGBA? = nil,
        followsAppearance: Bool = true
    ) {
        self.base = base
        self.accent = accent
        self.contrast = contrast.clamped(to: Theme.contrastRange)
        self.isDarkVariant = isDarkVariant
        self.elapsedOverride = elapsedOverride
        self.remainingOverride = remainingOverride
        self.followsAppearance = followsAppearance
    }

    /// True when the mark colours are stated outright rather than derived.
    public var isLiteral: Bool { elapsedOverride != nil || remainingOverride != nil }

    /// Missing or malformed fields decode to the default theme's values.
    public init(from decoder: any Decoder) throws {
        let fallback = ThemeLibrary.black
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = fallback
            return
        }
        self.init(
            base: container.lenient(.base, fallback.base),
            accent: container.lenient(.accent, fallback.accent),
            contrast: container.lenient(.contrast, fallback.contrast),
            isDarkVariant: container.lenient(.isDarkVariant, fallback.isDarkVariant),
            elapsedOverride: container.lenient(.elapsedOverride, fallback.elapsedOverride),
            remainingOverride: container.lenient(.remainingOverride, fallback.remainingOverride),
            followsAppearance: container.lenient(.followsAppearance, fallback.followsAppearance)
        )
    }

    // MARK: - Derivation

    /// The concrete colours for one appearance.
    ///
    /// PHASE 1 IMPLEMENTATION: lightness is moved by mixing toward white or
    /// black, which preserves hue but not perceptual step size. Phase 3
    /// replaces this with OKLCH.
    public func resolved(
        for appearance: Appearance,
        maxContrast: Double,
        remainingIntensity: Double
    ) -> ResolvedTheme {
        let contrast = min(self.contrast, maxContrast)
        let background = backgroundColor(for: appearance)
        let ink: RGBA = followsAppearance
            ? (appearance.isDark ? RGBA(1, 1, 1) : RGBA(0, 0, 0))
            : (base.luminance < 0.5 ? RGBA(1, 1, 1) : RGBA(0, 0, 0))
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

    private func backgroundColor(for appearance: Appearance) -> RGBA {
        guard followsAppearance else { return base }
        guard appearance.isDark != isDarkVariant else { return base }
        // Same hue, opposite end of the lightness range.
        return appearance.isDark
            ? base.mixed(with: RGBA(0, 0, 0), amount: 0.92)
            : base.mixed(with: RGBA(1, 1, 1), amount: 0.92)
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
    /// The end of the ramp: white in dark mode, black in light mode.
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
