import Foundation
import Testing
@testable import UnrestorCore

private let request = HoldRequest(id: "a", label: "build")
private let plugged = PowerState(onBattery: false, batteryPercent: 100, thermal: .nominal)

@Test func holdsWhenRequestedAndPowerIsFine() {
    let decision = HoldPolicy.decide(active: [request], settings: Settings(), power: plugged)
    #expect(decision.hold)
    #expect(decision.reason == "Awake for build")
}

@Test func releasesWithNoRequests() {
    #expect(!HoldPolicy.decide(active: [], settings: Settings(), power: plugged).hold)
}

@Test func releasesBelowBatteryFloorOnBatteryOnly() {
    var settings = Settings()
    settings.batteryFloor = 30
    let low = PowerState(onBattery: true, batteryPercent: 29, thermal: .nominal)
    let enough = PowerState(onBattery: true, batteryPercent: 30, thermal: .nominal)
    let chargingLow = PowerState(onBattery: false, batteryPercent: 5, thermal: .nominal)
    #expect(!HoldPolicy.decide(active: [request], settings: settings, power: low).hold)
    #expect(HoldPolicy.decide(active: [request], settings: settings, power: enough).hold)
    #expect(HoldPolicy.decide(active: [request], settings: settings, power: chargingLow).hold)
}

@Test func releasesOnBatteryWhenPowerOnly() {
    var settings = Settings()
    settings.onlyWhileConnectedToPower = true
    let battery = PowerState(onBattery: true, batteryPercent: 90, thermal: .nominal)
    #expect(!HoldPolicy.decide(active: [request], settings: settings, power: battery).hold)
    #expect(HoldPolicy.decide(active: [request], settings: settings, power: plugged).hold)
}

@Test func releasesWhenHotAndWhenPowerReadingIsUntrusted() {
    let hot = PowerState(onBattery: false, batteryPercent: 100, thermal: .serious)
    let blind = PowerState(onBattery: false, batteryPercent: 100, thermal: .nominal, trusted: false)
    #expect(!HoldPolicy.decide(active: [request], settings: Settings(), power: hot).hold)
    #expect(!HoldPolicy.decide(active: [request], settings: Settings(), power: blind).hold)
    let fair = PowerState(onBattery: false, batteryPercent: 100, thermal: .fair)
    #expect(HoldPolicy.decide(active: [request], settings: Settings(), power: fair).hold)
}

@Test func describesMultipleRequests() {
    let other = HoldRequest(id: "b", label: "test")
    let decision = HoldPolicy.decide(active: [request, other], settings: Settings(), power: plugged)
    #expect(decision.reason == "Awake for build and 1 more")
}
