import AppKit
import SwiftUI
import WallpaperService

/// The settings toolbar's window: borderless and transparent, so the glass
/// bar is all there is, and placed just under the grid on the wallpaper.
///
/// Opening it clears the desktop, so the wallpaper being edited is in view
/// rather than buried under other apps. Closing it brings the windows back,
/// and so does a click anywhere else; bringing the windows back any other way
/// — the gesture, F11, a click on a window's edge — closes it. The app is an
/// accessory, so it has to activate itself before the bar can take focus.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// From the bottom row of marks to the visible top of the bar, in points.
    private static let gapBelowGrid: CGFloat = 20

    private var panel: NSPanel?
    private let store: ConfigStore
    private let service: WallpaperService
    /// Where the bar was opened. It stays on that screen until reopened.
    private var screen: NSScreen?

    /// Bumped on every open, so a restore still pending from the last close
    /// cannot undo the new session's cleared desktop.
    private var session = 0
    private var clickMonitor: Any?
    private var desktopWatch: Timer?
    /// Whether this session has seen the desktop cleared, so the watch can
    /// tell "not cleared yet" from "cleared and then brought back".
    private var sawDesktopCleared = false

    init(store: ConfigStore, service: WallpaperService) {
        self.store = store
        self.service = service
    }

    func show() {
        let panel = panel ?? makePanel()
        if !panel.isVisible {
            session += 1
            screen = screenUnderMouse()
            place(panel)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        clearDesktop()
        watchForLeaving()
    }

    /// Called after every wallpaper refresh, so the bar follows the grid once
    /// the new image is on screen rather than running ahead of it.
    func wallpaperDidChange() {
        guard let panel, panel.isVisible else { return }
        place(panel)
    }

    func windowWillClose(_ notification: Notification) {
        stopWatchingForLeaving()
        restoreDesktop()
        NSApp.setActivationPolicy(.accessory)
    }

    /// The bar changes width with its content (a longer theme name), and has
    /// to stay centred under the grid when it does.
    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        place(panel)
    }

    // MARK: - Window

    private func makePanel() -> NSPanel {
        let toolbar = SettingsToolbar(store: store) { [weak self] in self?.panel?.close() }
        let controller = NSHostingController(rootView: toolbar)
        let panel = ToolbarPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentViewController = controller
        panel.setContentSize(controller.view.fittingSize)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass draws its own edge; a window shadow would outline the
        // transparent margin instead.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // Stays put when Show Desktop sends everything else to the edges.
        panel.collectionBehavior.insert(.stationary)
        self.panel = panel
        return panel
    }

    // MARK: - Placement

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Centred under the grid, kept inside the area between the menu bar and
    /// the Dock. The middle of the screen if the grid cannot be located.
    private func place(_ panel: NSPanel) {
        guard let screen = screen ?? NSScreen.main else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let area = screen.visibleFrame

        var origin: NSPoint
        if let grid = service.drawnFrame(on: screen) {
            origin = NSPoint(
                x: grid.midX - size.width / 2,
                y: grid.minY - Self.gapBelowGrid + SettingsToolbar.margin - size.height
            )
        } else {
            origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, area.minX), area.maxX - size.width)
        origin.y = min(max(origin.y, area.minY), area.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }

    // MARK: - Desktop

    /// Asked for only when it is not already on: the call is a toggle, and on
    /// an already cleared desktop it would bring the windows back instead.
    private func clearDesktop() {
        if !ShowDesktop.isActive {
            ShowDesktop.toggle()
        }
    }

    /// Brings the windows back unless something already has.
    ///
    /// Looks only after a pause. A click on a window's edge makes the Dock end
    /// Show Desktop by itself, but its marker window lingers for about 250 ms,
    /// and a toggle sent before it is gone would clear the desktop again.
    private func restoreDesktop() {
        let closedSession = session
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.session == closedSession, ShowDesktop.isActive else { return }
            ShowDesktop.toggle()
        }
    }

    // MARK: - Leaving

    private func watchForLeaving() {
        if clickMonitor == nil {
            // Global monitors only see clicks bound for other apps, so the bar
            // and its menus never reach this.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    // A global event has no window: its location is on screen.
                    guard !Self.isInMenuBar(event.locationInWindow) else { return }
                    self?.leave(reason: "click outside")
                }
            }
        }
        if desktopWatch == nil {
            sawDesktopCleared = false
            desktopWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkDesktop() }
            }
        }
    }

    private func stopWatchingForLeaving() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        desktopWatch?.invalidate()
        desktopWatch = nil
    }

    /// The windows came back without us: the gesture, F11, a click on a
    /// window's edge, or a switch to another app.
    private func checkDesktop() {
        if ShowDesktop.isActive {
            sawDesktopCleared = true
        } else if sawDesktopCleared {
            leave(reason: "windows brought back")
        }
    }

    private func leave(reason: String) {
        guard let panel, panel.isVisible else { return }
        Diagnostics.log("settings: closed, \(reason)")
        panel.close()
    }

    /// The menu bar and its status items: using them is not leaving settings.
    private static func isInMenuBar(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
        else { return false }
        return point.y > screen.visibleFrame.maxY
    }
}

/// Borderless windows refuse key status by default, which would leave the
/// popovers and Esc without a keyboard.
private final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
