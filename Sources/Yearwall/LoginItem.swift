import Foundation
import ServiceManagement

/// "Launch at login", via `SMAppService`.
///
/// `SMAppService.mainApp` needs a real application bundle. A bare `swift run`
/// binary has none, so the menu item is shown disabled rather than failing at
/// the moment it is clicked.
enum LoginItem {
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static var unsupportedReason: String {
        "Launch at Login needs the app bundle — run Scripts/make-app.sh"
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        guard isSupported else {
            return .failure(NSError(
                domain: "Yearwall", code: 1,
                userInfo: [NSLocalizedDescriptionKey: unsupportedReason]
            ))
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
