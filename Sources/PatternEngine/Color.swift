import CoreGraphics

/// Colour as plain numbers. No AppKit, no NSColor — this module must stay
/// drawable into any `CGContext` from any process type.
public struct RGBA: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RRGGBB`, because palettes read better that way in source.
    public init(hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public func mixed(with other: RGBA, amount t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        return RGBA(
            red + (other.red - red) * t,
            green + (other.green - green) * t,
            blue + (other.blue - blue) * t,
            alpha + (other.alpha - alpha) * t
        )
    }

    public func withAlpha(_ a: Double) -> RGBA {
        RGBA(red, green, blue, a)
    }

    /// Relative luminance (WCAG), used to sanity-check contrast in tests.
    public var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

public extension CGContext {
    func setFill(_ color: RGBA) {
        setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    func setStroke(_ color: RGBA) {
        setStrokeColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    func fillCircle(center: CGPoint, radius: CGFloat) {
        guard radius > 0 else { return }
        fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    func strokeCircle(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) {
        guard radius > 0, lineWidth > 0 else { return }
        setLineWidth(lineWidth)
        strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
