import Foundation
import UnrestorCore

/// One client connection's state: whether it holds, and when it last renewed.
/// Pure of sockets so it can be tested directly.
///
/// Every `HOLD` is a heartbeat and re-checks the safety limits, using the
/// daemon's own power reading and a clamped copy of the client's settings.
/// A client that stops renewing is released after the lease expires, and a
/// closed connection releases immediately.
public final class ConnectionHandler: @unchecked Sendable {
    public let id = UUID()
    private let coordinator: DaemonHoldCoordinator
    private let readPower: () -> PowerState
    private let now: () -> Date
    private var holding = false
    private var lowPowerOn = false
    private var lastRenewal: Date?

    public init(
        coordinator: DaemonHoldCoordinator,
        readPower: @escaping () -> PowerState,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.readPower = readPower
        self.now = now
    }

    public func handle(line: String) -> DaemonReply {
        guard let command = DaemonCommand.parse(line) else {
            return .error("unknown command")
        }
        switch command {
        case .hello:
            return .hello(version: UnrestorVersion.current)
        case .release:
            releaseAll()
            return .released(reason: "released on request")
        case .hold(let floor, let onlyOnPower, let lowPower):
            return hold(floor: floor, onlyOnPower: onlyOnPower, lowPower: lowPower)
        }
    }

    /// Called periodically. Returns true when the lease expired and the hold
    /// was released, so the caller can close the connection.
    @discardableResult
    public func expireLeaseIfNeeded() -> Bool {
        guard holding, let last = lastRenewal,
              now().timeIntervalSince(last) > DaemonProtocol.leaseSeconds
        else { return false }
        releaseAll()
        return true
    }

    /// Connection closed for any reason.
    public func close() {
        releaseAll()
    }

    private func hold(floor: Int, onlyOnPower: Bool, lowPower: Bool) -> DaemonReply {
        var settings = Settings()
        settings.batteryFloor = floor
        settings.onlyWhileConnectedToPower = onlyOnPower
        if let release = HoldPolicy.safetyRelease(settings: settings.clamped(), power: readPower()) {
            releaseAll()
            return .released(reason: release.reason)
        }
        switch coordinator.setHold(true, for: id) {
        case .failed(let message):
            return .error(message)
        case .applied:
            holding = true
            lastRenewal = now()
        }
        // Low Power Mode is a nicety nested in the hold. Failing to switch it
        // never blocks or releases the hold.
        if lowPower != lowPowerOn {
            if case .applied = coordinator.setLowPowerMode(lowPower, for: id) {
                lowPowerOn = lowPower
            }
        }
        return .held
    }

    private func releaseAll() {
        if lowPowerOn {
            _ = coordinator.setLowPowerMode(false, for: id)
            lowPowerOn = false
        }
        if holding {
            _ = coordinator.setHold(false, for: id)
            holding = false
        }
        lastRenewal = nil
    }
}
