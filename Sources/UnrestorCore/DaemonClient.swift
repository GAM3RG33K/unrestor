import Darwin
import Foundation

public enum DaemonClientError: Error, Equatable, LocalizedError {
    case notRunning
    case notPermitted
    case io(String)
    case badReply(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            "The background service is not running. Install it with: sudo unrestor install"
        case .notPermitted:
            "The background service refused this user. Re-run: sudo unrestor install"
        case .io(let message): "Lost contact with the background service (\(message))."
        case .badReply(let line): "Unexpected reply from the background service: \(line)"
        }
    }
}

/// A blocking client for the daemon's Unix socket. One instance is one
/// connection. Keep it open to keep a hold: closing it releases the hold.
/// Not thread-safe: use one queue per client.
public final class DaemonClient {
    private var fd: Int32 = -1
    private var buffer = Data()
    private let path: String

    public init(path: String = DaemonProtocol.socketPath) {
        self.path = path
    }

    deinit { close() }

    public var isConnected: Bool { fd >= 0 }

    public func connect(timeout: TimeInterval = 3) throws {
        close()
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw DaemonClientError.io(String(cString: strerror(errno))) }
        var one: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(sock)
            throw DaemonClientError.io("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (i, byte) in bytes.enumerated() { raw[i] = byte }
            raw[bytes.count] = 0
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(sock)
            switch code {
            case ENOENT, ECONNREFUSED: throw DaemonClientError.notRunning
            case EACCES, EPERM: throw DaemonClientError.notPermitted
            default: throw DaemonClientError.io(String(cString: strerror(code)))
            }
        }
        fd = sock
        buffer = Data()
    }

    public func send(_ command: DaemonCommand) throws -> DaemonReply {
        guard fd >= 0 else { throw DaemonClientError.notRunning }
        let data = Data((command.line + "\n").utf8)
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
        guard written == data.count else {
            close()
            throw DaemonClientError.io("write failed")
        }
        let line = try readLine()
        guard let reply = DaemonReply.parse(line) else { throw DaemonClientError.badReply(line) }
        return reply
    }

    public func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    private func readLine() throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 512)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 {
                close()
                throw DaemonClientError.io(count == 0 ? "connection closed" : String(cString: strerror(errno)))
            }
            buffer.append(chunk, count: count)
            if buffer.count > 4096 { close(); throw DaemonClientError.io("reply too long") }
        }
    }
}
