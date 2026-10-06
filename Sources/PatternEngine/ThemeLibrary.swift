import Foundation

/// Built-in themes. Selecting one copies its values into the config, so it can
/// then be edited — there is no separate "preset" storage mode.
public enum ThemeLibrary {
    public struct Preset: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let theme: Theme
    }

    /// True black, neutral, near-monochrome. The default.
    public static let black = Theme(
        base: RGBA(hex: 0x000000),
        accent: RGBA(hex: 0xFF6B57),
        contrast: 0.45,
        isDarkVariant: true
    )

    /// Warm off-white ground, dark ink.
    public static let paper = Theme(
        base: RGBA(hex: 0xF4F1EA),
        accent: RGBA(hex: 0xB5452F),
        contrast: 0.40,
        isDarkVariant: false
    )

    /// Cool blue-black, quieter still. Distinct from `black` by hue and by
    /// having the lowest contrast of the set.
    public static let deep = Theme(
        base: RGBA(hex: 0x0A0F1C),
        accent: RGBA(hex: 0x6C8BFF),
        contrast: 0.30,
        isDarkVariant: true
    )

    /// One clearly coloured option, to prove the colour maths holds on
    /// saturated hues.
    public static let terracotta = Theme(
        base: RGBA(hex: 0x2A1512),
        accent: RGBA(hex: 0xE8834F),
        contrast: 0.45,
        isDarkVariant: true
    )

    /// Windows 95 desktop teal, with the marks stated outright rather than
    /// derived: black behind, white ahead.
    public static let classic95 = Theme(
        base: RGBA(hex: 0x008080),
        accent: RGBA(hex: 0x000080),
        contrast: 0.55,
        isDarkVariant: true,
        elapsedOverride: RGBA(hex: 0x000000),
        remainingOverride: RGBA(hex: 0xFFFFFF),
        followsAppearance: false
    )

    public static let all: [Preset] = [
        Preset(id: "black", name: "Black", theme: black),
        Preset(id: "paper", name: "Paper", theme: paper),
        Preset(id: "deep", name: "Deep", theme: deep),
        Preset(id: "terracotta", name: "Terracotta", theme: terracotta),
        Preset(id: "classic95", name: "Classic 95", theme: classic95),
    ]

    public static let defaultID = "black"

    public static func preset(id: String) -> Preset? {
        all.first { $0.id == id }
    }

    /// Which preset a theme currently equals, if any. Drives the "Custom"
    /// label in settings.
    public static func matchingPresetID(for theme: Theme) -> String? {
        all.first { $0.theme == theme }?.id
    }
}
