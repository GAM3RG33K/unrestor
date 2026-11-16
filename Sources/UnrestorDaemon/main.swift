import Darwin
import Foundation
import os
import UnrestorDaemonCore

private let logger = Logger(
    subsystem: "app.unrestor.daemon",
    category: "lifecycle"
)

private final class DaemonClientSession: NSObject, UnrestorDaemonXPCProtocol {
    private let id = UUID()
    private let coordinator: DaemonHoldCoordinator
    private let buildIdentity: UnrestorDaemonBuildIdentity
    private let logger: Logger

    init(
        coordinator: DaemonHoldCoordinator,
        buildIdentity: UnrestorDaemonBuildIdentity,
        logger: Logger
    ) {
        self.coordinator = coordinator
        self.buildIdentity = buildIdentity
        self.logger = logger
    }

    func protocolVersion(withReply reply: @escaping (Int) -> Void) {
        reply(UnrestorDaemonProtocolVersion.current)
    }

    func daemonHandshake(
        withReply reply: @escaping (
            Int, String?, String?, String?, Bool, String?
        ) -> Void
    ) {
        let readiness = coordinator.reconciliationReadiness().reply
        reply(
            UnrestorDaemonProtocolVersion.current,
            buildIdentity.marketingVersion,
            buildIdentity.buildVersion,
            buildIdentity.codeDirectoryHash,
            readiness.ready,
            readiness.message
        )
    }

    func prepareForUpgrade(
        withReply reply: @escaping (Bool, String?, Int) -> Void
    ) {
        let result = coordinator.prepareForUpgrade().reply
        if !result.succeeded, let message = result.message {
            logger.error("Daemon upgrade preparation failed: \(message, privacy: .public)")
        }
        reply(result.succeeded, result.message, result.baseline)
    }

    func setLidClosedHold(
        _ enabled: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        let result = coordinator.setHold(enabled, for: id)
        let response = result.reply
        if case .failed(let message) = result {
            logger.error("Lid-closed hold request failed: \(message, privacy: .public)")
        }
        reply(response.succeeded, response.message)
    }

    func setLowPowerModeHold(
        _ enabled: Bool,
        withReply reply: @escaping (Bool, String?, Int) -> Void
    ) {
        let result = coordinator.setLowPowerMode(enabled, for: id)
        if case .failed(let message) = result {
            logger.error("Low Power Mode request failed: \(message, privacy: .public)")
        }
        let response = result.reply
        reply(response.succeeded, response.message, response.personalSources)
    }

    func invalidate() {
        let result = coordinator.connectionInvalidated(id)
        if case .failed(let message) = result {
            logger.error("Disconnect restore failed: \(message, privacy: .public)")
        }
    }

    deinit {
        invalidate()
    }
}

private final class DaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let coordinator: DaemonHoldCoordinator
    private let buildIdentity: UnrestorDaemonBuildIdentity
    private let clientRequirement: String
    private let logger: Logger

    init(
        coordinator: DaemonHoldCoordinator,
        buildIdentity: UnrestorDaemonBuildIdentity,
        clientRequirement: String,
        logger: Logger
    ) {
        self.coordinator = coordinator
        self.buildIdentity = buildIdentity
        self.clientRequirement = clientRequirement
        self.logger = logger
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let session = DaemonClientSession(
            coordinator: coordinator,
            buildIdentity: buildIdentity,
            logger: logger
        )
        connection.exportedInterface = NSXPCInterface(
            with: UnrestorDaemonXPCProtocol.self
        )
        connection.exportedObject = session

        // Enforced by Foundation for every incoming message. Both the Team ID
        // and app identifier are derived from this daemon's live Apple-issued
        // signature, so development and production cannot impersonate one
        // another and no identity is trusted merely because it was hardcoded.
        connection.setCodeSigningRequirement(clientRequirement)
        connection.invalidationHandler = { [weak session] in
            session?.invalidate()
        }
        connection.resume()
        return true
    }
}

guard geteuid() == 0 else {
    logger.critical("Refusing to run without root privileges.")
    exit(EX_NOPERM)
}

let daemonCodeIdentity: RuntimeSignedCodeIdentity
do {
    daemonCodeIdentity = try RuntimeSigningIdentity.validatedCurrentCode()
} catch {
    logger.critical("Could not read the daemon signature: \(error.localizedDescription, privacy: .public)")
    exit(EX_CONFIG)
}
let daemonIdentity = daemonCodeIdentity.signingIdentity
guard let appIdentity = daemonIdentity.appClientIdentity() else {
    logger.critical("Could not derive the app identity from \(daemonIdentity.identifier, privacy: .public).")
    exit(EX_CONFIG)
}
guard let daemonBuildIdentity = UnrestorDaemonBuildIdentity(
    marketingVersion: daemonCodeIdentity.marketingVersion,
    buildVersion: daemonCodeIdentity.buildVersion,
    codeDirectoryHash: daemonCodeIdentity.codeDirectoryHash
) else {
    logger.critical("Could not derive the exact daemon build identity.")
    exit(EX_CONFIG)
}

let stateDirectory = URL(
    fileURLWithPath: "/Library/Application Support/Unrestor",
    isDirectory: true
)
let debtURL = stateDirectory.appendingPathComponent(
    "\(daemonIdentity.identifier).sleep-debt.json",
    isDirectory: false
)
let powerModeDebtURL = stateDirectory.appendingPathComponent(
    "\(daemonIdentity.identifier).power-mode-debt.json",
    isDirectory: false
)
let pmsetControl = PMSetDaemonSleepControl()
let coordinator = DaemonHoldCoordinator(
    debtStore: FileDaemonSleepDebtStore(url: debtURL),
    sleepControl: pmsetControl,
    powerModeDebtStore: FileDaemonPowerModeDebtStore(url: powerModeDebtURL),
    powerModeControl: pmsetControl
)

switch coordinator.reconcileAtLaunch() {
case .clean:
    logger.notice("No disablesleep restore was pending at launch.")
case .clearedAlreadyRestored(let priorValue):
    logger.notice("Cleared completed restore record for disablesleep=\(priorValue ? 1 : 0).")
case .restored(let priorValue):
    logger.notice("Restored disablesleep=\(priorValue ? 1 : 0) at launch.")
case .blocked(let message):
    // Keep serving the XPC endpoint so clients get an actionable error.
    // Every acquire retries reconciliation; this never silently accepts a
    // hold while an earlier restore remains unresolved.
    logger.critical("Launch reconciliation blocked: \(message, privacy: .public)")
}

switch coordinator.reconcilePowerModeAtLaunch() {
case .clean:
    break
case .clearedAlreadyRestored:
    logger.notice("Cleared a completed energy mode restore record at launch.")
case .restored:
    logger.notice("Restored the recorded energy mode at launch.")
case .blocked(let message):
    // Never blocks closed-lid holds; the next handshake or release retries.
    logger.error("Energy mode restore at launch failed: \(message, privacy: .public)")
}

private let delegate = DaemonListenerDelegate(
    coordinator: coordinator,
    buildIdentity: daemonBuildIdentity,
    clientRequirement: appIdentity.codeSigningRequirement,
    logger: logger
)
let listener = NSXPCListener(machServiceName: daemonIdentity.identifier)
listener.delegate = delegate
listener.resume()
let restoreRetryTimer = coordinator.startRestoreRetryTimer()
logger.notice(
    "Unrestor daemon protocol v\(UnrestorDaemonProtocolVersion.current) build \(daemonBuildIdentity.versionDescription, privacy: .public) cdhash \(daemonBuildIdentity.codeDirectoryHash, privacy: .public) ready."
)
RunLoop.current.run()
