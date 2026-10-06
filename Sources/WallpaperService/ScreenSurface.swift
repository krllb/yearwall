import AppKit
import PatternEngine

/// One display, described in the terms the renderer needs.
public struct ScreenSurface: Sendable, Equatable {
    public let displayID: CGDirectDisplayID
    /// True panel pixels, not points.
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Pixels per point for this display's current mode.
    public let scale: Double
    /// Height of the menu bar on this screen, in points. 0 when it has none.
    public let menuBarPoints: Double
    /// Thickness of the Dock on this screen, in points. 0 when it is elsewhere
    /// or hidden.
    public let dockPoints: Double
    /// Stable-enough identifier for file names.
    public let tag: String

    public var description: String {
        "display \(displayID): \(pixelWidth)x\(pixelHeight)px @\(String(format: "%.2f", scale))x"
            + ", menu bar \(String(format: "%.0f", menuBarPoints))pt"
            + ", dock \(String(format: "%.0f", dockPoints))pt"
    }
}

public enum ScreenSurveyor {
    /// Reads the geometry of every attached screen.
    ///
    /// `NSScreen.frame` is in points; `CGDisplayMode.pixelWidth/pixelHeight`
    /// give the panel's real pixels, which is what a wallpaper should match.
    /// On a scaled HiDPI mode those two disagree (e.g. 2560x1440pt shown on a
    /// 3840x2160 panel), so the scale is derived rather than taken from
    /// `backingScaleFactor`.
    @MainActor
    public static func surfaces() -> [ScreenSurface] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let points = screen.frame.size

            var pixelWidth = Int(points.width * screen.backingScaleFactor)
            var pixelHeight = Int(points.height * screen.backingScaleFactor)
            if let mode = CGDisplayCopyDisplayMode(displayID), mode.pixelWidth > 0, mode.pixelHeight > 0 {
                pixelWidth = mode.pixelWidth
                pixelHeight = mode.pixelHeight
            }

            let scale = points.width > 0 ? Double(pixelWidth) / Double(points.width) : Double(screen.backingScaleFactor)

            // AppKit's y grows upward, so the menu bar is the strip missing
            // from the top of visibleFrame and the Dock the one missing from
            // the bottom. Measuring beats guessing: the bar is 24pt on most
            // Macs and about 37pt on a notched one.
            let visible = screen.visibleFrame
            let menuBar = max(0, Double(screen.frame.maxY - visible.maxY))
            let dock = max(0, Double(visible.minY - screen.frame.minY))

            return ScreenSurface(
                displayID: displayID,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: scale,
                menuBarPoints: menuBar,
                dockPoints: dock,
                tag: "d\(displayID)-\(pixelWidth)x\(pixelHeight)"
            )
        }
    }
}
