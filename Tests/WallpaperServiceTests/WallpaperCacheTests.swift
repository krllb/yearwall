import XCTest
@testable import WallpaperService

final class WallpaperCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yearwall-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(day: String, tag: String = "d1-3840x2160-dark", hash: String = "0123456789abcdef") -> URL {
        let url = directory.appendingPathComponent("yearwall-\(day)-\(tag)-\(hash).png")
        FileManager.default.createFile(atPath: url.path, contents: Data("png".utf8))
        return url
    }

    private var fileNames: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.sorted() ?? []
    }

    func testTenSimulatedDayChangesLeaveAtMostSevenFiles() {
        let cache = WallpaperCache(directory: directory, retainedDays: 7)
        for day in 1 ... 10 {
            _ = write(day: String(format: "2026-03-%02d", day))
            cache.prune()
        }
        XCTAssertLessThanOrEqual(fileNames.count, 7)
        XCTAssertEqual(fileNames.count, 7)
        XCTAssertTrue(fileNames.allSatisfy { $0.contains("2026-03-0") || $0.contains("2026-03-1") })
        XCTAssertFalse(fileNames.contains { $0.contains("2026-03-01") })
        XCTAssertTrue(fileNames.contains { $0.contains("2026-03-10") })
    }

    func testRetentionCountsDaysNotFiles() {
        // Two displays and two appearances mean four files a day; seven days
        // of those must all survive.
        let cache = WallpaperCache(directory: directory, retainedDays: 7)
        for day in 1 ... 9 {
            let key = String(format: "2026-03-%02d", day)
            for tag in ["d1-3840x2160-dark", "d1-3840x2160-light", "d2-1920x1080-dark", "d2-1920x1080-light"] {
                _ = write(day: key, tag: tag)
            }
            cache.prune()
        }
        let days = Set(fileNames.compactMap { WallpaperCache.dayKey(fromFileName: $0) })
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(fileNames.count, 28)
    }

    func testProtectedFilesSurviveEvenIfOld() {
        let cache = WallpaperCache(directory: directory, retainedDays: 2)
        let ancient = write(day: "2020-01-01")
        _ = write(day: "2026-03-01")
        _ = write(day: "2026-03-02")
        cache.prune(keeping: [ancient])
        XCTAssertTrue(FileManager.default.fileExists(atPath: ancient.path))
    }

    func testForeignFilesAreNeverTouched() {
        let cache = WallpaperCache(directory: directory, retainedDays: 1)
        let foreign = directory.appendingPathComponent("holiday-photo.png")
        FileManager.default.createFile(atPath: foreign.path, contents: Data("x".utf8))
        _ = write(day: "2026-03-01")
        _ = write(day: "2026-03-02")
        cache.prune()
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    func testDayKeyParsing() {
        XCTAssertEqual(
            WallpaperCache.dayKey(fromFileName: "yearwall-2026-09-09-d1-4112x2658-dark-cc67be0d190f81b7.png"),
            "2026-09-09"
        )
        XCTAssertNil(WallpaperCache.dayKey(fromFileName: "IMG_1234.png"))
        XCTAssertNil(WallpaperCache.dayKey(fromFileName: "yearwall-bogus.png"))
    }
}

extension WallpaperCacheTests {
    func testSupersededRendersOfTheSameDayAreDropped() throws {
        let cache = WallpaperCache(directory: directory, retainedDays: 7)
        // A day of fiddling with the palette picker.
        for index in 0 ..< 5 {
            let url = write(day: "2026-03-04", hash: String(format: "%016x", index))
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(Double(index))], ofItemAtPath: url.path
            )
        }
        cache.prune()
        XCTAssertEqual(fileNames.count, 1)
        XCTAssertTrue(fileNames[0].hasSuffix("0000000000000004.png"))
    }

    func testSurfacesAreKeptApart() throws {
        let cache = WallpaperCache(directory: directory, retainedDays: 7)
        _ = write(day: "2026-03-04", tag: "d1-3840x2160-dark")
        _ = write(day: "2026-03-04", tag: "d1-3840x2160-light")
        _ = write(day: "2026-03-04", tag: "d2-1920x1080-dark")
        cache.prune()
        XCTAssertEqual(fileNames.count, 3)
    }

    func testComponentParsing() {
        let parsed = WallpaperCache.components(
            ofFileName: "yearwall-2026-09-09-d1-4112x2658-dark-cc67be0d190f81b7.png"
        )
        XCTAssertEqual(parsed?.day, "2026-09-09")
        XCTAssertEqual(parsed?.surface, "d1-4112x2658-dark")
    }
}
