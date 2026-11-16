import Darwin
import Foundation
import UnrestorCore

/// Keeps one hold alive while a command, process, or timer is running: connects
/// to the daemon, renews the hold every second, and tells you once when the
/// daemon lets go or cannot be reached. Closing the connection releases the hold.
final class Holder: @unchecked Sendable {
    private let settings: Settings
    private let lock = NSLock()
    private var running = false
    private var finished = DispatchSemaphore(value: 0)
    private var announced: String?
    private var stopped = false

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        lock.lock(); running = true; lock.unlock()
        let thread = Thread { [self] in loop() }
        thread.name = "unrestor.holder"
        thread.start()
    }

    /// Stops renewing and closes the connection, which releases the hold.
    func stop() {
        lock.lock()
        running = false
        let already = stopped
        stopped = true
        lock.unlock()
        guard !already else { return }
        _ = finished.wait(timeout: .now() + 3)
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private func note(_ message: String) {
        guard announced != message else { return }
        announced = message
        FileHandle.standardError.write(Data("unrestor: \(message)\n".utf8))
    }

    private func loop() {
        let client = DaemonClient()
        defer { client.close(); finished.signal() }
        while isRunning {
            do {
                if !client.isConnected {
                    try client.connect()
                    _ = try client.send(.hello)
                }
                let reply = try client.send(.hold(
                    batteryFloor: settings.batteryFloor,
                    onlyOnPower: settings.onlyWhileConnectedToPower,
                    lowPower: settings.lowPowerWhileHeld))
                switch reply {
                case .held: note("holding the Mac awake")
                case .released(let reason): note(reason)
                default: break
                }
            } catch let error as DaemonClientError {
                client.close()
                switch error {
                case .notRunning:
                    note("the background service is not running, so the Mac may sleep. Run: sudo unrestor install")
                default:
                    note(error.localizedDescription)
                }
            } catch {
                client.close()
            }
            usleep(1_000_000)
        }
    }
}
