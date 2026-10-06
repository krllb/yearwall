import CoreGraphics

/// The surface, and nothing else: how many pixels, how dense, which appearance.
///
/// Deliberately free of colours, budgets and seeds — those live in
/// `WallpaperConfig`. The two are combined into a `Composition`, which is what
/// patterns actually draw against.
public struct CanvasSpec: Sendable, Equatable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Pixels per point. Insets expressed in points are multiplied by this.
    public let scale: Double
    public let appearance: Appearance

    public init(pixelWidth: Int, pixelHeight: Int, scale: Double, appearance: Appearance) {
        self.pixelWidth = max(1, pixelWidth)
        self.pixelHeight = max(1, pixelHeight)
        self.scale = max(0.1, scale)
        self.appearance = appearance
    }

    public var bounds: CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
    }

    public var minSide: CGFloat { min(bounds.width, bounds.height) }
}
