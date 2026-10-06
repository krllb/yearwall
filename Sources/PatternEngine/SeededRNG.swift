import Foundation

/// splitmix64. Small, fast, well-distributed, and — the reason it is here —
/// completely specified by these few lines, so its output can never drift with
/// a Swift or OS update the way `Int.random` / `arc4random` could.
public struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `[0, 1)`. 53 bits of mantissa, no floating point surprises.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform in `[lower, upper)`.
    public mutating func nextDouble(in range: Range<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    /// Uniform in `[lower, upper]`.
    public mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in `range`. Implemented here rather than via
    /// `Int.random(in:using:)` so the mapping is part of this file.
    public mutating func nextInt(in range: Range<Int>) -> Int {
        precondition(range.lowerBound < range.upperBound, "empty range")
        let span = UInt64(range.upperBound - range.lowerBound)
        return range.lowerBound + Int(next() % span)
    }

    /// `true` with probability `p`.
    public mutating func chance(_ p: Double) -> Bool {
        nextUnit() < p
    }

    /// A derived generator, so a sub-part of a drawing can have its own stream
    /// without consuming draws from the parent.
    public func branched(_ label: String) -> SeededRNG {
        SeededRNG(seed: Seeds.mix(state, Seeds.hash(label)))
    }
}

/// Seed derivation. Two levels, as specified:
/// * install seed — one per installation, fixes the "character" of the pattern
/// * day seed     — install seed mixed with `yyyy-MM-dd`, varies day to day
public enum Seeds {
    /// FNV-1a 64. Swift's own `Hasher` is randomly seeded per process and must
    /// never be used for anything that has to reproduce across launches.
    public static func hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// splitmix64 finalizer, used to fold two seeds into one.
    public static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var z = a &+ (b &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The seed for one particular day of one particular installation.
    public static func daySeed(dayKey: String, installSeed: UInt64) -> UInt64 {
        mix(installSeed, hash(dayKey))
    }

    /// A stable seed for a named sub-system (palette pick, orientation, ...)
    /// derived from the install seed alone, so it does not change daily.
    public static func installFacet(_ label: String, installSeed: UInt64) -> UInt64 {
        mix(installSeed, hash("facet:" + label))
    }
}

public extension Seeds {
    /// FNV-1a 64 over raw bytes. Used for content hashes in file names.
    static func hash<S: Sequence<UInt8>>(bytes: S) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// 16 lowercase hex characters, for file names.
    static func hexString(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }
}
