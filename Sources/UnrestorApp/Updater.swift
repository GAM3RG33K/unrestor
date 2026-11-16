import AppKit
import Foundation
import Observation
import UnrestorCore

/// Checks GitHub for a newer release, downloads it, verifies it, and swaps it
/// in. Nothing is sent about you or your Mac: the request is a plain read of the
/// public "latest release" page of this project.
///
/// Trust, stated plainly: the DMG is fetched over HTTPS from github.com and
/// checked against the SHA-256 published beside it. That catches a corrupt or
/// truncated download, not a compromised GitHub account. The app is ad-hoc
/// signed, so there is no developer signature to pin.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case verifying
        case installing
        case failed(String, ReleaseInfo?)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    let current = AppVersion(UnrestorVersion.current) ?? AppVersion(0, 0, 0)
    private var timer: Timer?

    /// An update can replace the app only when it runs from an installed
    /// Unrestor.app whose folder we may write to.
    var canInstallInPlace: Bool {
        let bundle = Bundle.main.bundleURL
        return bundle.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .verifying, .installing: true
        default: false
        }
    }

    // MARK: Checking

    /// Looks again once a day while the app runs, and shortly after launch.
    func startAutomaticChecks(enabled: @escaping @MainActor () -> Bool) {
        guard timer == nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if enabled() { await check(quiet: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3_600, repeats: true) { _ in
            Task { @MainActor in
                if enabled(), !self.isBusy { await self.check(quiet: true) }
            }
        }
    }

    /// `quiet` is for the automatic checks: a failure (offline, rate limited)
    /// is silent instead of showing a problem the person did not ask about.
    func check(quiet: Bool = false) async {
        guard !isBusy else { return }
        state = .checking
        do {
            let (data, response) = try await Self.session.data(for: Self.request(UnrestorLinks.latestReleaseAPI), delegate: RedirectGuard())
            lastChecked = Date()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.message("GitHub answered with an error. Try again later.")
            }
            guard let release = ReleaseFeed.parse(data) else {
                // No usable release (none published, or no DMG yet): nothing to offer.
                state = .upToDate
                return
            }
            state = release.version > current ? .available(release) : .upToDate
        } catch {
            state = quiet ? .idle : .failed(Self.describe(error), nil)
        }
    }

    // MARK: Installing

    func install() async {
        guard case .available(let release) = state else { return }
        guard canInstallInPlace else {
            NSWorkspace.shared.open(release.pageURL)
            state = .failed("Unrestor is not in a folder it can update. Download the new version from the release page.", release)
            return
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("unrestor-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            state = .downloading
            let dmg = work.appendingPathComponent("Unrestor-\(release.version).dmg")
            let (downloaded, response) = try await Self.session.download(for: Self.request(release.dmgURL), delegate: RedirectGuard())
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError.message("The download failed. Try again later.")
            }
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            state = .verifying
            let (sumData, sumResponse) = try await Self.session.data(for: Self.request(release.checksumURL), delegate: RedirectGuard())
            guard (sumResponse as? HTTPURLResponse)?.statusCode == 200, sumData.count < 1_024,
                  let expected = ReleaseFeed.parseChecksum(String(decoding: sumData, as: UTF8.self))
            else { throw UpdateError.message("The release has no valid checksum, so it was not installed.") }
            let actual = try await Task.detached { try FileHash.sha256(of: dmg) }.value
            guard actual == expected else {
                throw UpdateError.message("The download did not match its checksum, so it was not installed.")
            }

            let staged = try await Self.extractApp(from: dmg, into: work, expected: release.version)

            state = .installing
            try Self.launchSwap(staged: staged, work: work)
            NSApplication.shared.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .failed(Self.describe(error), release)
        }
    }

    func openReleasePage() {
        var url = UnrestorLinks.releasesPage
        switch state {
        case .available(let release), .failed(_, .some(let release)): url = release.pageURL
        default: break
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: Steps

    /// Mounts the DMG, copies the app out, and checks it is what the release claims.
    private static func extractApp(from dmg: URL, into work: URL, expected: AppVersion) async throws -> URL {
        let mounts = work.appendingPathComponent("mounts", isDirectory: true)
        try FileManager.default.createDirectory(at: mounts, withIntermediateDirectories: true)

        let attach = try await run("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-readonly", "-noverify", "-plist",
            "-mountrandom", mounts.path, dmg.path])
        guard attach.status == 0, let mountPoint = mountPoint(fromPlist: attach.output) else {
            throw UpdateError.message("The download could not be opened.")
        }
        defer { Task.detached { _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint, "-force", "-quiet"]) } }

        let source = URL(fileURLWithPath: mountPoint).appendingPathComponent("Unrestor.app")
        let staged = work.appendingPathComponent("Unrestor.app")
        let copy = try await run("/usr/bin/ditto", [source.path, staged.path])
        guard copy.status == 0 else { throw UpdateError.message("The new app could not be copied.") }

        guard let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == "app.unrestor",
              info["CFBundleShortVersionString"] as? String == expected.description,
              FileManager.default.isExecutableFile(
                atPath: staged.appendingPathComponent("Contents/MacOS/Unrestor").path),
              FileManager.default.isExecutableFile(
                atPath: staged.appendingPathComponent("Contents/Helpers/unrestor").path),
              FileManager.default.isExecutableFile(
                atPath: staged.appendingPathComponent("Contents/Helpers/unrestor-daemon").path)
        else { throw UpdateError.message("The download is not the Unrestor \(expected) app, so it was not installed.") }

        let verify = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        guard verify.status == 0 else {
            throw UpdateError.message("The new app's signature is damaged, so it was not installed.")
        }
        return staged
    }

    /// Starts the swap script detached. It waits for this process to exit, so
    /// the running app is never replaced underneath itself.
    private static func launchSwap(staged: URL, work: URL) throws {
        let target = Bundle.main.bundleURL
        let script = work.appendingPathComponent("swap.sh")
        try Data(UpdateScript.text.utf8).write(to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path, String(getpid()), staged.path, target.path,
            target.path + ".old", "/usr/bin/open",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: Plumbing

    private enum UpdateError: Error { case message(String) }

    /// GitHub redirects release downloads to its CDN. Follow only redirects that
    /// stay inside the same HTTPS allowlist as the original URL.
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url, UpdateURLPolicy.isAllowed(url) else { return nil }
            return request
        }
    }

    private static func describe(_ error: Error) -> String {
        if case UpdateError.message(let text) = error { return text }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You are offline." }
        return error.localizedDescription
    }

    /// An ephemeral session: no cookies, no cache, nothing kept between checks.
    private static let session = URLSession(configuration: {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 600
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpShouldSetCookies = false
        return c
    }())

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Unrestor", forHTTPHeaderField: "User-Agent")   // no version, no identifiers
        return request
    }

    private static func mountPoint(fromPlist data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    private static func run(_ path: String, _ arguments: [String]) async throws -> (status: Int32, output: Data) {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }.value
    }
}
