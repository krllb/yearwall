import Foundation

/// Where generated wallpapers live: only the ones on screen right now.
///
/// A render takes a fraction of a second, so there is nothing worth keeping
/// once a newer wallpaper has replaced it. macOS keeps its own copy of every
/// image ever set and does not prune it; we cannot fix that from here, but
/// our own output does not accumulate.
public struct WallpaperCache: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? WallpaperCache.defaultDirectory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Yearwall/Wallpapers", isDirectory: true)
    }

    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `yearwall-2026-09-09-d1-3840x2160-dark-<hash>.png` (or `.heic`)
    /// -> day `2026-09-09`, surface `d1-3840x2160-dark`.
    ///
    /// Only files this app generated are ever parsed, and therefore only those
    /// are ever deleted.
    static func components(ofFileName name: String) -> (day: String, surface: String)? {
        guard name.hasPrefix("yearwall-"),
              let suffix = [".png", ".heic"].first(where: { name.hasSuffix($0) })
        else { return nil }
        let stem = name.dropFirst("yearwall-".count).dropLast(suffix.count)
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        // year, month, day, at least one surface component, hash
        guard parts.count >= 5 else { return nil }
        let day = parts[0 ... 2].joined(separator: "-")
        guard day.count == 10, day.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
        let surface = parts[3 ..< (parts.count - 1)].joined(separator: "-")
        guard !surface.isEmpty else { return nil }
        return (day, surface)
    }

    /// Deletes every generated wallpaper except `keeping`, the ones on screen.
    /// Returns the URLs removed.
    @discardableResult
    public func prune(keeping current: Set<URL>) -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        let kept = Set(current.map(\.standardizedFileURL.path))

        var removed: [URL] = []
        for name in names where Self.components(ofFileName: name) != nil {
            let url = directory.appendingPathComponent(name)
            guard !kept.contains(url.standardizedFileURL.path) else { continue }
            if (try? fm.removeItem(at: url)) != nil {
                removed.append(url)
            }
        }
        return removed
    }

    // TODO: macOS keeps every wallpaper it has been given under
    // ~/Library/Application Support/com.apple.wallpaper/ and never prunes it.
    // Cleaning it needs proof a file is unreferenced plus an explicit opt-in.
}
