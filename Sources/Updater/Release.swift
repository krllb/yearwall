import Foundation

/// `1.2.3`, compared numerically. A leading `v` and anything after a `-` are
/// ignored, so `v1.2.3-beta` reads as `1.2.3`.
public struct Version: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        var core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        if core.hasPrefix("v") { core.removeFirst() }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0 ..< count {
            let a = index < lhs.parts.count ? lhs.parts[index] : 0
            let b = index < rhs.parts.count ? rhs.parts[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The parts of a GitHub release the updater reads.
public struct Release: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browserDownloadURL: URL
        /// `sha256:<hex>`, filled in by GitHub for every uploaded asset.
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }

        public var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            return String(digest.dropFirst("sha256:".count)).lowercased()
        }
    }

    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }

    public var version: Version? { Version(tagName) }

    /// The zipped app bundle, named `<app>-<version>.zip` by the release workflow.
    public func appArchive(named appName: String) -> Asset? {
        assets.first { $0.name.hasPrefix(appName + "-") && $0.name.hasSuffix(".zip") }
    }
}
