import Darwin
import Foundation
import UnrestorCore

let versionString = UnrestorVersion.current

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("unrestor: \(message)\n".utf8))
    exit(code)
}

/// Pulls `--for` and `--name` from the front of `args`, stopping at the first
/// other argument (or at `--`).
func parseOptions(_ args: inout [String]) -> (expiresAt: Date?, name: String?) {
    var expiresAt: Date?
    var name: String?
    while let first = args.first {
        switch first {
        case "--for":
            guard args.count >= 2, let seconds = DurationParser.parse(args[1]) else {
                fail("--for needs a time such as 90m or 2h")
            }
            expiresAt = Date().addingTimeInterval(seconds)
            args.removeFirst(2)
        case "--name":
            guard args.count >= 2, !args[1].isEmpty else { fail("--name needs a value") }
            name = String(args[1].prefix(80))
            args.removeFirst(2)
        default:
            return (expiresAt, name)
        }
    }
    return (expiresAt, name)
}

func requestID(_ prefix: String) -> String {
    prefix + "-" + String(UUID().uuidString.prefix(8)).lowercased()
}

/// Lists the hold in the menu-bar app while it lasts. Display only: the hold
/// itself is the CLI's own connection to the daemon.
func announce(_ request: HoldRequest, store: HoldRequestStore) {
    try? store.write(request)
}

func commandRun(_ rest: [String], store: HoldRequestStore) -> Never {
    var args = rest
    let options = parseOptions(&args)
    if args.first == "--" { args.removeFirst() }
    guard let program = args.first else { fail("run needs a command after --. Example: unrestor run -- npm test") }

    let id = requestID("run")
    announce(HoldRequest(
        id: id,
        label: options.name ?? URL(fileURLWithPath: program).lastPathComponent,
        pid: getpid(),
        expiresAt: options.expiresAt
    ), store: store)

    let holder = Holder(settings: SettingsStore().load())
    holder.start()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    do {
        try process.run()
    } catch {
        holder.stop(); store.remove(id: id)
        fail("could not start \(program): \(error.localizedDescription)", code: 127)
    }

    if let expiresAt = options.expiresAt {
        // After the time limit the Mac may sleep again; the command keeps running.
        DispatchQueue.global().asyncAfter(deadline: .now() + max(0, expiresAt.timeIntervalSinceNow)) {
            FileHandle.standardError.write(Data("unrestor: time limit reached, letting the Mac sleep\n".utf8))
            holder.stop()
        }
    }
    process.waitUntilExit()
    holder.stop()
    store.remove(id: id)
    switch process.terminationReason {
    case .exit: exit(process.terminationStatus)
    case .uncaughtSignal: exit(128 + process.terminationStatus)
    @unknown default: exit(1)
    }
}

/// Blocks, holding, until `done` returns true or the time limit passes.
func holdUntil(_ options: (expiresAt: Date?, name: String?), id: String, label: String,
               store: HoldRequestStore, done: () -> Bool) -> Never {
    announce(HoldRequest(id: id, label: label, pid: getpid(), expiresAt: options.expiresAt), store: store)
    let holder = Holder(settings: SettingsStore().load())
    holder.start()
    while !done() {
        if let expiresAt = options.expiresAt, Date() >= expiresAt {
            FileHandle.standardError.write(Data("unrestor: time limit reached\n".utf8))
            break
        }
        sleep(1)
    }
    holder.stop()
    store.remove(id: id)
    exit(0)
}

func commandWatch(_ rest: [String], store: HoldRequestStore) -> Never {
    var args = rest
    guard let first = args.first, let pid = Int32(first), pid > 0 else {
        fail("watch needs a process id. Example: unrestor watch 4821")
    }
    args.removeFirst()
    let options = parseOptions(&args)
    guard args.isEmpty else { fail("unexpected argument: \(args[0])") }
    guard ProcessLiveness.isAlive(pid) else { fail("no process with id \(pid)", code: 1) }
    print("Staying awake while process \(pid) runs. Press Ctrl-C to stop.")
    holdUntil(options, id: requestID("watch"), label: options.name ?? "process \(pid)",
              store: store) { !ProcessLiveness.isAlive(pid) }
}

func commandHold(_ rest: [String], store: HoldRequestStore) -> Never {
    var args = rest
    let options = parseOptions(&args)
    guard args.isEmpty else { fail("unexpected argument: \(args[0])") }
    if let until = options.expiresAt {
        print("Staying awake for \(DurationParser.format(until.timeIntervalSinceNow)). Press Ctrl-C to stop sooner.")
    } else {
        print("Staying awake. Press Ctrl-C to stop.")
    }
    holdUntil(options, id: requestID("hold"), label: options.name ?? "manual hold",
              store: store) { false }
}

func commandStatus(store: HoldRequestStore) {
    // Service
    let client = DaemonClient()
    var serviceOK = false
    do {
        try client.connect()
        if case .hello(let version) = try client.send(.hello) {
            print("Background service: running (v\(version))")
            serviceOK = true
        }
    } catch let error as DaemonClientError {
        print("Background service: NOT running")
        print("  \(error.localizedDescription)")
    } catch {
        print("Background service: unknown (\(error.localizedDescription))")
    }
    client.close()

    // Holds
    let now = Date()
    let active = store.activeRequests(now: now)
    if active.isEmpty {
        print("Holds: none")
    } else {
        print("Holds:")
        for request in active {
            var line = "  \(request.label)"
            if let pid = request.pid { line += " (pid \(pid))" }
            if let expiresAt = request.expiresAt {
                line += ", \(DurationParser.format(expiresAt.timeIntervalSince(now))) left"
            }
            print(line)
        }
    }

    // System
    let power = IOKitPowerSource().current()
    let settings = SettingsStore().load().clamped()
    let blocked = PMSetSleepControl().isSleepDisabled()
    print("Sleep blocked by the system: " + (blocked == true ? "yes" : blocked == false ? "no" : "unknown"))
    print("Power: \(power.onBattery ? "battery" : "connected"), \(power.batteryPercent)%")
    if let limit = HoldPolicy.safetyRelease(settings: settings, power: power) {
        print("Right now Unrestor would let the Mac sleep: \(limit.reason)")
    }
    if !serviceOK {
        print("Next step: sudo unrestor install")
    } else if !active.isEmpty, blocked == false {
        print("Holds are listed but sleep is not blocked. See the limit above, or run `unrestor run` again.")
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
let store = HoldRequestStore()
guard let command = arguments.first else {
    print(helpText)
    exit(0)
}
arguments.removeFirst()

switch command {
case "run": commandRun(arguments, store: store)
case "watch": commandWatch(arguments, store: store)
case "hold": commandHold(arguments, store: store)
case "status": commandStatus(store: store)
case "install": commandInstall(arguments)
case "uninstall": commandUninstall()
case "--version", "-v", "version": print("unrestor \(versionString)")
case "--help", "-h", "help": print(helpText)
default: fail("unknown command '\(command)'. Try `unrestor help`.")
}
