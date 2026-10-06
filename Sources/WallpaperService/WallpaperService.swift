import AppKit
import Foundation
import PatternEngine
import Renderer
import TimeModel

/// Owns the loop: decide what today looks like, render it for every screen,
/// hand it to the window server, keep the folder tidy, and schedule the next
/// time all of that has to happen.
@MainActor
public final class WallpaperService: NSObject {
    public struct Snapshot: Sendable {
        public let progress: TimeModel.Progress
        public let surfaces: [ScreenSurface]
        public let files: [URL]
        public let appearance: Appearance
        public let renderDuration: TimeInterval
    }

    private let store: ConfigStore
    private let cache: WallpaperCache
    private let renderer = WallpaperRenderer()
    private var timeModel: ProgressCalculator

    private var appliedFingerprint: String?
    private var appliedFiles: [CGDirectDisplayID: URL] = [:]
    private var coalesceTimer: Timer?
    private var midnightTimer: Timer?
    private var pendingReasons: [String] = []
    private var isRefreshing = false

    /// Latest successful run, for the menu bar.
    public private(set) var snapshot: Snapshot?
    /// Called on the main actor after every successful refresh.
    public var onUpdate: (@MainActor (Snapshot) -> Void)?

    public init(store: ConfigStore, cache: WallpaperCache = WallpaperCache(), timeZone: TimeZone = .current) {
        self.store = store
        self.cache = cache
        self.timeModel = ProgressCalculator(timeZone: timeZone)
        super.init()
    }

    // MARK: - Lifecycle

    public func start() {
        try? cache.ensureExists()
        logObservedDesktopImages(prefix: "before first set, observed")
        installObservers()
        scheduleNextMidnight()
        requestRefresh(reason: "launch", force: true)
    }

    public func stop() {
        coalesceTimer?.invalidate()
        midnightTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Triggers

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        workspace.addObserver(
            self, selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleAppearanceChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil
        )
    }

    @objc private func handleWake() { requestRefresh(reason: "wake") }
    @objc private func handleScreenChange() { requestRefresh(reason: "screens") }
    @objc private func handleSpaceChange() {
        // Log what the window server reports *before* we touch anything: this
        // is the only way to find out whether our image survived the switch.
        logObservedDesktopImages(prefix: "space changed, observed")
        requestRefresh(reason: "space")
    }
    @objc private func handleAppearanceChange() {
        // The distributed notification arrives slightly before NSApp's
        // effectiveAppearance settles.
        requestRefresh(reason: "appearance", delay: 0.35)
    }

    /// Schedules the *next* midnight after every fire instead of trusting a
    /// 24 hour repeating timer, which drifts across DST and sleep.
    private func scheduleNextMidnight() {
        midnightTimer?.invalidate()
        let next = timeModel.nextMidnight(after: Date())
        // A couple of seconds past the boundary: the date has definitely rolled.
        let fire = next.addingTimeInterval(2)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.requestRefresh(reason: "midnight")
                self.scheduleNextMidnight()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
        Diagnostics.log("next midnight refresh at \(fire)")
    }

    // MARK: - Coalescing

    /// Every trigger funnels through here. A wake at 00:00:05 and the midnight
    /// timer collapse into a single render.
    public func requestRefresh(reason: String, force: Bool = false, delay: TimeInterval = 0.8) {
        pendingReasons.append(reason)
        if force { appliedFingerprint = nil }
        guard coalesceTimer == nil else { return }

        let timer = Timer(fire: Date().addingTimeInterval(delay), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.coalesceTimer = nil
                let reasons = self.pendingReasons.joined(separator: "+")
                self.pendingReasons.removeAll()
                self.performRefresh(reason: reasons)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        coalesceTimer = timer
    }

    /// "Refresh now" from the menu: bypass the debounce, redo the work.
    public func refreshNow() {
        coalesceTimer?.invalidate()
        coalesceTimer = nil
        pendingReasons.removeAll()
        appliedFingerprint = nil
        performRefresh(reason: "manual")
    }

    // MARK: - The actual work

    private func performRefresh(reason: String) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let started = Date()
        let surfaces = ScreenSurveyor.surfaces()
        guard !surfaces.isEmpty else {
            Diagnostics.log("refresh(\(reason)): no screens")
            return
        }

        let appearance = currentAppearance()
        let config = store.config
        let progress = currentProgress()

        let configFingerprint = (try? config.encoded()).map {
            Seeds.hexString(Seeds.hash(bytes: $0))
        } ?? "?"
        let fingerprint = [
            configFingerprint,
            progress.dayKey,
            appearance.rawValue,
            surfaces.map(\.tag).joined(separator: ","),
        ].joined(separator: "#")

        var files: [CGDirectDisplayID: URL] = [:]
        if fingerprint == appliedFingerprint,
           appliedFiles.count == surfaces.count,
           appliedFiles.values.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            files = appliedFiles
            Diagnostics.log("refresh(\(reason)): unchanged, re-applying cached images")
        } else {
            do {
                files = try render(config: config, progress: progress, surfaces: surfaces, appearance: appearance)
            } catch {
                Diagnostics.log("refresh(\(reason)) failed: \(error)")
                return
            }
        }

        apply(files: files, reason: reason)
        appliedFingerprint = fingerprint
        appliedFiles = files
        cache.prune(keeping: Set(files.values))

        let snapshot = Snapshot(
            progress: progress,
            surfaces: surfaces,
            files: surfaces.compactMap { files[$0.displayID] },
            appearance: appearance,
            renderDuration: Date().timeIntervalSince(started)
        )
        self.snapshot = snapshot
        onUpdate?(snapshot)
        Diagnostics.log(
            "refresh(\(reason)): \(progress.summary), \(surfaces.count) screen(s), "
                + String(format: "%.0f ms", snapshot.renderDuration * 1000)
        )
    }

    private func render(
        config: WallpaperConfig,
        progress: TimeModel.Progress,
        surfaces: [ScreenSurface],
        appearance: Appearance
    ) throws -> [CGDirectDisplayID: URL] {
        try cache.ensureExists()

        var result: [CGDirectDisplayID: URL] = [:]
        for surface in surfaces {
            // The blackout band has to match this screen's actual menu bar.
            var config = config
            config.budget.menuBarBandPoints = surface.menuBarPoints
            let canvas = CanvasSpec(
                pixelWidth: surface.pixelWidth,
                pixelHeight: surface.pixelHeight,
                scale: surface.scale,
                appearance: appearance
            )
            let rendered = try renderer.renderPNG(
                config: config,
                progress: progress,
                canvas: canvas,
                tag: "\(surface.tag)-\(appearance.rawValue)",
                into: cache.directory
            )
            result[surface.displayID] = rendered.url
        }
        return result
    }

    /// `setDesktopImageURL` only touches the *current* Space of each screen, so
    /// this is called again whenever the active Space changes.
    private func apply(files: [CGDirectDisplayID: URL], reason: String) {
        let workspace = NSWorkspace.shared
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),
            .allowClipping: NSNumber(value: false),
        ]

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID, let url = files[displayID] else { continue }

            let current = workspace.desktopImageURL(for: screen)
            if current?.standardizedFileURL == url.standardizedFileURL {
                continue
            }
            do {
                try workspace.setDesktopImageURL(url, for: screen, options: options)
                Diagnostics.log("set wallpaper on display \(displayID) (\(reason)) -> \(url.lastPathComponent)")
            } catch {
                Diagnostics.log("setDesktopImageURL failed on display \(displayID): \(error)")
            }
        }
    }

    // MARK: - Appearance

    /// The only place the render path would otherwise touch global state:
    /// resolved here, once, and passed down as a value.
    public func currentAppearance() -> Appearance {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    // MARK: - Introspection (menu + README observations)

    public var cacheDirectory: URL { cache.directory }

    public func currentProgress() -> TimeModel.Progress {
        let config = store.config
        return timeModel.progress(
            for: Date(),
            mode: config.mode,
            birthDate: config.birthDate,
            lifespanYears: config.lifespanYears
        )
    }

    /// Where today's drawing sits on `screen`, in AppKit screen coordinates
    /// (points, origin bottom-left), laid out the way `render` lays it out.
    /// `nil` for a screen the surveyor does not know.
    public func drawnFrame(on screen: NSScreen) -> CGRect? {
        guard
            let displayID = screen.displayID,
            let surface = ScreenSurveyor.surfaces().first(where: { $0.displayID == displayID })
        else { return nil }

        let config = store.config
        let canvas = CanvasSpec(
            pixelWidth: surface.pixelWidth,
            pixelHeight: surface.pixelHeight,
            scale: surface.scale,
            appearance: currentAppearance()
        )
        let pixels = config.pattern().drawnBounds(
            progress: currentProgress(),
            composition: Composition(config: config, canvas: canvas)
        )
        guard !pixels.isNull else { return nil }

        // The image is stretched to the screen (`scaleAxesIndependently`), so
        // each axis maps on its own; the canvas y grows downward.
        let frame = screen.frame
        let xScale = frame.width / CGFloat(surface.pixelWidth)
        let yScale = frame.height / CGFloat(surface.pixelHeight)
        return CGRect(
            x: frame.minX + pixels.minX * xScale,
            y: frame.maxY - pixels.maxY * yScale,
            width: pixels.width * xScale,
            height: pixels.height * yScale
        )
    }

    public func logObservedDesktopImages(prefix: String) {
        for entry in observedDesktopImages() {
            let name = entry.url?.lastPathComponent ?? "<none>"
            let ours = entry.url?.deletingLastPathComponent().standardizedFileURL
                == cache.directory.standardizedFileURL
            Diagnostics.log("\(prefix): display \(entry.display) -> \(name)\(ours ? " (ours)" : "")")
        }
    }

    /// What the window server currently reports per screen. Used to check
    /// whether our image survived a Space switch.
    public func observedDesktopImages() -> [(display: CGDirectDisplayID, url: URL?)] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { ($0, NSWorkspace.shared.desktopImageURL(for: screen)) }
        }
    }
}

/// Timestamped logging to stderr and to `~/Library/Logs/Yearwall.log`.
///
/// The file matters because the app is normally launched by Launch Services,
/// where stderr goes nowhere the user can read. Nothing leaves the machine.
public enum Diagnostics {
    public static var logFileURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return logs.appendingPathComponent("Yearwall.log")
    }

    private static let lock = NSLock()
    /// Truncated when it passes this, so an always-running app cannot fill the disk.
    private static let maxBytes = 512 * 1024

    public static func log(_ message: @autoclosure () -> String) {
        let stamp = Date().ISO8601Format(.iso8601(timeZone: .current))
        let line = "[Yearwall \(stamp)] \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))
        append(line)
    }

    private static func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL
        let fm = FileManager.default
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
            try? fm.removeItem(at: url)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? Data(line.utf8).write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
