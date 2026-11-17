import Foundation
import Testing
@testable import UnrestorCore

// MARK: Versions

@Test func versionsParseAndCompareNumerically() {
    #expect(AppVersion("0.1.0") == AppVersion(0, 1, 0))
    #expect(AppVersion("v1.2.3") == AppVersion(1, 2, 3))
    #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
    #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
    #expect(!(AppVersion("0.1.0")! > AppVersion("0.1.0")!))
    #expect(AppVersion("0.1.0")!.description == "0.1.0")
}

@Test func nonFinalOrMalformedVersionsAreRejected() {
    for bad in ["", "1", "1.2", "1.2.3.4", "1.2.3-beta", "v", "a.b.c", "1..3", "1.2.-3", "1.2.3 "+"x"] {
        #expect(AppVersion(bad) == nil, "\(bad)")
    }
}

// MARK: Feed

private func releaseJSON(
    tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false,
    assets: [(String, String)]? = nil
) -> Data {
    let defaults = [
        ("Unrestor-0.2.0.dmg", "https://github.com/GAM3RG33K/unrestor/releases/download/v0.2.0/Unrestor-0.2.0.dmg"),
        ("Unrestor-0.2.0.dmg.sha256", "https://github.com/GAM3RG33K/unrestor/releases/download/v0.2.0/Unrestor-0.2.0.dmg.sha256"),
    ]
    let list = (assets ?? defaults).map {
        "{\"name\":\"\($0.0)\",\"browser_download_url\":\"\($0.1)\",\"size\":1234}"
    }.joined(separator: ",")
    return Data("""
    {"tag_name":"\(tag)","html_url":"https://github.com/GAM3RG33K/unrestor/releases/tag/\(tag)",
     "draft":\(draft),"prerelease":\(prerelease),"assets":[\(list)]}
    """.utf8)
}

@Test func aNormalReleaseParses() throws {
    let info = try #require(ReleaseFeed.parse(releaseJSON()))
    #expect(info.version == AppVersion(0, 2, 0))
    #expect(info.dmgURL.lastPathComponent == "Unrestor-0.2.0.dmg")
    #expect(info.checksumURL.lastPathComponent == "Unrestor-0.2.0.dmg.sha256")
    #expect(info.dmgSize == 1234)
}

@Test func unusableReleasesAreIgnored() {
    #expect(ReleaseFeed.parse(releaseJSON(draft: true)) == nil)
    #expect(ReleaseFeed.parse(releaseJSON(prerelease: true)) == nil)
    #expect(ReleaseFeed.parse(releaseJSON(tag: "nightly")) == nil)
    #expect(ReleaseFeed.parse(releaseJSON(assets: [])) == nil)
    #expect(ReleaseFeed.parse(Data("not json".utf8)) == nil)
    // A DMG with no checksum next to it is not installable.
    #expect(ReleaseFeed.parse(releaseJSON(assets: [
        ("Unrestor-0.2.0.dmg", "https://github.com/x/y/releases/download/v0.2.0/Unrestor-0.2.0.dmg")])) == nil)
}

@Test func downloadsMustComeFromGitHubOverHTTPS() {
    let evil = [
        ("Unrestor-0.2.0.dmg", "https://evil.example/Unrestor-0.2.0.dmg"),
        ("Unrestor-0.2.0.dmg.sha256", "https://evil.example/Unrestor-0.2.0.dmg.sha256"),
    ]
    #expect(ReleaseFeed.parse(releaseJSON(assets: evil)) == nil)
    let http = [
        ("Unrestor-0.2.0.dmg", "http://github.com/a/b/Unrestor-0.2.0.dmg"),
        ("Unrestor-0.2.0.dmg.sha256", "http://github.com/a/b/Unrestor-0.2.0.dmg.sha256"),
    ]
    #expect(ReleaseFeed.parse(releaseJSON(assets: http)) == nil)
    #expect(UpdateURLPolicy.isAllowed(URL(string: "https://objects.githubusercontent.com/x")!))
    #expect(!UpdateURLPolicy.isAllowed(URL(string: "https://github.com.evil.example/x")!))
    #expect(!UpdateURLPolicy.isAllowed(URL(string: "https://notgithubusercontent.com/x")!))
}

@Test func checksumsParseFromShasumOutput() {
    let hash = String(repeating: "ab", count: 32)
    #expect(ReleaseFeed.parseChecksum("\(hash)  Unrestor-0.2.0.dmg\n") == hash)
    #expect(ReleaseFeed.parseChecksum(hash.uppercased()) == hash)
    #expect(ReleaseFeed.parseChecksum("short") == nil)
    #expect(ReleaseFeed.parseChecksum(String(repeating: "zz", count: 32)) == nil)
    #expect(ReleaseFeed.parseChecksum("") == nil)
}

@Test func fileHashMatchesTheKnownVector() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString)")
    try Data("abc".utf8).write(to: url)
    #expect(try FileHash.sha256(of: url)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

// MARK: The swap script, run for real against temp folders

private struct SwapRig {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("unrestor-swap-\(UUID().uuidString)", isDirectory: true)
    var new: String { dir.appendingPathComponent("new.app").path }
    var target: String { dir.appendingPathComponent("Unrestor.app").path }
    var backup: String { dir.appendingPathComponent("Unrestor.app.old").path }
    var marker: String { dir.appendingPathComponent("relaunched").path }

    init() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: new, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: target, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: URL(fileURLWithPath: new + "/version"))
        try Data("old".utf8).write(to: URL(fileURLWithPath: target + "/version"))
        // A "relaunch" command that just records its argument.
        let relaunch = dir.appendingPathComponent("relaunch.sh")
        try Data("#!/bin/sh\necho \"$1\" > '\(marker)'\n".utf8).write(to: relaunch)
        chmod(relaunch.path, 0o755)
    }

    var relaunchPath: String { dir.appendingPathComponent("relaunch.sh").path }

    func run(pid: Int32) throws -> Int32 {
        let script = dir.appendingPathComponent("swap.sh")
        try Data(UpdateScript.text.utf8).write(to: script)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, String(pid), new, target, backup, relaunchPath]
        try p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }
}

private func deadPID() throws -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try p.run(); p.waitUntilExit()
    return p.processIdentifier
}

@Test func theSwapReplacesTheAppAndRelaunchesIt() throws {
    let rig = try SwapRig()
    #expect(try rig.run(pid: deadPID()) == 0)
    #expect(rig.read(rig.target + "/version") == "new")
    #expect(!FileManager.default.fileExists(atPath: rig.backup))
    #expect(!FileManager.default.fileExists(atPath: rig.new))
    #expect(rig.read(rig.marker)?.trimmingCharacters(in: .whitespacesAndNewlines) == rig.target)
}

@Test func aFailedCopyRestoresTheOldApp() throws {
    let rig = try SwapRig()
    try FileManager.default.removeItem(atPath: rig.new)         // nothing to copy
    #expect(try rig.run(pid: deadPID()) == 1)
    #expect(rig.read(rig.target + "/version") == "old")
    #expect(!FileManager.default.fileExists(atPath: rig.backup))
}

@Test func theSwapNeverTouchesAnAppThatDoesNotQuit() throws {
    let rig = try SwapRig()
    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["60"]
    try sleeper.run()
    defer { sleeper.terminate() }
    // Shorten the wait by running the script with a pid that stays alive: it
    // must give up and leave everything as it was.
    let script = rig.dir.appendingPathComponent("swap.sh")
    try Data(UpdateScript.text.replacingOccurrences(of: "-lt 100", with: "-lt 3").utf8).write(to: script)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = [script.path, String(sleeper.processIdentifier), rig.new, rig.target, rig.backup, rig.relaunchPath]
    try p.run(); p.waitUntilExit()
    #expect(p.terminationStatus == 1)
    #expect(rig.read(rig.target + "/version") == "old")
}

@Test func settingsFromOlderFilesKeepNewDefaults() throws {
    let old = Data("{\"batteryFloor\":30,\"onlyWhileConnectedToPower\":true,\"lowPowerWhileHeld\":false}".utf8)
    let settings = try JSONDecoder().decode(Settings.self, from: old)
    #expect(settings.batteryFloor == 30)
    #expect(settings.onlyWhileConnectedToPower)
    #expect(settings.checkForUpdates)               // default on, and can be turned off
}

// MARK: - Install source and the Homebrew update script

@Test func aHomebrewInstallIsDetectedOnEitherPrefix() {
    let apple = Set(["/opt/homebrew/Caskroom/unrestor", "/opt/homebrew/bin/brew"])
    #expect(InstallSource.detect(fileExists: apple.contains) == .homebrew(brewPath: "/opt/homebrew/bin/brew"))
    let intel = Set(["/usr/local/Caskroom/unrestor", "/usr/local/bin/brew"])
    #expect(InstallSource.detect(fileExists: intel.contains) == .homebrew(brewPath: "/usr/local/bin/brew"))
}

@Test func withoutBothHomebrewMarkersTheInstallIsDirect() {
    #expect(InstallSource.detect(fileExists: { _ in false }) == .direct)
    // A leftover Caskroom folder with no brew, or brew without the cask, is not Homebrew.
    #expect(InstallSource.detect(fileExists: { $0 == "/opt/homebrew/Caskroom/unrestor" }) == .direct)
    #expect(InstallSource.detect(fileExists: { $0 == "/opt/homebrew/bin/brew" }) == .direct)
}

@Test func theBrewScriptUpdatesThenRestartsTheService() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("unrestor-brew-test-\(UUID().uuidString)")
    let bin = dir.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("calls.log")

    func fake(_ name: String) throws {
        let url = bin.appendingPathComponent(name)
        try Data("#!/bin/sh\necho \"\(name) $*\" >> '\(log.path)'\n".utf8).write(to: url)
        chmod(url.path, 0o755)
    }
    try fake("brew"); try fake("unrestor"); try fake("sudo")
    // sudo runs the program it is given, as the real one does.
    try Data("#!/bin/sh\necho \"sudo $*\" >> '\(log.path)'\n\"$@\"\n".utf8)
        .write(to: bin.appendingPathComponent("sudo"))

    let script = dir.appendingPathComponent("update.sh")
    try Data(BrewUpdateScript.text.utf8).write(to: script)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path, bin.appendingPathComponent("brew").path, "9.9.9"]
    process.environment = ["PATH": "\(bin.path):/usr/bin:/bin"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    #expect(calls == [
        "brew update",
        "brew upgrade --cask GAM3RG33K/tap/unrestor",
        "sudo \(bin.path)/unrestor install",
        "unrestor install",
    ])
    #expect(!FileManager.default.fileExists(atPath: script.path), "the script removes itself")
}

@Test func theBrewScriptSkipsTheServiceWhenTheUpgradeFails() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("unrestor-brew-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let brew = dir.appendingPathComponent("brew")
    try Data("#!/bin/sh\nexit 1\n".utf8).write(to: brew)
    chmod(brew.path, 0o755)
    let script = dir.appendingPathComponent("update.sh")
    try Data(BrewUpdateScript.text.utf8).write(to: script)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path, brew.path, "9.9.9"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    #expect(process.terminationStatus == 1)
}
