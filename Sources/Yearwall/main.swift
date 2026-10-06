import AppKit
import WallpaperService

// `Yearwall --report` prints screen geometry and the wallpaper each screen
// currently shows, then exits. Used to document real behaviour (Spaces,
// multi-display) instead of assuming it.
if CommandLine.arguments.contains("--report") {
    _ = NSApplication.shared
    let store = ConfigStore()
    let service = WallpaperService(store: store)
    print("scheme: \(service.currentAppearance().rawValue)")
    for surface in ScreenSurveyor.surfaces() {
        print("screen: \(surface.description) tag=\(surface.tag)")
    }
    for entry in service.observedDesktopImages() {
        print("desktop image on display \(entry.display): \(entry.url?.path ?? "<none>")")
    }
    print("cache: \(service.cacheDirectory.path)")
    exit(0)
}

if CommandLine.arguments.contains("--preview") {
    exit(PreviewCommand.run(arguments: CommandLine.arguments))
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Belt and braces: the embedded Info.plist carries LSUIElement, but a bare
// `swift run` binary is not always treated as bundled.
application.setActivationPolicy(.accessory)
application.run()
