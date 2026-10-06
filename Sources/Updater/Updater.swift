import AppKit
import CryptoKit
import Foundation

public enum UpdateError: LocalizedError {
    case badResponse(Int)
    case noArchive(String)
    case missingDigest
    case checksumMismatch
    case bundleMismatch(String)
    case notWritable(URL)
    case toolFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case let .badResponse(status): return "GitHub answered with HTTP \(status)"
        case let .noArchive(tag): return "Release \(tag) has no app archive"
        case .missingDigest: return "The archive has no SHA-256 digest to check against"
        case .checksumMismatch: return "The downloaded archive does not match its SHA-256 digest"
        case let .bundleMismatch(reason): return "The downloaded app is not this app: \(reason)"
        case let .notWritable(url): return "No permission to replace \(url.path)"
        case let .toolFailed(tool, status): return "\(tool) exited with status \(status)"
        }
    }
}

/// Checks the GitHub releases of this app once a day and, when a newer one is
/// out, downloads it, swaps the bundle on disk and relaunches.
///
/// Releases are ad-hoc signed, so the archive is trusted on HTTPS plus the
/// SHA-256 digest GitHub publishes for every asset. Only works from an app
/// bundle: a bare `swift run` binary has nothing to replace.
@MainActor
public final class Updater {
    public struct Configuration: Sendable {
        /// `owner/name` on GitHub.
        public let repository: String
        public let appName: String
        public let bundleIdentifier: String
        public let currentVersion: Version
        public let appURL: URL

        public init?(bundle: Bundle = .main) {
            guard
                bundle.bundleURL.pathExtension == "app",
                let repository = bundle.object(forInfoDictionaryKey: "YearwallUpdateRepository") as? String,
                !repository.isEmpty,
                let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                let bundleIdentifier = bundle.bundleIdentifier,
                let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                let currentVersion = Version(versionText)
            else { return nil }
            self.repository = repository
            self.appName = appName
            self.bundleIdentifier = bundleIdentifier
            self.currentVersion = currentVersion
            self.appURL = bundle.bundleURL
        }
    }

    public enum Outcome: Sendable {
        case upToDate(Version)
        /// A newer version is out but `canRelaunch` said not now.
        case postponed(Version)
        case installed(Version)
    }

    public static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"

    public let configuration: Configuration
    /// Asked right before relaunching. `false` leaves the install for the
    /// next check, an hour later.
    public var canRelaunch: () -> Bool = { true }

    private let defaults: UserDefaults
    private let log: (String) -> Void
    private var timer: Timer?
    private var isChecking = false

    public init(configuration: Configuration, defaults: UserDefaults = .standard, log: @escaping (String) -> Void) {
        self.configuration = configuration
        self.defaults = defaults
        self.log = log
    }

    // MARK: - Schedule

    /// Checks now if a day has passed since the last check, then looks again
    /// every hour, so a Mac that slept through the due time catches up soon
    /// after waking.
    public func start() {
        checkIfDue()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkIfDue() {
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        Task {
            do {
                try await check()
            } catch {
                log("update: check failed, \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Check

    @discardableResult
    public func check() async throws -> Outcome {
        guard !isChecking else { return .upToDate(configuration.currentVersion) }
        isChecking = true
        defer { isChecking = false }

        let release = try await latestRelease()
        guard let version = release.version, version > configuration.currentVersion else {
            defaults.set(Date(), forKey: Self.lastCheckKey)
            log("update: \(configuration.currentVersion) is current")
            return .upToDate(configuration.currentVersion)
        }
        guard canRelaunch() else {
            log("update: \(version) available, postponed")
            return .postponed(version)
        }

        log("update: installing \(version) over \(configuration.currentVersion)")
        try await install(release, version: version)
        defaults.set(Date(), forKey: Self.lastCheckKey)
        relaunch()
        return .installed(version)
    }

    private func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(configuration.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(configuration.appName)/\(configuration.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Install

    private func install(_ release: Release, version: Version) async throws {
        let appURL = configuration.appURL
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: appURL.deletingLastPathComponent().path),
              fm.isWritableFile(atPath: appURL.path)
        else { throw UpdateError.notWritable(appURL) }

        guard let asset = release.appArchive(named: configuration.appName) else {
            throw UpdateError.noArchive(release.tagName)
        }
        guard let expected = asset.sha256 else { throw UpdateError.missingDigest }

        // On the app's own volume, so the final swap is a rename.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        defer { try? fm.removeItem(at: work) }

        let (downloaded, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }
        let archive = work.appendingPathComponent(asset.name)
        try fm.moveItem(at: downloaded, to: archive)

        let digest = SHA256.hash(data: try Data(contentsOf: archive))
        guard digest.map({ String(format: "%02x", $0) }).joined() == expected else {
            throw UpdateError.checksumMismatch
        }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        try await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let newApp = unpacked.appendingPathComponent(appURL.lastPathComponent)
        try verify(newApp, version: version)
        try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

        _ = try fm.replaceItemAt(appURL, withItemAt: newApp)
    }

    private func verify(_ app: URL, version: Version) throws {
        guard let bundle = Bundle(url: app) else { throw UpdateError.bundleMismatch("no bundle in the archive") }
        guard bundle.bundleIdentifier == configuration.bundleIdentifier else {
            throw UpdateError.bundleMismatch("bundle identifier \(bundle.bundleIdentifier ?? "none")")
        }
        let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard Version(text) == version else {
            throw UpdateError.bundleMismatch("version \(text), release says \(version)")
        }
    }

    /// Waits for this process to exit, opens the new bundle, and quits.
    private func relaunch() {
        let script = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), configuration.appURL.path]
        do {
            try process.run()
        } catch {
            log("update: installed, but relaunch failed, \(error.localizedDescription)")
            return
        }
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.toolFailed(tool, process.terminationStatus))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
