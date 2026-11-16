import AppKit
import Foundation
import Observation
import ServiceManagement
import UnrestorCore

enum ServiceState: Equatable {
    case starting
    case connected
    case notInstalled
    case failed(String)
}

/// Owns the one connection to the daemon. All socket work runs on a private
/// serial queue, so the main thread never blocks on it.
private final class DaemonLink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.unrestor.daemon-link")
    private let client = DaemonClient()

    enum Outcome: Sendable {
        case held, released(String), unavailable(DaemonClientError)
    }

    func sync(
        wantHold: Bool, settings: Settings,
        completion: @escaping @Sendable (Outcome) -> Void
    ) {
        queue.async { [client] in
            do {
                if !client.isConnected {
                    try client.connect()
                    _ = try client.send(.hello)
                }
                if wantHold {
                    let reply = try client.send(.hold(
                        batteryFloor: settings.batteryFloor,
                        onlyOnPower: settings.onlyWhileConnectedToPower,
                        lowPower: settings.lowPowerWhileHeld))
                    switch reply {
                    case .held: completion(.held)
                    case .released(let reason): completion(.released(reason))
                    case .error(let message): completion(.unavailable(.io(message)))
                    case .hello: completion(.released(""))
                    }
                } else {
                    // Releasing is just not asking; an explicit release is faster than the lease.
                    _ = try client.send(.release)
                    completion(.released(""))
                }
            } catch let error as DaemonClientError {
                client.close()
                completion(.unavailable(error))
            } catch {
                client.close()
                completion(.unavailable(.io(error.localizedDescription)))
            }
        }
    }

    /// Closing the connection makes the daemon release the hold.
    func close() { queue.sync { client.close() } }
}

@MainActor
@Observable
final class AppModel {
    private(set) var service: ServiceState = .starting
    private(set) var decision = HoldDecision(hold: false, reason: "Nothing is asking to stay awake")
    private(set) var requests: [HoldRequest] = []
    private(set) var power = IOKitPowerSource().current()
    private(set) var launchAtLogin = false
    private(set) var installing = false
    var settings: Settings {
        didSet { settingsStore.save(settings) }
    }

    private let store = HoldRequestStore()
    private let settingsStore = SettingsStore()
    private let link = DaemonLink()
    private var timer: Timer?
    private var inFlight = false

    init() {
        settings = settingsStore.load()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        link.close()
    }

    // MARK: Manual hold (the menu switch)

    var manualRequest: HoldRequest? { requests.first { $0.id == HoldRequest.manualID } }

    func setManualHold(_ on: Bool, for duration: TimeInterval? = nil) {
        if on {
            try? store.write(HoldRequest(
                id: HoldRequest.manualID,
                label: "manual hold",
                expiresAt: duration.map { Date().addingTimeInterval($0) }
            ))
        } else {
            store.remove(id: HoldRequest.manualID)
        }
        tick()
    }

    // MARK: Background service

    /// The command that installs the service, for the Terminal route.
    var installCommand: String {
        "sudo \(shellQuote(cliPath)) install"
    }

    private var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/unrestor").path
    }

    func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
    }

    /// Runs the installer through the standard macOS password prompt.
    func installService() {
        guard !installing else { return }
        installing = true
        let command = "\(shellQuote(cliPath)) install --uid \(getuid())"
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            var message: String?
            do {
                try process.run()
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let text = String(decoding: data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // -128 is "User canceled": not an error worth showing.
                    message = text.contains("-128") ? nil : (text.isEmpty ? "The install did not finish." : text)
                }
            } catch {
                message = error.localizedDescription
            }
            await MainActor.run {
                self.installing = false
                if let message { self.service = .failed(message) }
                self.tick()
            }
        }
    }

    func openHelp() {
        if let url = URL(string: "https://github.com/GAM3RG33K/unrestor#install") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Polling

    private func tick() {
        requests = store.activeRequests()
        power = IOKitPowerSource().current()
        decision = HoldPolicy.decide(active: requests, settings: settings, power: power)
        guard !inFlight else { return }
        inFlight = true
        // The app holds only for its own manual switch. `unrestor run` and the
        // other commands hold directly through the daemon; the menu just lists
        // them. The daemon re-checks every heartbeat and has the last word.
        let wantHold = decision.hold && manualRequest != nil
        link.sync(wantHold: wantHold, settings: settings) { [weak self] outcome in
            Task { @MainActor in self?.apply(outcome, wanted: wantHold) }
        }
    }

    private func apply(_ outcome: DaemonLink.Outcome, wanted: Bool) {
        inFlight = false
        switch outcome {
        case .held:
            service = .connected
        case .released(let reason):
            service = .connected
            if wanted, !reason.isEmpty {
                decision = HoldDecision(hold: false, reason: reason)
            }
        case .unavailable(let error):
            switch error {
            case .notRunning: service = .notInstalled
            case .notPermitted: service = .failed(error.localizedDescription)
            default: service = .failed(error.localizedDescription)
            }
            if wanted {
                decision = HoldDecision(hold: false, reason: "Background service is not running")
            }
        }
    }

    // MARK: Launch at login

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshLaunchAtLogin()
    }
}

/// Single-quotes a path for /bin/sh.
func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// A double-quoted AppleScript string literal.
func appleScriptQuote(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
