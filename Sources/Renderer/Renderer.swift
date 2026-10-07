import CoreGraphics
import Foundation
import ImageIO
import PatternEngine
import TimeModel
import UniformTypeIdentifiers

public enum RendererError: Error, CustomStringConvertible {
    case contextCreationFailed
    case imageCreationFailed
    case encodingFailed

    public var description: String {
        switch self {
        case .contextCreationFailed: return "Could not create the bitmap context"
        case .imageCreationFailed: return "Could not snapshot the bitmap context"
        case .encodingFailed: return "Could not encode the image as PNG"
        }
    }
}

public struct RenderResult: Sendable {
    public let url: URL
    public let byteCount: Int
    public let contentHash: String
    public let pixelWidth: Int
    public let pixelHeight: Int
}

/// Turns a `WallpaperConfig` + `CanvasSpec` into pixels, and pixels into a PNG.
///
/// A pure function of its arguments: it reads no `UserDefaults`, no `NSApp`,
/// no clock, no environment. The day seed comes from the config and the
/// progress, so the same three arguments always produce the same bytes.
public struct WallpaperRenderer: Sendable {
    public init() {}

    // MARK: - Pixels

    public func render(
        config: WallpaperConfig,
        progress: TimeModel.Progress,
        canvas: CanvasSpec,
        backdrop: CGImage? = nil
    ) throws -> CGImage {
        let composition = Composition(config: config, canvas: canvas)

        guard let context = CGContext(
            data: nil,
            width: canvas.pixelWidth,
            height: canvas.pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw RendererError.contextCreationFailed
        }

        // A bitmap context has its origin at the bottom left. Flip it once here
        // so `draw` can work in screen terms.
        context.translateBy(x: 0, y: CGFloat(canvas.pixelHeight))
        context.scaleBy(x: 1, y: -1)

        draw(config: config, progress: progress, composition: composition, backdrop: backdrop, into: context)

        guard let image = context.makeImage() else {
            throw RendererError.imageCreationFailed
        }
        return image
    }

    /// The one drawing path. The context must already be in screen
    /// orientation: origin top-left, y growing downward.
    ///
    /// `backdrop` replaces the background colour when the config's custom
    /// theme has one; it is passed in rather than read from disk to keep this
    /// a function of its arguments.
    public func draw(
        config: WallpaperConfig,
        progress: TimeModel.Progress,
        composition: Composition,
        backdrop: CGImage? = nil,
        into context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high

        // Background first: patterns draw marks, not backdrops.
        if config.activeBackdropName != nil, let backdrop {
            drawFilling(backdrop, composition.bounds, in: context)
        } else {
            context.setFill(composition.colors.background)
            context.fill(composition.bounds)
        }

        var rng = SeededRNG(seed: config.daySeed(dayKey: progress.dayKey))
        config.pattern().draw(progress: progress, composition: composition, rng: &rng, into: context)

        // Last, so it wins over anything a pattern drew up there.
        if let band = composition.menuBarBandRect {
            context.setFill(RGBA(0, 0, 0))
            context.fill(band)
        }
    }

    /// Scaled to cover `rect` and centred, cropping the overflow, like the
    /// system's "Fill Screen".
    private func drawFilling(_ image: CGImage, _ rect: CGRect, in context: CGContext) {
        let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.saveGState()
        context.clip(to: rect)
        // The context is flipped; CGImage draws bottom-up, so flip it back.
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }

    // MARK: - PNG

    public func pngData(
        config: WallpaperConfig,
        progress: TimeModel.Progress,
        canvas: CanvasSpec,
        backdrop: CGImage? = nil
    ) throws -> Data {
        try encodePNG(render(config: config, progress: progress, canvas: canvas, backdrop: backdrop))
    }

    public func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RendererError.encodingFailed
        }
        // No timestamps, no EXIF: keep the bytes a pure function of the pixels.
        let options: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: 0] as CFDictionary
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw RendererError.encodingFailed
        }
        return data as Data
    }

    // MARK: - Files

    /// Writes the PNG under `directory` with a name that is unique per day,
    /// per surface and per content.
    ///
    /// The unique name is not cosmetic: `NSWorkspace.setDesktopImageURL` caches
    /// by URL, so re-writing the same path leaves the desktop unchanged.
    @discardableResult
    public func renderPNG(
        config: WallpaperConfig,
        progress: TimeModel.Progress,
        canvas: CanvasSpec,
        backdrop: CGImage? = nil,
        tag: String,
        into directory: URL
    ) throws -> RenderResult {
        let data = try pngData(config: config, progress: progress, canvas: canvas, backdrop: backdrop)
        let hash = Seeds.hexString(Seeds.hash(bytes: data))
        let name = "yearwall-\(progress.dayKey)-\(tag)-\(hash).png"
        let url = directory.appendingPathComponent(name)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }

        return RenderResult(
            url: url,
            byteCount: data.count,
            contentHash: hash,
            pixelWidth: canvas.pixelWidth,
            pixelHeight: canvas.pixelHeight
        )
    }
}
