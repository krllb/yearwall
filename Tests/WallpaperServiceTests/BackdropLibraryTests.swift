import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WallpaperService

final class BackdropLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackdropLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A `width`×`height` JPEG, optionally tagged with an EXIF orientation.
    private func writePicture(width: Int, height: Int, orientation: Int = 1) throws -> URL {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = directory.appendingPathComponent("source-\(orientation).jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testImportNamesTheCopyByContent() throws {
        let library = BackdropLibrary(directory: directory.appendingPathComponent("store"))
        let source = try writePicture(width: 40, height: 20)
        let name = try library.importImage(from: source)
        XCTAssertEqual(name, try library.importImage(from: source), "same bytes, same name")
        XCTAssertTrue(name.hasSuffix(".jpg"))
        try FileManager.default.removeItem(at: source)
        XCTAssertNotNil(library.image(named: name, covering: [CGSize(width: 40, height: 20)]), "survives the original")
    }

    func testDecodesOnlyAsLargeAsTheScreenNeeds() throws {
        let library = BackdropLibrary(directory: directory)
        let name = try library.importImage(from: try writePicture(width: 3000, height: 3000))
        let image = try XCTUnwrap(library.image(named: name, covering: [CGSize(width: 1200, height: 800)]))
        XCTAssertEqual(image.width, 1200, "covers the wider side, square picture")
        XCTAssertEqual(image.height, 1200)
    }

    func testNeverUpscales() throws {
        let library = BackdropLibrary(directory: directory)
        let name = try library.importImage(from: try writePicture(width: 300, height: 200))
        let image = try XCTUnwrap(library.image(named: name, covering: [CGSize(width: 3000, height: 2000)]))
        XCTAssertEqual(image.width, 300)
    }

    func testHonoursExifOrientation() throws {
        let library = BackdropLibrary(directory: directory)
        // Stored landscape, tagged "rotate 90°": shown portrait.
        let name = try library.importImage(from: try writePicture(width: 400, height: 200, orientation: 6))
        let image = try XCTUnwrap(library.image(named: name, covering: [CGSize(width: 400, height: 400)]))
        XCTAssertLessThan(image.width, image.height)
    }

    func testPruneKeepsOnlyTheCurrentPicture() throws {
        let library = BackdropLibrary(directory: directory.appendingPathComponent("store"))
        let first = try library.importImage(from: try writePicture(width: 10, height: 10))
        let second = try library.importImage(from: try writePicture(width: 20, height: 10, orientation: 3))
        library.prune(keeping: second)
        let left = try FileManager.default.contentsOfDirectory(atPath: library.directory.path)
        XCTAssertEqual(left, [second])
        XCTAssertNotEqual(first, second)
    }
}
