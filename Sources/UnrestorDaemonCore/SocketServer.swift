import Darwin
import Foundation
import UnrestorCore

/// A Unix-socket server for the daemon. The socket is owned by one user with
/// mode 0600, and every connection's peer uid is checked again on accept.
public final class SocketServer: @unchecked Sendable {
    private let path: String
    private let allowedUID: uid_t
    private let makeHandler: @Sendable () -> ConnectionHandler
    private let maxConnections = 8
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var open: Set<Int32> = []
    private var stopping = false

    public init(
        path: String,
        allowedUID: uid_t,
        makeHandler: @escaping @Sendable () -> ConnectionHandler
    ) {
        self.path = path
        self.allowedUID = allowedUID
        self.makeHandler = makeHandler
    }

    public enum ServerError: Error { case failed(String) }

    public func start() throws {
        unlink(path)
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw ServerError.failed("socket: \(String(cString: strerror(errno)))") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(sock)
            throw ServerError.failed("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (i, byte) in bytes.enumerated() { raw[i] = byte }
            raw[bytes.count] = 0
        }
        // Create the socket private from the start: no window where others can connect.
        let oldMask = umask(0o177)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(oldMask)
        guard bound == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(sock)
            throw ServerError.failed("bind: \(message)")
        }
        // The kernel enforces the owner. Ignore failure only when not root (tests).
        if geteuid() == 0 {
            guard chown(path, allowedUID, gid_t(0)) == 0 else {
                let message = String(cString: strerror(errno))
                Darwin.close(sock)
                throw ServerError.failed("chown: \(message)")
            }
        }
        guard chmod(path, 0o600) == 0, listen(sock, 8) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(sock)
            throw ServerError.failed("listen: \(message)")
        }
        lock.lock(); listenFD = sock; stopping = false; lock.unlock()
        let thread = Thread { [weak self] in self?.acceptLoop(sock) }
        thread.name = "unrestor.accept"
        thread.start()
    }

    /// Closes the listener and every connection. Each connection's hold is
    /// released as its read loop ends.
    public func stop() {
        lock.lock()
        stopping = true
        let fds = open
        let listener = listenFD
        listenFD = -1
        lock.unlock()
        if listener >= 0 { shutdown(listener, SHUT_RDWR); Darwin.close(listener) }
        for fd in fds { shutdown(fd, SHUT_RDWR) }
        unlink(path)
        // Give connection threads a moment to release their holds.
        for _ in 0..<50 {
            lock.lock(); let remaining = open.count; lock.unlock()
            if remaining == 0 { break }
            usleep(20_000)
        }
    }

    private func acceptLoop(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            lock.lock(); let done = stopping; lock.unlock()
            if client < 0 || done {
                if client >= 0 { Darwin.close(client) }
                if done || errno != EINTR { return }
                continue
            }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == allowedUID || uid == 0 else {
                Darwin.close(client)
                continue
            }
            lock.lock()
            let full = open.count >= maxConnections
            if !full { open.insert(client) }
            lock.unlock()
            if full { Darwin.close(client); continue }

            let handler = makeHandler()
            let thread = Thread { [weak self] in self?.serve(client, handler) }
            thread.name = "unrestor.client"
            thread.start()
        }
    }

    private func serve(_ fd: Int32, _ handler: ConnectionHandler) {
        defer {
            handler.close()
            Darwin.close(fd)
            lock.lock(); open.remove(fd); lock.unlock()
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 512)
        while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 1000)
            if ready < 0 { if errno == EINTR { continue }; return }
            if ready == 0 {
                if handler.expireLeaseIfNeeded() { return }
                continue
            }
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return }
            buffer.append(chunk, count: count)
            if buffer.count > 1024 && !buffer.contains(0x0A) { return }   // no newline: not our client
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(buffer.startIndex...newline)
                let reply = Data((handler.handle(line: line).line + "\n").utf8)
                let written = reply.withUnsafeBytes { write(fd, $0.baseAddress, reply.count) }
                if written != reply.count { return }
            }
        }
    }
}
