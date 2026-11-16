import Darwin
import Foundation
import UnrestorCore

private func say(_ text: String) { print(text) }

private func requireRoot(_ what: String) {
    guard geteuid() == 0 else {
        fail("\(what) needs administrator rights. Run: sudo unrestor \(what)")
    }
}

@discardableResult
private func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (127, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines))
}

/// A directory root can trust: not writable by group or others. The daemon runs
/// as root, so it must never be loaded from a place anyone else can edit.
private func isRootOnlyWritable(_ path: String) -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
    return info.st_uid == 0 && (info.st_mode & 0o022) == 0
}

private func locateDaemonBinary() -> URL? {
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
    let sibling = executable.deletingLastPathComponent().appendingPathComponent("unrestor-daemon")
    return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
}

private func installedFileIsSafe(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
        && info.st_uid == 0 && (info.st_mode & 0o022) == 0
}

func commandInstall(_ rest: [String]) -> Never {
    requireRoot("install")

    var uid: UInt32?
    var args = rest
    while let first = args.first {
        guard first == "--uid", args.count >= 2, let value = UInt32(args[1]) else {
            fail("unexpected argument: \(first)")
        }
        uid = value
        args.removeFirst(2)
    }
    if uid == nil, let sudo = ProcessInfo.processInfo.environment["SUDO_UID"] { uid = UInt32(sudo) }
    guard let uid, uid > 0 else {
        fail("could not tell which user to allow. Run it as: sudo unrestor install")
    }
    guard let account = getpwuid(uid_t(uid)) else { fail("no user with id \(uid)") }
    let user = String(cString: account.pointee.pw_name)

    guard let source = locateDaemonBinary() else {
        fail("could not find unrestor-daemon next to this program. Reinstall Unrestor.", code: 1)
    }

    let helperDirectory = (DaemonProtocol.installedDaemonPath as NSString).deletingLastPathComponent
    let fm = FileManager.default
    do {
        if !fm.fileExists(atPath: helperDirectory) {
            try fm.createDirectory(
                atPath: helperDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0])
        }
        guard isRootOnlyWritable(helperDirectory) else {
            fail("\(helperDirectory) is not root-only writable, so it is not safe to run a root service from. Not installing.", code: 1)
        }

        // Stop any older copy first so the file can be replaced.
        launchctl(["bootout", "system/\(DaemonProtocol.label)"])

        let staged = DaemonProtocol.installedDaemonPath + ".new"
        try? fm.removeItem(atPath: staged)
        try fm.copyItem(at: source, to: URL(fileURLWithPath: staged))
        // A copy taken from a downloaded app carries the download quarantine mark.
        removexattr(staged, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard chmod(staged, 0o755) == 0, chown(staged, 0, 0) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard rename(staged, DaemonProtocol.installedDaemonPath) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard installedFileIsSafe(DaemonProtocol.installedDaemonPath) else {
            fail("the installed daemon has unsafe ownership or permissions. Not starting it.", code: 1)
        }

        let plist = LaunchDaemonPlist.render(
            daemonPath: DaemonProtocol.installedDaemonPath, allowedUID: uid)
        let stagedPlist = DaemonProtocol.plistPath + ".new"
        try plist.write(toFile: stagedPlist, atomically: false, encoding: .utf8)
        guard chmod(stagedPlist, 0o644) == 0, chown(stagedPlist, 0, 0) == 0,
              rename(stagedPlist, DaemonProtocol.plistPath) == 0
        else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    } catch {
        fail("install failed: \(error.localizedDescription)", code: 1)
    }

    let started = launchctl(["bootstrap", "system", DaemonProtocol.plistPath])
    guard started.status == 0 else {
        fail("launchctl could not start the service: \(started.output)", code: 1)
    }

    // Wait for the socket, so "installed" means "working".
    let client = DaemonClient()
    var ready = false
    for _ in 0..<30 {
        if (try? client.connect()) != nil, (try? client.send(.hello)) != nil { ready = true; break }
        usleep(100_000)
    }
    client.close()
    guard ready else {
        fail("installed, but the service did not answer. Check: log show --last 2m --predicate 'subsystem == \"\(DaemonProtocol.label)\"'", code: 1)
    }

    say("Installed. The background service is running for user \(user).")
    say("")
    say("Try it:  unrestor run -- sleep 30")
    say("Check:   unrestor status")
    say("Remove:  sudo unrestor uninstall")
    exit(0)
}

func commandUninstall() -> Never {
    requireRoot("uninstall")

    // Stopping the service makes it release every hold and restore the setting.
    launchctl(["bootout", "system/\(DaemonProtocol.label)"])
    usleep(500_000)

    let fm = FileManager.default
    for path in [DaemonProtocol.plistPath, DaemonProtocol.installedDaemonPath, DaemonProtocol.socketPath] {
        try? fm.removeItem(atPath: path)
    }

    let stillBlocked = PMSetSleepControl().isSleepDisabled()
    if stillBlocked == true {
        say("Removed the service, but the system still reports sleep as blocked.")
        say("If you did not set that yourself, run: sudo pmset -a disablesleep 0")
        say("(Kept \(DaemonProtocol.stateDirectory) so a restore record is not lost.)")
    } else {
        try? fm.removeItem(atPath: DaemonProtocol.stateDirectory)
        say("Uninstalled. Your sleep settings are back to normal.")
    }
    say("You can now delete Unrestor.app. Settings are in ~/Library/Application Support/Unrestor.")
    exit(0)
}
