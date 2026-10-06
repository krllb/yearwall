import Foundation
import Observation
import PatternEngine
import TimeModel

/// The single persisted object.
///
/// v0 scattered settings across seven `UserDefaults` keys, which made partial
/// upgrades and partial corruption both possible. There is now one JSON blob:
/// it either loads, or falls back field by field, and the install seed can
/// never be lost while the rest survives.
@MainActor
@Observable
public final class ConfigStore {
    public static let defaultsKey = "wallpaperConfig"

    @ObservationIgnored private let defaults: UserDefaults

    public var config: WallpaperConfig {
        didSet {
            guard config != oldValue else { return }
            save()
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.defaultsKey) {
            self.config = WallpaperConfig.decoded(from: data)
        } else {
            var fresh = WallpaperConfig.default
            fresh.installSeed = Self.generateInstallSeed()
            self.config = fresh
            save()
        }

        // A blob written before the install seed existed, or by a build that
        // dropped it, must not leave every installation sharing one seed.
        if config.installSeed == WallpaperConfig.placeholderSeed {
            config.installSeed = Self.generateInstallSeed()
        }
    }

    /// One-time randomness. Not `arc4random` / `Int.random`: a UUID is hashed
    /// with the same FNV-1a used everywhere else, so the whole seeding chain
    /// stays one inspectable function.
    static func generateInstallSeed() -> UInt64 {
        Seeds.hash(UUID().uuidString + "|" + String(Date().timeIntervalSince1970))
    }

    public func update(_ mutate: (inout WallpaperConfig) -> Void) {
        var copy = config
        mutate(&copy)
        config = copy
    }

    /// Puts the composition numbers back to the ones this build ships with.
    ///
    /// Needed because the budget is persisted: without it a value tuned once
    /// would outlive every later change to the defaults, with no way to tell
    /// from the UI that it was doing so.
    public func resetBudget() {
        update { $0.budget = .default }
    }

    /// Forgets everything except the install seed, which is what makes this
    /// installation's wallpapers its own.
    public func resetToDefaults() {
        let seed = config.installSeed
        var fresh = WallpaperConfig.default
        fresh.installSeed = seed
        config = fresh
    }

    private func save() {
        guard let data = try? config.encoded() else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
