import AppKit
import Observation
import PatternEngine
import TimeModel
import WallpaperService

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private lazy var service = WallpaperService(store: store)
    private lazy var settingsWindow = SettingsWindow(store: store, service: service)

    private var statusItem: NSStatusItem?
    private let progressItem = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        service.onUpdate = { [weak self] snapshot in
            self?.progressItem.title = snapshot.progress.summary
            self?.settingsWindow.wallpaperDidChange()
        }
        observeSettings()
        service.start()

        // Development aid: `Yearwall --settings` opens the window at launch.
        if CommandLine.arguments.contains("--settings") {
            settingsWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.stop()
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()

        let menu = NSMenu()
        menu.delegate = self

        progressItem.isEnabled = false
        menu.addItem(progressItem)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self

        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Yearwall", action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        statusItem = item
        progressItem.title = service.currentProgress().summary
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginItem.isEnabled = LoginItem.isSupported
        loginItem.toolTip = LoginItem.isSupported ? nil : LoginItem.unsupportedReason
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        service.refreshNow()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func toggleLaunchAtLogin() {
        if case let .failure(error) = LoginItem.setEnabled(!LoginItem.isEnabled) {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshLoginItemState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings changes

    /// Any config change re-renders. Tracking the whole value tracks every
    /// field that could affect the image.
    private func observeSettings() {
        withObservationTracking {
            _ = store.config
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.service.requestRefresh(reason: "settings", force: true, delay: 0.35)
                self.observeSettings()
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        progressItem.title = (service.snapshot?.progress ?? service.currentProgress()).summary
        refreshLoginItemState()
    }
}
