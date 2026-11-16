import Darwin
import Foundation
import Testing
import UnrestorCore
@testable import UnrestorDaemonCore

private final class MemoryDebt: DaemonSleepDebtStoring {
    var state: DaemonSleepDebtState = .none
    func load() -> DaemonSleepDebtState { state }
    func save(_ debt: DaemonSleepDebt) -> Bool { state = .valid(debt); return true }
    func remove() -> Bool { state = .none; return true }
}

private final class MemorySleep: DaemonSleepSettingControlling {
    var live = false
    func readDisabled() -> Bool? { live }
    func writeDisabled(_ disabled: Bool) -> Bool { live = disabled; return true }
}

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000)
}

private final class PowerBox: @unchecked Sendable {
    var state = PowerState(onBattery: false, batteryPercent: 100, thermal: .nominal)
}

private struct Rig: @unchecked Sendable {
    let sleep = MemorySleep()
    let clock = Clock()
    let power = PowerBox()
    let coordinator: DaemonHoldCoordinator

    init() {
        coordinator = DaemonHoldCoordinator(debtStore: MemoryDebt(), sleepControl: sleep)
    }

    func handler() -> ConnectionHandler {
        ConnectionHandler(
            coordinator: coordinator,
            readPower: { [power] in power.state },
            now: { [clock] in clock.date }
        )
    }
}

private let hold = "HOLD floor=20 power-only=0 low-power=0"

@Test func helloReportsTheVersion() {
    let reply = Rig().handler().handle(line: "HELLO 1")
    #expect(reply == .hello(version: UnrestorVersion.current))
}

@Test func holdDisablesSleepAndReleaseRestoresIt() {
    let rig = Rig()
    let handler = rig.handler()
    #expect(handler.handle(line: hold) == .held)
    #expect(rig.sleep.live)
    #expect(rig.coordinator.holdCount == 1)
    #expect(handler.handle(line: "RELEASE") == .released(reason: "released on request"))
    #expect(!rig.sleep.live)
    #expect(rig.coordinator.holdCount == 0)
}

@Test func closingTheConnectionReleasesTheHold() {
    let rig = Rig()
    let handler = rig.handler()
    _ = handler.handle(line: hold)
    handler.close()
    #expect(!rig.sleep.live)
}

@Test func unknownAndMalformedCommandsAreRefusedWithoutEffect() {
    let rig = Rig()
    let handler = rig.handler()
    for line in ["", "PMSET -a disablesleep 1", "HOLD floor=abc", "HOLD bogus=1", "HOLD floor"] {
        #expect(handler.handle(line: line) == .error("unknown command"), "\(line)")
    }
    #expect(!rig.sleep.live)
}

@Test func lowBatteryReleasesAnExistingHold() {
    let rig = Rig()
    let handler = rig.handler()
    _ = handler.handle(line: hold)
    rig.power.state = PowerState(onBattery: true, batteryPercent: 15, thermal: .nominal)
    let reply = handler.handle(line: hold)
    #expect(reply == .released(reason: "Battery below 20%, so the Mac can sleep"))
    #expect(!rig.sleep.live)
}

@Test func aClientCannotLowerTheFloorBelowTheDaemonMinimum() {
    let rig = Rig()
    let handler = rig.handler()
    rig.power.state = PowerState(onBattery: true, batteryPercent: 7, thermal: .nominal)
    let reply = handler.handle(line: "HOLD floor=0 power-only=0 low-power=0")
    #expect(reply == .released(reason: "Battery below 10%, so the Mac can sleep"))
    #expect(!rig.sleep.live)
}

@Test func heatAndUnreadablePowerAlwaysRelease() {
    let rig = Rig()
    let handler = rig.handler()
    rig.power.state = PowerState(onBattery: false, batteryPercent: 100, thermal: .serious)
    #expect(handler.handle(line: "HOLD floor=0 power-only=0 low-power=0")
        == .released(reason: "Mac is running hot, so it can sleep"))
    rig.power.state = PowerState(onBattery: false, batteryPercent: 100, thermal: .nominal, trusted: false)
    if case .released = handler.handle(line: hold) {} else { Issue.record("should release") }
    #expect(!rig.sleep.live)
}

@Test func powerOnlyReleasesOnBattery() {
    let rig = Rig()
    let handler = rig.handler()
    rig.power.state = PowerState(onBattery: true, batteryPercent: 90, thermal: .nominal)
    #expect(handler.handle(line: "HOLD floor=20 power-only=1 low-power=0")
        == .released(reason: "On battery, and you chose power-only"))
}

@Test func aSilentClientIsReleasedWhenItsLeaseExpires() {
    let rig = Rig()
    let handler = rig.handler()
    _ = handler.handle(line: hold)
    rig.clock.date += DaemonProtocol.leaseSeconds - 1
    #expect(!handler.expireLeaseIfNeeded())
    #expect(rig.sleep.live)
    rig.clock.date += 2
    #expect(handler.expireLeaseIfNeeded())
    #expect(!rig.sleep.live)
}

@Test func heartbeatsRenewTheLease() {
    let rig = Rig()
    let handler = rig.handler()
    _ = handler.handle(line: hold)
    for _ in 0..<5 {
        rig.clock.date += DaemonProtocol.leaseSeconds - 1
        _ = handler.handle(line: hold)
        #expect(!handler.expireLeaseIfNeeded())
    }
    #expect(rig.sleep.live)
}

@Test func twoClientsHoldTogetherAndTheLastReleaseRestores() {
    let rig = Rig()
    let a = rig.handler(), b = rig.handler()
    _ = a.handle(line: hold); _ = b.handle(line: hold)
    a.close()
    #expect(rig.sleep.live)
    b.close()
    #expect(!rig.sleep.live)
}

// MARK: - Over a real socket

private func shortSocketPath() -> String { "/tmp/unrestor-t-\(UUID().uuidString.prefix(8)).sock" }

@Test func hardLimitsAndCleanupWorkOverARealSocket() throws {
    let rig = Rig()
    let path = shortSocketPath()
    let server = SocketServer(path: path, allowedUID: getuid()) { rig.handler() }
    try server.start()
    defer { server.stop() }

    var info = stat()
    #expect(stat(path, &info) == 0)
    #expect(info.st_mode & 0o777 == 0o600)

    let client = DaemonClient(path: path)
    try client.connect()
    #expect(try client.send(.hello) == .hello(version: UnrestorVersion.current))
    #expect(try client.send(.hold(batteryFloor: 20, onlyOnPower: false, lowPower: false)) == .held)
    #expect(rig.sleep.live)

    rig.power.state = PowerState(onBattery: true, batteryPercent: 5, thermal: .nominal)
    if case .released = try client.send(.hold(batteryFloor: 0, onlyOnPower: false, lowPower: false)) {}
    else { Issue.record("expected a release at 5%") }
    #expect(!rig.sleep.live)

    rig.power.state = PowerState(onBattery: false, batteryPercent: 100, thermal: .nominal)
    #expect(try client.send(.hold(batteryFloor: 20, onlyOnPower: false, lowPower: false)) == .held)
    #expect(rig.sleep.live)
    client.close()                                   // app quits or crashes
    for _ in 0..<100 where rig.sleep.live { usleep(20_000) }
    #expect(!rig.sleep.live)                         // the daemon released on its own
}

@Test func aMissingDaemonIsReportedAsNotRunning() {
    let client = DaemonClient(path: shortSocketPath())
    #expect(throws: DaemonClientError.notRunning) { try client.connect() }
}

@Test func stoppingTheServerReleasesEveryHold() throws {
    let rig = Rig()
    let path = shortSocketPath()
    let server = SocketServer(path: path, allowedUID: getuid()) { rig.handler() }
    try server.start()
    let client = DaemonClient(path: path)
    try client.connect()
    _ = try client.send(.hold(batteryFloor: 20, onlyOnPower: false, lowPower: false))
    #expect(rig.sleep.live)
    server.stop()
    #expect(!rig.sleep.live)
    #expect(access(path, F_OK) != 0)
}
