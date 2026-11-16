import Foundation

/// Reads the system `disablesleep` flag with `pmset -g`. Read-only: only the
/// privileged daemon ever writes it.
///
/// Keep calls off the main thread: a synchronous `Process.waitUntilExit` spins
/// the main run loop.
public final class PMSetSleepControl: @unchecked Sendable {
    public init() {}

    public func isSleepDisabled() -> Bool? {
        PMSet.parseSleepDisabled(from: Self.run("/usr/bin/pmset", ["-g"]))
    }

    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(decoding: data, as: UTF8.self)
            return output.isEmpty ? nil : output
        } catch {
            return nil
        }
    }
}
