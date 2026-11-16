import Foundation
import UnrestorDaemonCore

enum DaemonFailure: LocalizedError {
    case unsignedApp
    case invalidEmbeddedDaemon(String)
    case unreachable(String)
    case staleBuild
    case incompatible(String)
    case refused(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsignedApp: "Unrestor's Apple signature could not be read."
        case .invalidEmbeddedDaemon(let m): "The embedded daemon could not be verified: \(m)"
        case .unreachable(let m): "The background service is not running: \(m)"
        case .staleBuild: "The background service is from an older version."
        case .incompatible(let m): "The background service is incompatible: \(m)"
        case .refused(let m): m
        case .timedOut: "The background service did not answer in time."
        }
    }
}

/// A mutually authenticated client for the privileged daemon. It creates an
/// XPC connection only; it never creates or queries an `SMAppService`.
///
/// The daemon ties every hold to this connection. If the app quits, crashes,
/// or the connection drops, the daemon releases the hold on its own.
final class DaemonConnection: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NSXPCConnection
    private let expectedBuild: UnrestorDaemonBuildIdentity
    private var compatible = false

    /// Called when the daemon connection is lost. Any hold is already released.
    var onLost: (@Sendable () -> Void)?

    init() throws {
        let appIdentity: RuntimeSigningIdentity
        do {
            appIdentity = try RuntimeSigningIdentity.validatedCurrent()
        } catch {
            throw DaemonFailure.unsignedApp
        }
        let daemonIdentity = RuntimeSigningIdentity(
            identifier: appIdentity.identifier + ".daemon",
            teamIdentifier: appIdentity.teamIdentifier
        )
        guard daemonIdentity.appClientIdentity() == appIdentity else {
            throw DaemonFailure.invalidEmbeddedDaemon("identifier mismatch")
        }

        let daemonURL = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/LaunchServices/UnrestorDaemon", isDirectory: false)
        let embedded: RuntimeSignedCodeIdentity
        do {
            embedded = try RuntimeSigningIdentity.validatedCode(executableURL: daemonURL)
        } catch {
            throw DaemonFailure.invalidEmbeddedDaemon(error.localizedDescription)
        }
        guard embedded.signingIdentity.identifier == daemonIdentity.identifier,
              embedded.signingIdentity.teamIdentifier == daemonIdentity.teamIdentifier,
              let build = UnrestorDaemonBuildIdentity(
                marketingVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                buildVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleVersion") as? String,
                codeDirectoryHash: embedded.codeDirectoryHash)
        else {
            throw DaemonFailure.invalidEmbeddedDaemon(
                "identifier, Team ID, version, or code hash does not match the app")
        }
        expectedBuild = build

        let connection = NSXPCConnection(
            machServiceName: daemonIdentity.identifier, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: UnrestorDaemonXPCProtocol.self)
        // The daemon must prove it is the exact Apple-signed daemon of this team.
        connection.setCodeSigningRequirement(daemonIdentity.codeSigningRequirement)
        self.connection = connection
        connection.interruptionHandler = { [weak self] in self?.lost() }
        connection.invalidationHandler = { [weak self] in self?.lost() }
    }

    func connect(timeout: TimeInterval = 5) async throws {
        connection.resume()
        try await withTimeout(timeout) { [self] finish in
            guard let proxy = proxy(onError: { finish(.failure(DaemonFailure.unreachable($0.localizedDescription))) })
            else { return finish(.failure(DaemonFailure.unreachable("invalid XPC interface"))) }
            proxy.daemonHandshake { proto, marketing, build, hash, ready, message in
                let result = UnrestorDaemonHandshakeCompatibility.evaluate(
                    expectedBuild: self.expectedBuild,
                    receivedProtocol: proto,
                    receivedMarketingVersion: marketing,
                    receivedBuildVersion: build,
                    receivedCodeDirectoryHash: hash,
                    reconciliationReady: ready,
                    reconciliationMessage: message)
                switch result {
                case .compatible: finish(.success(()))
                case .staleBuild: finish(.failure(DaemonFailure.staleBuild))
                case .reconciliationBlocked(let m): finish(.failure(DaemonFailure.incompatible(m)))
                case .incompatibleProtocol(let e, let r):
                    finish(.failure(DaemonFailure.incompatible("protocol v\(r), expected v\(e)")))
                case .legacyOrUnidentified:
                    finish(.failure(DaemonFailure.incompatible("it does not identify its build")))
                }
            }
        }
        setCompatible(true)
    }

    func setHold(_ enabled: Bool) async throws {
        try requireCompatible()
        try await withTimeout(5) { [self] finish in
            guard let proxy = proxy(onError: { finish(.failure(DaemonFailure.unreachable($0.localizedDescription))) })
            else { return finish(.failure(DaemonFailure.unreachable("invalid XPC interface"))) }
            proxy.setLidClosedHold(enabled) { ok, message in
                finish(ok ? .success(()) : .failure(DaemonFailure.refused(message ?? "The daemon refused the hold.")))
            }
        }
    }

    func setLowPowerMode(_ enabled: Bool) async throws {
        try requireCompatible()
        try await withTimeout(5) { [self] finish in
            guard let proxy = proxy(onError: { finish(.failure(DaemonFailure.unreachable($0.localizedDescription))) })
            else { return finish(.failure(DaemonFailure.unreachable("invalid XPC interface"))) }
            proxy.setLowPowerModeHold(enabled) { ok, message, _ in
                finish(ok ? .success(()) : .failure(DaemonFailure.refused(message ?? "The daemon refused Low Power Mode.")))
            }
        }
    }

    func invalidate() {
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
    }

    // MARK: - Plumbing

    private func proxy(onError: @escaping @Sendable (Error) -> Void) -> UnrestorDaemonXPCProtocol? {
        connection.remoteObjectProxyWithErrorHandler(onError) as? UnrestorDaemonXPCProtocol
    }

    private func lost() {
        setCompatible(false)
        onLost?()
    }

    private func requireCompatible() throws {
        lock.lock(); defer { lock.unlock() }
        guard compatible else { throw DaemonFailure.unreachable("not connected") }
    }

    private func setCompatible(_ value: Bool) {
        lock.lock(); compatible = value; lock.unlock()
    }

    /// Runs an XPC call, finishing exactly once: on its reply, its error, or
    /// the timeout, whichever comes first.
    private func withTimeout(
        _ seconds: TimeInterval,
        _ body: @escaping @Sendable (@escaping @Sendable (Result<Void, Error>) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            let finish: @Sendable (Result<Void, Error>) -> Void = { result in
                once.run { continuation.resume(with: result) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + max(0.1, seconds)) {
                finish(.failure(DaemonFailure.timedOut))
            }
            body(finish)
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ work: () -> Void) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        work()
    }
}
