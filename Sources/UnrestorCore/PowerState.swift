import Foundation

/// A reading of battery and thermal state for the hold policy.
public struct PowerState: Equatable, Sendable {
    public var onBattery: Bool
    public var batteryPercent: Int
    public var thermal: ProcessInfo.ThermalState
    public var lowPowerModeEnabled: Bool
    /// False means the reading itself could not be trusted: an IOKit call
    /// failed outright. This is not the same as "this Mac has no battery",
    /// which is a trustworthy, plugged-in reading. The policy refuses to hold
    /// on an untrusted reading rather than bypass the battery floor.
    public var trusted: Bool

    public init(
        onBattery: Bool,
        batteryPercent: Int,
        thermal: ProcessInfo.ThermalState,
        lowPowerModeEnabled: Bool = false,
        trusted: Bool = true
    ) {
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.thermal = thermal
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.trusted = trusted
    }
}
