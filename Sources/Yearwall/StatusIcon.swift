import AppKit

/// The menu bar version of the app icon: one elapsed row joined into a bar,
/// a second one half way, the rest dimmed. A template image, so the system
/// tints it for light and dark menu bars.
enum StatusIcon {
    static func make() -> NSImage {
        let columns = 4
        let rows = 3
        let today = 5
        let diameter: CGFloat = 3
        let columnGap: CGFloat = 1.4
        let rowGap: CGFloat = 1.8
        let width = CGFloat(columns) * diameter + CGFloat(columns - 1) * columnGap
        let height = CGFloat(rows) * diameter + CGFloat(rows - 1) * rowGap
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: true) { _ in
            let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
            func center(_ index: Int) -> CGPoint {
                CGPoint(
                    x: origin.x + CGFloat(index % columns) * (diameter + columnGap) + diameter / 2,
                    y: origin.y + CGFloat(index / columns) * (diameter + rowGap) + diameter / 2
                )
            }

            let bars = NSBezierPath()
            bars.lineWidth = diameter
            bars.lineCapStyle = .round
            for row in 0 ..< rows {
                let first = row * columns
                let last = min(first + columns - 1, today)
                guard last > first else { continue }
                bars.move(to: center(first))
                bars.line(to: center(last))
            }
            NSColor.black.setStroke()
            bars.stroke()

            for index in (today + 1) ..< rows * columns {
                let point = center(index)
                NSColor.black.withAlphaComponent(0.4).setFill()
                NSBezierPath(ovalIn: NSRect(
                    x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter
                )).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Yearwall"
        return image
    }
}
