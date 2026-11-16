import Foundation

public struct Settings: Codable, Equatable, Sendable {
    /// Release below this charge, on battery only.
    public var batteryFloor: Int = 20
    public var onlyWhileConnectedToPower = false
    /// Run in Low Power Mode while the hold is on, to save battery and heat.
    public var lowPowerWhileHeld = false
    /// Ask GitHub once a day whether a newer release exists. Sends nothing about
    /// you or your Mac; turn it off here and the app never contacts the network.
    public var checkForUpdates = true

    public init() {}

    // Older settings files lack newer keys; missing ones keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        batteryFloor = try c.decodeIfPresent(Int.self, forKey: .batteryFloor) ?? d.batteryFloor
        onlyWhileConnectedToPower = try c.decodeIfPresent(Bool.self, forKey: .onlyWhileConnectedToPower) ?? d.onlyWhileConnectedToPower
        lowPowerWhileHeld = try c.decodeIfPresent(Bool.self, forKey: .lowPowerWhileHeld) ?? d.lowPowerWhileHeld
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? d.checkForUpdates
    }

    /// What the daemon will actually honor: it never accepts a floor below its
    /// hard minimum, so a client cannot talk it out of protecting the battery.
    public func clamped() -> Settings {
        var copy = self
        copy.batteryFloor = min(100, max(DaemonProtocol.hardMinimumBatteryFloor, batteryFloor))
        return copy
    }
}

public struct HoldDecision: Equatable, Sendable {
    public var hold: Bool
    /// Shown in the menu and by `unrestor status`.
    public var reason: String

    public init(hold: Bool, reason: String) {
        self.hold = hold
        self.reason = reason
    }
}

/// Decides whether the Mac should be held awake. Pure: no I/O, no clock.
/// Safety limits always win over a request: a hot or nearly flat Mac sleeps.
public enum HoldPolicy {
    public static func decide(
        active requests: [HoldRequest],
        settings: Settings,
        power: PowerState
    ) -> HoldDecision {
        guard !requests.isEmpty else {
            return HoldDecision(hold: false, reason: "Nothing is asking to stay awake")
        }
        if let release = safetyRelease(settings: settings, power: power) { return release }
        return HoldDecision(hold: true, reason: describe(requests))
    }

    /// The limits that end a hold no matter who asked for it. The daemon applies
    /// this to every heartbeat, so they hold even against a misbehaving client.
    public static func safetyRelease(settings: Settings, power: PowerState) -> HoldDecision? {
        guard power.trusted else {
            return HoldDecision(hold: false, reason: "Battery state unreadable, so the Mac can sleep")
        }
        switch power.thermal {
        case .serious, .critical:
            return HoldDecision(hold: false, reason: "Mac is running hot, so it can sleep")
        default:
            break
        }
        if settings.onlyWhileConnectedToPower, power.onBattery {
            return HoldDecision(hold: false, reason: "On battery, and you chose power-only")
        }
        if power.onBattery, power.batteryPercent < settings.batteryFloor {
            return HoldDecision(
                hold: false,
                reason: "Battery below \(settings.batteryFloor)%, so the Mac can sleep"
            )
        }
        return nil
    }

    /// When the hold will end on its own, if every request has a time limit:
    /// the latest of them. Nil when any request is open-ended (a manual hold
    /// without a timer, or a command that ends when it ends) or none exist.
    public static func holdEndsAt(_ requests: [HoldRequest]) -> Date? {
        guard !requests.isEmpty else { return nil }
        let ends = requests.map(\.expiresAt)
        guard !ends.contains(where: { $0 == nil }) else { return nil }
        return ends.compactMap { $0 }.max()
    }

    static func describe(_ requests: [HoldRequest]) -> String {
        guard let first = requests.first else { return "" }
        if requests.count == 1 { return "Awake for \(first.label)" }
        return "Awake for \(first.label) and \(requests.count - 1) more"
    }
}
