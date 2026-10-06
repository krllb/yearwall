import XCTest
@testable import Updater

final class ReleaseTests: XCTestCase {
    func testVersionParsing() {
        XCTAssertEqual(Version("v1.2.3")?.parts, [1, 2, 3])
        XCTAssertEqual(Version("0.10")?.parts, [0, 10])
        XCTAssertEqual(Version("v2.0.0-beta.1")?.parts, [2, 0, 0])
        XCTAssertNil(Version("latest"))
        XCTAssertNil(Version("1..2"))
        XCTAssertNil(Version(""))
    }

    func testVersionOrderingIsNumeric() throws {
        let order = ["0.1.0", "0.1.1", "0.2", "0.10.0", "1.0.0"].compactMap(Version.init)
        XCTAssertEqual(order, order.sorted())
        XCTAssertEqual(Version("1.0"), Version("1.0.0"))
        XCTAssertFalse(try XCTUnwrap(Version("1.0.0")) > XCTUnwrap(Version("v1.0")))
    }

    func testDecodesGitHubRelease() throws {
        let json = """
        {
          "tag_name": "v0.2.0", "draft": false, "prerelease": false, "name": "ignored",
          "assets": [
            {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt", "digest": null},
            {"name": "Yearwall-0.2.0.zip", "browser_download_url": "https://example.com/Yearwall-0.2.0.zip",
             "digest": "sha256:ABCDEF0123"}
          ]
        }
        """
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, Version("0.2.0"))
        let archive = try XCTUnwrap(release.appArchive(named: "Yearwall"))
        XCTAssertEqual(archive.name, "Yearwall-0.2.0.zip")
        XCTAssertEqual(archive.sha256, "abcdef0123")
        XCTAssertNil(release.appArchive(named: "Other"))
    }

    func testDigestWithoutSHA256PrefixIsIgnored() throws {
        let json = #"{"name": "Yearwall-1.zip", "browser_download_url": "https://example.com/a", "digest": "md5:00"}"#
        let asset = try JSONDecoder().decode(Release.Asset.self, from: Data(json.utf8))
        XCTAssertNil(asset.sha256)
    }
}
