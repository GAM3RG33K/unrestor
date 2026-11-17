import Foundation

public enum UnrestorVersion {
    public static let current = "0.1.6"
}

/// Paths and limits shared by the CLI, the app, and the root daemon.
public enum DaemonProtocol {
    public static let version = 1
    public static let label = "app.unrestor.daemon"

    /// Created by the daemon, owned by the installing user, mode 0600.
    public static let socketPath = "/var/run/unrestor.sock"
    /// Root-owned and not writable by the admin group, unlike /Library/Application Support.
    public static let installedDaemonPath = "/Library/PrivilegedHelperTools/app.unrestor.daemon"
    public static let plistPath = "/Library/LaunchDaemons/app.unrestor.daemon.plist"
    /// Root-only. Holds the record needed to restore sleep settings after a crash.
    public static let stateDirectory = "/var/db/unrestor"

    /// A hold the client has not renewed within this many seconds is released.
    /// Clients renew every second, so a hung or killed app cannot strand a hold.
    public static let leaseSeconds: TimeInterval = 10

    /// The daemon never honors a battery floor below this, whatever a client asks.
    public static let hardMinimumBatteryFloor = 10
}

/// What a client may ask of the daemon. One line of text each.
public enum DaemonCommand: Equatable, Sendable {
    case hello
    /// Ask to hold, with the client's limits. Sent about once a second as a
    /// heartbeat; each one re-checks the safety limits.
    case hold(batteryFloor: Int, onlyOnPower: Bool, lowPower: Bool)
    case release

    public var line: String {
        switch self {
        case .hello: "HELLO \(DaemonProtocol.version)"
        case .hold(let floor, let power, let low):
            "HOLD floor=\(floor) power-only=\(power ? 1 : 0) low-power=\(low ? 1 : 0)"
        case .release: "RELEASE"
        }
    }

    public static func parse(_ line: String) -> DaemonCommand? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let verb = parts.first else { return nil }
        switch verb {
        case "HELLO":
            return .hello
        case "RELEASE":
            return .release
        case "HOLD":
            var floor = 20, power = false, low = false
            for field in parts.dropFirst() {
                let pair = field.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                switch pair[0] {
                case "floor": guard let v = Int(pair[1]) else { return nil }; floor = v
                case "power-only": power = pair[1] == "1"
                case "low-power": low = pair[1] == "1"
                default: return nil
                }
            }
            return .hold(batteryFloor: floor, onlyOnPower: power, lowPower: low)
        default:
            return nil
        }
    }
}

public enum DaemonReply: Equatable, Sendable {
    case hello(version: String)
    case held
    case released(reason: String)
    case error(String)

    public var line: String {
        switch self {
        case .hello(let version): "OK unrestor \(version)"
        case .held: "HELD"
        case .released(let reason): "RELEASED \(reason)"
        case .error(let message): "ERR \(message)"
        }
    }

    public static func parse(_ line: String) -> DaemonReply? {
        if line == "HELD" { return .held }
        if line.hasPrefix("OK unrestor ") { return .hello(version: String(line.dropFirst(12))) }
        if line.hasPrefix("RELEASED ") { return .released(reason: String(line.dropFirst(9))) }
        if line == "RELEASED" { return .released(reason: "") }
        if line.hasPrefix("ERR ") { return .error(String(line.dropFirst(4))) }
        return nil
    }
}
