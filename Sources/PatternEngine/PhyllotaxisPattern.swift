import CoreGraphics
import Foundation
import TimeModel

/// Vogel's model of a sunflower head: `r = c * sqrt(n)`, `theta = n * 137.508°`.
///
/// One dot per unit of time, in the order time passes: the innermost dot is
/// the first unit of the span, the rim is the last. Elapsed units are filled,
/// remaining ones dimmer. Every dot has the same radius and every dot is
/// filled — the spiral does the work, not size or outline variation.
public struct PhyllotaxisPattern: Pattern {
    public static let id = "phyllotaxis"
    public static let displayName = "Phyllotaxis"

    /// The golden angle, 360° * (1 - 1/phi). Vogel's 137.508° to three decimals.
    public static let goldenAngle: Double = 137.508 * .pi / 180

    public init() {}

    public func draw(
        progress: TimeModel.Progress,
        composition: Composition,
        rng: inout SeededRNG,
        into context: CGContext
    ) {
        let total = max(progress.total, 1)
        let center = composition.focalPoint

        // Day-to-day variation: how far the head opens and where it points.
        // Deliberately small — the wallpaper should look like the same object
        // seen on a different day, not like a different object.
        let spread = rng.nextDouble(in: 0.94 ... 1.0)
        let rotation = composition.character.orientation + rng.nextDouble(in: 0 ..< (2 * Double.pi))

        // Centred on the canvas, sized to stay inside the safe rect. The head
        // does reach into the quiet zone, where it is attenuated.
        let maxRadius = composition.contentRadius * CGFloat(spread)

        // Grouping in a spiral only works at the coarse level. A life has 80
        // year boundaries inside a radius of a few hundred pixels: a visible
        // gap at each one turns the phyllotaxis into eighty thin rings and
        // destroys the spiral. Only the major boundaries — decades — get a gap.
        let majorInterval = progress.majorGroupInterval
        // The unit index where each ring starts: every `majorInterval`-th group.
        let ringStarts: [Int] = {
            guard progress.hasGroups, majorInterval > 1 else { return [] }
            let starts = progress.groupStarts
            return stride(from: majorInterval, to: progress.groupCount, by: majorInterval)
                .map { starts[$0] }
        }()
        let ringGap = ringStarts.isEmpty ? 0 : composition.budget.majorGroupGap

        func ringsBefore(_ index: Int) -> Double {
            Double(ringStarts.prefix { $0 <= index }.count)
        }

        // r(n) = c * (sqrt(n) + gap * ringsBefore(n)), solved for c so the
        // outermost mark still lands on maxRadius.
        let outer = Double(max(total - 1, 1))
        let denominator = outer.squareRoot() + ringGap * ringsBefore(total - 1)
        // Grow until the marks reach their ceiling, then stop: `contentRadius`
        // is the most room the head may take, not the room it has to fill.
        let fitted = maxRadius / CGFloat(max(denominator, 0.0001))
        let preferred = composition.preferredSpacing / CGFloat(Double.pi.squareRoot())
        let c = min(fitted, preferred)
        let spacing = c * CGFloat(Double.pi.squareRoot())
        let radius: CGFloat = composition.markRadius(spacing: spacing)
        let elapsed = composition.colors.elapsed
        let remaining = composition.colors.remaining

        for index in 0 ..< total {
            let n = Double(index)
            let angle = n * Self.goldenAngle + rotation
            let distance = c * CGFloat(n.squareRoot() + ringGap * ringsBefore(index))
            let point = CGPoint(
                x: center.x + distance * CGFloat(cos(angle)),
                y: center.y + distance * CGFloat(sin(angle))
            )

            switch MarkKind(index: index, progress: progress) {
            case .elapsed, .today:
                context.setFill(elapsed)
            case .remaining:
                context.setFill(remaining)
            }
            context.fillCircle(center: point, radius: radius)
        }
    }
}
