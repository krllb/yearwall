import Foundation

/// Built-in themes. Selecting one copies its values into the config, so it can
/// then be edited — there is no separate "preset" storage mode.
public enum ThemeLibrary {
    public struct Preset: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let theme: Theme
    }

    /// Black in dark mode, white in light mode. The default, and the only
    /// theme that follows the system appearance.
    public static let system = Theme(
        base: RGBA(hex: 0x000000),
        lightBase: RGBA(hex: 0xFFFFFF),
        accent: RGBA(hex: 0xFF6B57),
        contrast: 0.45
    )

    public static let black = Theme(
        base: RGBA(hex: 0x000000),
        accent: RGBA(hex: 0xFF6B57),
        contrast: 0.45
    )

    public static let white = Theme(
        base: RGBA(hex: 0xFFFFFF),
        accent: RGBA(hex: 0xFF6B57),
        contrast: 0.45
    )

    /// Warm off-white ground, dark ink.
    public static let paper = Theme(
        base: RGBA(hex: 0xF4F1EA),
        accent: RGBA(hex: 0xB5452F),
        contrast: 0.40
    )

    /// Cool blue-black, quieter still: the lowest contrast of the set.
    public static let deep = Theme(
        base: RGBA(hex: 0x0A0F1C),
        accent: RGBA(hex: 0x6C8BFF),
        contrast: 0.30
    )

    /// One clearly coloured option, to prove the colour maths holds on
    /// saturated hues.
    public static let terracotta = Theme(
        base: RGBA(hex: 0x2A1512),
        accent: RGBA(hex: 0xE8834F),
        contrast: 0.45
    )

    /// Windows 95 desktop teal, with the marks stated outright rather than
    /// derived: black behind, white ahead.
    public static let classic95 = Theme(
        base: RGBA(hex: 0x008080),
        accent: RGBA(hex: 0x000080),
        contrast: 0.55,
        elapsedOverride: RGBA(hex: 0x000000),
        remainingOverride: RGBA(hex: 0xFFFFFF)
    )

    public static let all: [Preset] = [
        Preset(id: "system", name: "System", theme: system),
        Preset(id: "black", name: "Black", theme: black),
        Preset(id: "white", name: "White", theme: white),
        Preset(id: "paper", name: "Paper", theme: paper),
        Preset(id: "deep", name: "Deep", theme: deep),
        Preset(id: "terracotta", name: "Terracotta", theme: terracotta),
        Preset(id: "classic95", name: "Classic 95", theme: classic95),
    ]

    public static let defaultID = "system"

    public static func preset(id: String) -> Preset? {
        all.first { $0.id == id }
    }
}
