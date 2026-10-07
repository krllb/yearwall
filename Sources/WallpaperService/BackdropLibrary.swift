import CoreGraphics
import Foundation
import ImageIO
import PatternEngine

/// Pictures a custom theme draws over.
///
/// A chosen file is copied in under a name made from its content hash, so the
/// wallpaper survives the original being moved or deleted, and the config
/// only ever stores that name.
public struct BackdropLibrary: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Yearwall/Backdrops", isDirectory: true)
    }

    /// Copies `source` in and returns the name to store in the config.
    public func importImage(from source: URL) throws -> String {
        let data = try Data(contentsOf: source)
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0
        else { throw CocoaError(.fileReadCorruptFile) }

        let ext = source.pathExtension.isEmpty ? "img" : source.pathExtension.lowercased()
        let name = Seeds.hexString(Seeds.hash(bytes: data)) + "." + ext
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: .atomic)
        }
        return name
    }

    /// Decoded now rather than on first draw, upright whatever its EXIF
    /// orientation, and no larger than it takes to cover every one of
    /// `canvases`: a 6000px photo held at full size would cost a menu bar app
    /// well over 100 MB.
    public func image(named name: String, covering canvases: [CGSize]) -> CGImage? {
        let url = directory.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }

        // Orientations 5 to 8 turn the picture on its side.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let size = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        let cover = canvases.map { max($0.width / size.width, $0.height / size.height) }.max() ?? 1
        let longest = (max(size.width, size.height) * min(cover, 1)).rounded(.up)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(longest, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Deletes every stored picture except `keeping`.
    public func prune(keeping name: String?) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for other in names where other != name {
            try? fm.removeItem(at: directory.appendingPathComponent(other))
        }
    }
}
