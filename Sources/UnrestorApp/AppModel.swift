import Foundation
import Observation
import ServiceManagement
import UnrestorCore

enum ServiceState: Equatable {
    case starting
    case connected
    case needsSetup(String)
}

@MainActor
@Observable
final class AppModel {
    private(set) var service: ServiceState = .starting
    private(set) var decision = HoldDecision(hold: false, reason: "Nothing is asking to stay awake")
    private(set) var requests: [HoldRequest] = []
    private(set) var power = IOKitPowerSource().current()
    private(set) var launchAtLogin = false
    var settings: Settings {
        didSet { saveSettings() }
    }

    private let store = HoldRequestStore()
    private var connection: DaemonConnection?
    private var applied = false
    private var appliedLowPower = false
    private var busy = false
    private var timer: Timer?

    init() {
        settings = Self.loadSettings()
    }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        Task { await connect() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // Closing the connection makes the daemon release the hold.
        connection?.invalidate()
        connection = nil
    }

    // MARK: Manual hold (shared with `unrestor on/off`)

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
        Task { await tick() }
    }

    // MARK: Background service

    func setUpService() {
        Task {
            do {
                try DaemonRegistration.register()
            } catch where DaemonRegistration.isApprovalNeeded(error) {
                service = .needsSetup("Allow Unrestor in System Settings > Login Items.")
                DaemonRegistration.openLoginItemsSettings()
                return
            } catch {
                service = .needsSetup(error.localizedDescription)
                return
            }
            await connect()
        }
    }

    private func connect(retryAfterRefresh: Bool = true) async {
        connection?.invalidate()
        connection = nil
        applied = false
        appliedLowPower = false
        do {
            let new = try DaemonConnection()
            new.onLost = { [weak self] in
                Task { @MainActor in self?.daemonLost() }
            }
            try await new.connect()
            connection = new
            service = .connected
        } catch DaemonFailure.staleBuild where retryAfterRefresh {
            do { try await DaemonRegistration.refresh() } catch {
                service = .needsSetup(error.localizedDescription)
                return
            }
            await connect(retryAfterRefresh: false)
        } catch {
            service = .needsSetup(error.localizedDescription)
        }
    }

    private func daemonLost() {
        guard service == .connected else { return }
        applied = false
        appliedLowPower = false
        service = .starting
        Task { await connect() }
    }

    // MARK: Polling

    private func tick() async {
        requests = store.activeRequests()
        power = IOKitPowerSource().current()
        decision = HoldPolicy.decide(active: requests, settings: settings, power: power)
        guard let connection, service == .connected, !busy else { return }

        let wantHold = decision.hold
        let wantLowPower = wantHold && settings.lowPowerWhileHeld
        guard wantHold != applied || wantLowPower != appliedLowPower else { return }

        busy = true
        defer { busy = false }
        do {
            // Low Power Mode is nested inside the hold: turn it off first.
            if !wantLowPower, appliedLowPower {
                try await connection.setLowPowerMode(false)
                appliedLowPower = false
            }
            if wantHold != applied {
                try await connection.setHold(wantHold)
                applied = wantHold
            }
            if wantLowPower, !appliedLowPower, applied {
                try await connection.setLowPowerMode(true)
                appliedLowPower = true
            }
        } catch {
            decision = HoldDecision(hold: false, reason: error.localizedDescription)
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

    // MARK: Settings storage

    private static let settingsKey = "settings.v1"

    private static func loadSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}
