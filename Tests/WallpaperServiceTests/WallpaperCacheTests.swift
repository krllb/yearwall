import XCTest
@testable import WallpaperService

final class WallpaperCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: WallpaperCache!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yearwall-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = WallpaperCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(
        day: String, tag: String = "d1-3840x2160-dark", hash: String = "0123456789abcdef", ext: String = "png"
    ) -> URL {
        let url = directory.appendingPathComponent("yearwall-\(day)-\(tag)-\(hash).\(ext)")
        FileManager.default.createFile(atPath: url.path, contents: Data("image".utf8))
        return url
    }

    private var fileNames: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.sorted() ?? []
    }

    func testOnlyTheWallpapersOnScreenSurvive() {
        // A day of fiddling with settings, yesterday, and the other appearance.
        for index in 0 ..< 5 {
            _ = write(day: "2026-03-04", hash: String(format: "%016x", index))
        }
        _ = write(day: "2026-03-03")
        _ = write(day: "2026-03-04", tag: "d1-3840x2160-light")
        let current = write(day: "2026-03-04", hash: "ffffffffffffffff", ext: "heic")

        let removed = cache.prune(keeping: [current])

        XCTAssertEqual(fileNames, [current.lastPathComponent])
        XCTAssertEqual(removed.count, 7)
    }

    func testEveryDisplayKeepsItsWallpaper() {
        let first = write(day: "2026-03-04", tag: "d1-3840x2160-dark")
        let second = write(day: "2026-03-04", tag: "d2-1920x1080-dark")
        _ = write(day: "2026-03-04", tag: "d2-1920x1080-dark", hash: "1111111111111111")
        cache.prune(keeping: [first, second])
        XCTAssertEqual(Set(fileNames), [first.lastPathComponent, second.lastPathComponent])
    }

    func testForeignFilesAreNeverTouched() {
        let foreign = directory.appendingPathComponent("holiday-photo.png")
        FileManager.default.createFile(atPath: foreign.path, contents: Data("x".utf8))
        _ = write(day: "2026-03-01")
        cache.prune(keeping: [])
        XCTAssertEqual(fileNames, ["holiday-photo.png"])
    }

    func testComponentParsing() {
        let parsed = WallpaperCache.components(
            ofFileName: "yearwall-2026-09-09-d1-4112x2658-dark-cc67be0d190f81b7.png"
        )
        XCTAssertEqual(parsed?.day, "2026-09-09")
        XCTAssertEqual(parsed?.surface, "d1-4112x2658-dark")
        XCTAssertNotNil(WallpaperCache.components(ofFileName: "yearwall-2026-09-09-d1-4112x2658-dark-cc67be0d190f81b7.heic"))
        XCTAssertNil(WallpaperCache.components(ofFileName: "yearwall-2026-09-09-d1-4112x2658-dark-cc67be0d190f81b7.jpg"))
        XCTAssertNil(WallpaperCache.components(ofFileName: "IMG_1234.png"))
        XCTAssertNil(WallpaperCache.components(ofFileName: "yearwall-bogus.png"))
    }
}
