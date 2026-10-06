import Foundation

/// Where generated PNGs live, and how many of them survive.
///
/// macOS keeps its own copy of every image ever set as a wallpaper and does
/// not currently prune it. We cannot fix that from here, but we can at least
/// stop our own output from accumulating.
public struct WallpaperCache: Sendable {
    public let directory: URL
    /// How many distinct days to keep.
    public let retainedDays: Int

    public init(directory: URL? = nil, retainedDays: Int = 7) {
        self.directory = directory ?? WallpaperCache.defaultDirectory
        self.retainedDays = max(1, retainedDays)
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Yearwall/Wallpapers", isDirectory: true)
    }

    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `yearwall-2026-09-09-d1-3840x2160-dark-<hash>.png`
    /// -> day `2026-09-09`, surface `d1-3840x2160-dark`.
    ///
    /// Only files this app generated are ever parsed, and therefore only those
    /// are ever deleted.
    static func components(ofFileName name: String) -> (day: String, surface: String)? {
        guard name.hasPrefix("yearwall-"), name.hasSuffix(".png") else { return nil }
        let stem = name.dropFirst("yearwall-".count).dropLast(".png".count)
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        // year, month, day, at least one surface component, hash
        guard parts.count >= 5 else { return nil }
        let day = parts[0 ... 2].joined(separator: "-")
        guard day.count == 10, day.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
        let surface = parts[3 ..< (parts.count - 1)].joined(separator: "-")
        guard !surface.isEmpty else { return nil }
        return (day, surface)
    }

    static func dayKey(fromFileName name: String) -> String? {
        components(ofFileName: name)?.day
    }

    /// Deletes generated files that are no longer worth keeping:
    ///
    /// * anything older than the newest `retainedDays` days, and
    /// * within a kept day, every superseded render of the same surface — a
    ///   day of fiddling with settings would otherwise leave a file per change.
    ///
    /// Returns the URLs removed.
    @discardableResult
    public func prune(keeping protected: Set<URL> = []) -> [URL] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }

        struct Entry {
            let name: String
            let surface: String
            let modified: Date
        }

        var byDay: [String: [Entry]] = [:]
        for name in names {
            guard let parsed = Self.components(ofFileName: name) else { continue }
            let url = directory.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            byDay[parsed.day, default: []].append(
                Entry(name: name, surface: parsed.surface, modified: modified)
            )
        }

        let keptDays = Set(byDay.keys.sorted(by: >).prefix(retainedDays))
        let protectedPaths = Set(protected.map(\.standardizedFileURL.path))

        var doomed: [String] = []
        for (day, entries) in byDay {
            if !keptDays.contains(day) {
                doomed.append(contentsOf: entries.map(\.name))
                continue
            }
            // Keep the newest render per surface; drop the rest.
            let bySurface = Dictionary(grouping: entries, by: \.surface)
            for (_, group) in bySurface {
                let survivor = group.max { $0.modified < $1.modified }?.name
                doomed.append(contentsOf: group.map(\.name).filter { $0 != survivor })
            }
        }

        var removed: [URL] = []
        for name in doomed {
            let url = directory.appendingPathComponent(name)
            if protectedPaths.contains(url.standardizedFileURL.path) { continue }
            if (try? fm.removeItem(at: url)) != nil {
                removed.append(url)
            }
        }
        return removed
    }

    // TODO: macOS also caches every wallpaper it has ever been given, under
    // ~/Library/Application Support/com.apple.wallpaper/ (and, on older
    // systems, the desktoppicture.db store). It grows without bound. Offering
    // to clean it needs (a) confirmation that the files are not referenced by
    // the current configuration and (b) an explicit user opt-in, so it is left
    // out of v0 deliberately rather than forgotten.
}
