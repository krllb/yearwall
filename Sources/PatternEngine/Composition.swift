import CoreGraphics

/// A config placed on a canvas: colours resolved, geometry precomputed.
///
/// This is the single argument a pattern draws against. Coordinates are
/// **pixels**, origin top-left, y growing downward — the renderer flips the
/// context so patterns can reason in screen terms (menu bar at the top, Dock
/// at the bottom).
public struct Composition: Sendable {
    public let config: WallpaperConfig
    public let canvas: CanvasSpec
    public let colors: ResolvedTheme
    public let character: PatternCharacter

    public init(config: WallpaperConfig, canvas: CanvasSpec) {
        self.config = config
        self.canvas = canvas
        self.colors = config.theme.resolved(
            for: canvas.appearance,
            maxContrast: config.budget.maxPatternContrast,
            remainingIntensity: config.budget.remainingIntensity
        )
        self.character = config.character
    }

    public var budget: CompositionBudget { config.budget }
    public var bounds: CGRect { canvas.bounds }
    public var scale: Double { canvas.scale }

    // MARK: - Geometry

    /// Canvas minus menu bar, Dock and side margins. Nothing meaningful is
    /// drawn outside it.
    public var safeRect: CGRect {
        let top = CGFloat(budget.menuBarInsetPoints * canvas.scale)
        let bottom = CGFloat(budget.dockInsetPoints * canvas.scale)
        let side = CGFloat(Double(canvas.pixelWidth) * budget.horizontalInsetFraction)
        let width = max(1, CGFloat(canvas.pixelWidth) - side * 2)
        let height = max(1, CGFloat(canvas.pixelHeight) - top - bottom)
        return CGRect(x: side, y: top, width: width, height: height)
    }

    /// Where the composition is centred: the middle of the canvas, so it looks
    /// centred on the screen rather than centred on whatever is left after the
    /// Dock inset is taken off the bottom.
    public var focalPoint: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// The safe rect shrunk by `budget.contentScale`, about the focal point.
    /// Patterns lay themselves out inside this, not inside the whole safe rect,
    /// so the drawing keeps a margin instead of running to the edges.
    public var contentRect: CGRect {
        let area = safeRect
        let scale = CGFloat(min(max(budget.contentScale, 0.1), 1))
        let width = area.width * scale
        let height = area.height * scale
        let centre = focalPoint
        return CGRect(
            x: centre.x - width / 2,
            y: max(area.minY, centre.y - height / 2),
            width: width,
            height: min(height, area.height)
        )
    }

    /// The largest rect centred on the focal point that stays inside the safe
    /// rect: all the room a centred drawing has, whatever `contentScale` says.
    public var centredSafeRect: CGRect {
        let area = safeRect
        let centre = focalPoint
        let halfWidth = max(0, min(centre.x - area.minX, area.maxX - centre.x))
        let halfHeight = max(0, min(centre.y - area.minY, area.maxY - centre.y))
        return CGRect(
            x: centre.x - halfWidth, y: centre.y - halfHeight,
            width: halfWidth * 2, height: halfHeight * 2
        )
    }

    /// How far a centred, circular composition may extend without leaving the
    /// safe rect. Used by the patterns that grow outward from the centre.
    public var contentRadius: CGFloat {
        let area = safeRect
        let centre = focalPoint
        let vertical = min(centre.y - area.minY, area.maxY - centre.y)
        let horizontal = min(centre.x - area.minX, area.maxX - centre.x)
        return min(vertical, horizontal) * CGFloat(min(max(budget.contentScale, 0.1), 1))
    }

    /// The strip to paint black under the menu bar, or `nil` when the option
    /// is off or this screen has no menu bar.
    public var menuBarBandRect: CGRect? {
        guard config.blacksOutMenuBar else { return nil }
        let height = CGFloat(budget.menuBarBandPoints * canvas.scale)
        guard height > 0 else { return nil }
        return CGRect(x: 0, y: 0, width: bounds.width, height: min(height, bounds.height))
    }

    // MARK: - Marks

    /// Radius of one mark, given how far apart the marks are.
    ///
    /// The single place the size ceiling is applied, so no pattern can grow its
    /// marks past it by accident.
    public func markRadius(spacing: CGFloat) -> CGFloat {
        let natural = spacing * CGFloat(budget.dotFill * character.density)
        return max(0.5, min(natural, maxMarkRadius))
    }

    public var maxMarkRadius: CGFloat {
        CGFloat(budget.maxMarkSizePoints * canvas.scale) / 2
    }

    /// The spacing at which marks reach their size ceiling.
    ///
    /// Patterns lay themselves out at `min(whatever fits, this)`, so the
    /// drawing grows until the marks are as large as they are allowed to be and
    /// then stops, instead of spreading the same marks ever thinner across the
    /// content rect. `contentScale` is the ceiling on how much room it may take,
    /// not a target it has to fill.
    public var preferredSpacing: CGFloat {
        let fill = max(budget.dotFill * character.density, 0.01)
        return maxMarkRadius / CGFloat(fill)
    }

    // MARK: - Colour

    /// The only way a pattern may produce a non-accent colour. `intensity` is
    /// 0...1 along the theme's contrast ramp, which is itself already clamped
    /// by the budget, so the cap cannot be exceeded by accident.
    public func mark(_ intensity: Double) -> RGBA {
        colors.mark(intensity)
    }
}
