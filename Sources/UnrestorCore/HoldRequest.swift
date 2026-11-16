import Darwin
import Foundation

/// One reason to keep the Mac awake. A request is a small JSON file, so the
/// CLI and the menu-bar app need no IPC between them: the CLI writes files, the
/// app reads them. A request ends when it is removed, when it expires, or when
/// the process it names exits.
public struct HoldRequest: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    /// The process this request lives and dies with. Nil for a manual request.
    public var pid: Int32?
    public var createdAt: Date
    /// Nil means no time limit.
    public var expiresAt: Date?

    public init(
        id: String,
        label: String,
        pid: Int32? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.pid = pid
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// The id of the single manual request, shared by `unrestor on` and the
    /// menu's toggle, so turning it on twice does not stack.
    public static let manualID = "manual"

    /// Ids become file names, so they are restricted to a safe alphabet.
    public static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else { return false }
        return id.unicodeScalars.allSatisfy {
            switch $0.value {
            case 48...57, 65...90, 97...122, 45, 46, 95: true   // 0-9 A-Z a-z - . _
            default: false
            }
        } && !id.hasPrefix(".")
    }

    public func isActive(
        now: Date,
        isProcessAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> Bool {
        if let expiresAt, now >= expiresAt { return false }
        if let pid, !isProcessAlive(pid) { return false }
        return true
    }
}

public enum ProcessLiveness {
    /// `kill(pid, 0)` sends nothing. EPERM still means the process exists.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

/// A directory of request files, one per request.
public struct HoldRequestStore: Sendable {
    public let directory: URL

    public init(directory: URL = HoldRequestStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unrestor", isDirectory: true)
            .appendingPathComponent("requests", isDirectory: true)
    }

    public enum StoreError: Error, Equatable {
        case invalidID(String)
    }

    public func write(_ request: HoldRequest) throws {
        guard HoldRequest.isValidID(request.id) else {
            throw StoreError.invalidID(request.id)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: url(for: request.id), options: .atomic)
    }

    public func remove(id: String) {
        guard HoldRequest.isValidID(id) else { return }
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Every readable request. A corrupt or foreign file is skipped, never fatal.
    public func list() -> [HoldRequest] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> HoldRequest? in
                guard let data = try? Data(contentsOf: file),
                      let request = try? decoder.decode(HoldRequest.self, from: data),
                      HoldRequest.isValidID(request.id),
                      file.deletingPathExtension().lastPathComponent == request.id
                else { return nil }
                return request
            }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// The requests still in force. Finished ones are deleted as a side effect,
    /// so a crashed `unrestor run` cannot leave a file behind forever.
    @discardableResult
    public func activeRequests(
        now: Date = Date(),
        isProcessAlive: (Int32) -> Bool = ProcessLiveness.isAlive
    ) -> [HoldRequest] {
        var active: [HoldRequest] = []
        for request in list() {
            if request.isActive(now: now, isProcessAlive: isProcessAlive) {
                active.append(request)
            } else {
                remove(id: request.id)
            }
        }
        return active
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(id + ".json", isDirectory: false)
    }
}
