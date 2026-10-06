import Foundation

/// The half of the seeding that does *not* change from day to day.
///
/// Derived once from the install seed and carried on the `Composition`.
/// Placement is deliberately *not* part of it: a composition nudged off-centre
/// only ever looked like a mistake.
public struct PatternCharacter: Sendable, Equatable {
    /// Multiplies mark size. 1.0 == the pattern's own default.
    public var density: Double
    /// Global rotation in radians.
    public var orientation: Double

    public init(density: Double, orientation: Double) {
        self.density = density
        self.orientation = orientation
    }

    public static func derived(installSeed: UInt64) -> PatternCharacter {
        var rng = SeededRNG(seed: Seeds.installFacet("character", installSeed: installSeed))
        return PatternCharacter(
            density: rng.nextDouble(in: 0.88 ... 1.14),
            orientation: rng.nextDouble(in: 0 ..< (2 * Double.pi))
        )
    }
}
