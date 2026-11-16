import Darwin
import Foundation
import UnrestorCore

let version = "0.1.0"

let usage = """
unrestor \(version): keep your Mac awake, lid closed, while work runs.

Usage:
  unrestor run [--for DURATION] [--name NAME] -- COMMAND [ARGS...]
      Stay awake while COMMAND runs, then let the Mac sleep.
  unrestor watch PID [--for DURATION] [--name NAME]
      Stay awake while process PID runs.
  unrestor on [--for DURATION]     Stay awake until `unrestor off`.
  unrestor off                     End the manual hold.
  unrestor status                  Show what is holding the Mac awake.
  unrestor --version

DURATION looks like 90m, 2h, 1h30m. The Unrestor menu-bar app must be running
to apply the hold; it also enforces the battery and heat limits.
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("unrestor: \(message)\n".utf8))
    exit(code)
}

/// Pulls `--for` and `--name` from the front of `args`, stopping at the first
/// argument that is not one of them (or at `--`).
func parseOptions(_ args: inout [String]) -> (expiresAt: Date?, name: String?) {
    var expiresAt: Date?
    var name: String?
    while let first = args.first {
        switch first {
        case "--for":
            guard args.count >= 2, let seconds = DurationParser.parse(args[1]) else {
                fail("--for needs a duration such as 90m or 2h")
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

func shortID(_ prefix: String) -> String {
    prefix + "-" + String(UUID().uuidString.prefix(8)).lowercased()
}

func write(_ request: HoldRequest, to store: HoldRequestStore) {
    do { try store.write(request) } catch { fail("could not save the request: \(error)", code: 1) }
}

func commandRun(_ rest: [String], store: HoldRequestStore) -> Never {
    var args = rest
    let options = parseOptions(&args)
    if args.first == "--" { args.removeFirst() }
    guard let program = args.first else { fail("run needs a command after --") }

    let id = shortID("run")
    write(HoldRequest(
        id: id,
        label: options.name ?? URL(fileURLWithPath: program).lastPathComponent,
        pid: getpid(),
        expiresAt: options.expiresAt
    ), to: store)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    do {
        try process.run()
    } catch {
        store.remove(id: id)
        fail("could not start \(program): \(error.localizedDescription)", code: 127)
    }
    process.waitUntilExit()
    store.remove(id: id)
    switch process.terminationReason {
    case .exit: exit(process.terminationStatus)
    case .uncaughtSignal: exit(128 + process.terminationStatus)
    @unknown default: exit(1)
    }
}

func commandWatch(_ rest: [String], store: HoldRequestStore) {
    var args = rest
    guard let first = args.first, let pid = Int32(first), pid > 0 else {
        fail("watch needs a process id")
    }
    args.removeFirst()
    let options = parseOptions(&args)
    guard args.isEmpty else { fail("unexpected argument: \(args[0])") }
    guard ProcessLiveness.isAlive(pid) else { fail("no process with id \(pid)", code: 1) }
    write(HoldRequest(
        id: "watch-\(pid)",
        label: options.name ?? "process \(pid)",
        pid: pid,
        expiresAt: options.expiresAt
    ), to: store)
    print("Staying awake while process \(pid) runs.")
}

func commandOn(_ rest: [String], store: HoldRequestStore) {
    var args = rest
    let options = parseOptions(&args)
    guard args.isEmpty else { fail("unexpected argument: \(args[0])") }
    write(HoldRequest(
        id: HoldRequest.manualID,
        label: "manual hold",
        expiresAt: options.expiresAt
    ), to: store)
    if let until = options.expiresAt {
        print("Staying awake for \(DurationParser.format(until.timeIntervalSinceNow)).")
    } else {
        print("Staying awake until you run `unrestor off`.")
    }
}

func commandStatus(store: HoldRequestStore) {
    let now = Date()
    let active = store.activeRequests(now: now)
    if active.isEmpty {
        print("No holds requested.")
    } else {
        print("Holds requested:")
        for request in active {
            var line = "  \(request.label)"
            if let pid = request.pid { line += " (pid \(pid))" }
            if let expiresAt = request.expiresAt {
                line += ", \(DurationParser.format(expiresAt.timeIntervalSince(now))) left"
            }
            print(line)
        }
    }
    let power = IOKitPowerSource().current()
    let disabled = PMSetSleepControl().isSleepDisabled()
    let applied = switch disabled {
    case .some(true): "yes"
    case .some(false): "no"
    case .none: "unknown"
    }
    print("Sleep currently blocked by the system flag: \(applied)")
    print("Power: \(power.onBattery ? "battery" : "connected"), \(power.batteryPercent)%")
    if !active.isEmpty, disabled == false {
        print("Note: is the Unrestor app running? It applies the hold and the battery and heat limits.")
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
let store = HoldRequestStore()
guard let command = arguments.first else {
    print(usage)
    exit(0)
}
arguments.removeFirst()

switch command {
case "run": commandRun(arguments, store: store)
case "watch": commandWatch(arguments, store: store)
case "on": commandOn(arguments, store: store)
case "off":
    store.remove(id: HoldRequest.manualID)
    print("Manual hold ended.")
case "status": commandStatus(store: store)
case "--version", "-v", "version": print("unrestor \(version)")
case "--help", "-h", "help": print(usage)
default: fail("unknown command '\(command)'. Try `unrestor help`.")
}
