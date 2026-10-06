import AppKit

/// Mission Control's "Show Desktop": every window slides off to the screen
/// edges and the wallpaper is left in the open.
///
/// There is no public API for it. The Dock listens for a private notification
/// sent through `CoreDockSendNotification`, which is looked up at runtime so a
/// macOS that drops the symbol costs the effect and nothing else.
@MainActor
enum ShowDesktop {
    private typealias SendNotification = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Int32

    private static let send: SendNotification? = {
        // Not loaded by AppKit on its own, so `RTLD_DEFAULT` alone misses it.
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"
        guard
            let handle = dlopen(path, RTLD_LAZY),
            let symbol = dlsym(handle, "CoreDockSendNotification")
        else { return nil }
        return unsafeBitCast(symbol, to: SendNotification.self)
    }()

    /// A toggle, not a setter: the second call brings the windows back.
    /// Returns `false` when the Dock could not be asked at all.
    @discardableResult
    static func toggle() -> Bool {
        guard let send else { return false }
        return send("com.apple.showdesktop.awake" as CFString, nil) == 0
    }

    /// Whether the desktop is cleared right now, whoever cleared it.
    ///
    /// No API says so either. While Show Desktop is on, the Dock covers the
    /// screen with a window of its own just under the Dock's level (18 on
    /// macOS 26.2). Measured there: it appears about 40 ms after the toggle
    /// and is gone about 250 ms after the toggle back.
    static var isActive: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return false }
        let normalLevel = Int(CGWindowLevelForKey(.normalWindow))
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { info in
            guard
                (info[kCGWindowOwnerPID as String] as? pid_t) == dock.processIdentifier,
                let layer = info[kCGWindowLayer as String] as? Int
            else { return false }
            return layer > normalLevel && layer < dockLevel
        }
    }
}
