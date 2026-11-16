import Darwin
import Foundation
import os
import UnrestorCore
import UnrestorDaemonCore

private let logger = Logger(subsystem: DaemonProtocol.label, category: "lifecycle")

guard geteuid() == 0 else {
    logger.critical("Refusing to run without root privileges.")
    exit(EX_NOPERM)
}

// The one user allowed to connect comes from the root-owned launchd job.
var allowedUID: uid_t?
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--allowed-uid"), index + 1 < arguments.count,
   let value = UInt32(arguments[index + 1]), value > 0 {
    allowedUID = uid_t(value)
}
guard let allowedUID else {
    logger.critical("Missing or invalid --allowed-uid.")
    exit(EX_CONFIG)
}

signal(SIGPIPE, SIG_IGN)

let stateDirectory = URL(fileURLWithPath: DaemonProtocol.stateDirectory, isDirectory: true)
do {
    try FileManager.default.createDirectory(
        at: stateDirectory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
} catch {
    logger.critical("Cannot create state directory: \(error.localizedDescription, privacy: .public)")
    exit(EX_CANTCREAT)
}

let pmsetControl = PMSetDaemonSleepControl()
let coordinator = DaemonHoldCoordinator(
    debtStore: FileDaemonSleepDebtStore(
        url: stateDirectory.appendingPathComponent("sleep-debt.json")),
    sleepControl: pmsetControl,
    powerModeDebtStore: FileDaemonPowerModeDebtStore(
        url: stateDirectory.appendingPathComponent("power-mode-debt.json")),
    powerModeControl: pmsetControl
)

switch coordinator.reconcileAtLaunch() {
case .clean: break
case .clearedAlreadyRestored, .restored:
    logger.notice("Restored the sleep setting recorded before the last exit.")
case .blocked(let message):
    // Keep serving. Every acquire retries reconciliation and refuses while it is blocked.
    logger.critical("Launch reconciliation blocked: \(message, privacy: .public)")
}
if case .blocked(let message) = coordinator.reconcilePowerModeAtLaunch() {
    logger.error("Energy mode restore at launch failed: \(message, privacy: .public)")
}

let power = IOKitPowerSource()
let server = SocketServer(path: DaemonProtocol.socketPath, allowedUID: allowedUID) {
    ConnectionHandler(coordinator: coordinator, readPower: { power.current() })
}
do {
    try server.start()
} catch {
    logger.critical("Cannot start the socket: \(String(describing: error), privacy: .public)")
    exit(EX_OSERR)
}

// On stop (launchctl bootout, shutdown) release every hold and restore settings
// before exiting, so a stop never leaves sleep disabled.
let stopSignals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler {
        logger.notice("Stopping: releasing holds.")
        server.stop()
        _ = coordinator.prepareForUpgrade()
        exit(0)
    }
    source.resume()
    return source
}
_ = stopSignals

let restoreRetryTimer = coordinator.startRestoreRetryTimer()
_ = restoreRetryTimer
logger.notice("Unrestor daemon \(UnrestorVersion.current, privacy: .public) ready for uid \(allowedUID).")
dispatchMain()
