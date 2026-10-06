import CoreGraphics
import TimeModel

/// A generative pattern. Knows nothing about AppKit, screens, files or dates
/// beyond the `Progress` value it is handed.
public protocol Pattern: Sendable {
    static var id: String { get }
    static var displayName: String { get }
    func draw(
        progress: TimeModel.Progress,
        composition: Composition,
        rng: inout SeededRNG,
        into context: CGContext
    )

    /// Which parts of the config this pattern actually reads, so the settings
    /// UI can hide controls that would do nothing.
    static var usedConfigFields: Set<ConfigField> { get }

    /// The box the drawing covers, in canvas pixels (origin top-left), so
    /// something can be placed against it on the real desktop.
    func drawnBounds(progress: TimeModel.Progress, composition: Composition) -> CGRect
}

public extension Pattern {
    /// Instance-side access to the static identity, for existential values.
    var patternID: String { Self.id }
    var patternName: String { Self.displayName }
    var usedConfigFields: Set<ConfigField> { Self.usedConfigFields }

    /// Most patterns use everything.
    static var usedConfigFields: Set<ConfigField> { Set(ConfigField.allCases) }

    /// The area patterns lay themselves out in. An overestimate for anything
    /// that does not fill it.
    func drawnBounds(progress: TimeModel.Progress, composition: Composition) -> CGRect {
        composition.contentRect
    }
}

/// A knob in the settings UI. A pattern declares the ones it honours.
public enum ConfigField: String, Sendable, CaseIterable, Hashable {
    case theme
    case contrast
    case contentScale
    case density
    case orientation
}

/// The role a single unit of time plays in the drawing.
public enum MarkKind: Sendable {
    /// A unit already behind us: drawn at full weight.
    case elapsed
    /// The unit we are living through: the one high-contrast mark.
    case today
    /// A unit still ahead: drawn at `CompositionBudget.remainingIntensity`.
    case remaining

    public init(index: Int, progress: TimeModel.Progress) {
        if index == progress.todayIndex {
            self = .today
        } else if index < progress.elapsed {
            self = .elapsed
        } else {
            self = .remaining
        }
    }
}

/// Adding a pattern means adding a case here and nothing anywhere else.
public enum PatternLibrary {
    public struct Descriptor: Sendable, Identifiable {
        public let id: String
        public let name: String
        private let factory: @Sendable () -> any Pattern
        public func make() -> any Pattern { factory() }

        init(id: String, name: String, factory: @escaping @Sendable () -> any Pattern) {
            self.id = id
            self.name = name
            self.factory = factory
        }
    }

    public static let all: [Descriptor] = [
        Descriptor(id: GridPattern.id, name: GridPattern.displayName) { GridPattern() },
        Descriptor(id: PhyllotaxisPattern.id, name: PhyllotaxisPattern.displayName) { PhyllotaxisPattern() },
    ]

    public static let defaultID = GridPattern.id

    public static func pattern(id: String) -> any Pattern {
        (all.first { $0.id == id } ?? all[0]).make()
    }
}
