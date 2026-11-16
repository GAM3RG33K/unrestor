import Testing
@testable import UnrestorCore

@Test func commandsRoundTrip() {
    let commands: [DaemonCommand] = [
        .hello, .release,
        .hold(batteryFloor: 25, onlyOnPower: true, lowPower: false),
        .hold(batteryFloor: 10, onlyOnPower: false, lowPower: true),
    ]
    for command in commands { #expect(DaemonCommand.parse(command.line) == command) }
}

@Test func holdDefaultsApplyWhenFieldsAreMissing() {
    #expect(DaemonCommand.parse("HOLD") == .hold(batteryFloor: 20, onlyOnPower: false, lowPower: false))
}

@Test func repliesRoundTrip() {
    let replies: [DaemonReply] = [
        .hello(version: "0.1.0"), .held,
        .released(reason: "Mac is running hot, so it can sleep"), .error("nope"),
    ]
    for reply in replies { #expect(DaemonReply.parse(reply.line) == reply) }
}

@Test func garbageDoesNotParse() {
    #expect(DaemonCommand.parse("rm -rf /") == nil)
    #expect(DaemonCommand.parse("HOLD floor=1 floor") == nil)
    #expect(DaemonReply.parse("???") == nil)
}

@Test func settingsClampTheFloorToTheHardMinimum() {
    var settings = Settings()
    settings.batteryFloor = 0
    #expect(settings.clamped().batteryFloor == DaemonProtocol.hardMinimumBatteryFloor)
    settings.batteryFloor = 500
    #expect(settings.clamped().batteryFloor == 100)
    settings.batteryFloor = 35
    #expect(settings.clamped().batteryFloor == 35)
}

@Test func launchdJobPinsTheProgramAndTheAllowedUser() {
    let plist = LaunchDaemonPlist.render(daemonPath: "/Library/PrivilegedHelperTools/app.unrestor.daemon", allowedUID: 501)
    #expect(plist.contains("<string>app.unrestor.daemon</string>"))
    #expect(plist.contains("<string>--allowed-uid</string>"))
    #expect(plist.contains("<string>501</string>"))
    #expect(plist.contains("<key>KeepAlive</key>"))
    #expect(LaunchDaemonPlist.render(daemonPath: "/a&b<c>", allowedUID: 1).contains("/a&amp;b&lt;c&gt;"))
}
