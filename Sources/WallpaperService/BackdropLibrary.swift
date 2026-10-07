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

    public func image(named name: String) -> CGImage? {
        let url = directory.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
