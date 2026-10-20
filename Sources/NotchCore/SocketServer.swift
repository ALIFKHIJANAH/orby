import Darwin
import Foundation
import NotchShared

/// A bridge waiting for a decision. Reply exactly once; EOF means the agent gave up on it.
public final class BridgeConnection: @unchecked Sendable {
    private let fd: Int32
    private let queue: DispatchQueue
    private var source: DispatchSourceRead?
    private var finished = false
    private var onClose: (@Sendable () -> Void)?

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    /// Watch for the peer hanging up while we wait for the user. The source keeps this
    /// connection alive until it finishes, so callers don't have to retain it.
    public func watch(onClose: @escaping @Sendable () -> Void) {
        queue.async {
            guard !self.finished else { return }
            self.onClose = onClose
            let src = DispatchSource.makeReadSource(fileDescriptor: self.fd, queue: self.queue)
            src.setEventHandler {
                var byte: UInt8 = 0
                let n = recv(self.fd, &byte, 1, MSG_PEEK)
                // Spurious wake-ups on a non-blocking socket are not a hang-up.
                if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { self.finish(notify: true) }
            }
            self.source = src
            src.resume()
        }
    }

    public func reply(_ reply: BridgeReply) {
        queue.async {
            guard !self.finished, var data = try? wireJSONEncoder.encode(reply) else { return }
            data.append(UInt8(ascii: "\n"))
            _ = data.withUnsafeBytes { raw in send(self.fd, raw.baseAddress, raw.count, 0) }
            self.finish(notify: false)
        }
    }

    private func finish(notify: Bool) {
        guard !finished else { return }
        finished = true
        let fd = self.fd
        if let source {
            // Close only after the source is torn down; closing first is undefined for dispatch.
            source.setCancelHandler { close(fd) }
            source.cancel()
            self.source = nil
        } else {
            close(fd)
        }
        if notify { onClose?() }
        onClose = nil
    }
}

/// Newline-delimited JSON over a Unix domain socket at ~/.orby/run/app.sock.
public final class SocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (BridgeEnvelope, BridgeConnection?) -> Void

    public let path: String
    private let queue = DispatchQueue(label: "orby.socket")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let handler: Handler
    private static let maxMessage = 8 * 1024 * 1024

    public init(path: String = NotchPaths.socket.path, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 64) == 0 else {
            let err = errno
            close(fd)
            throw POSIXError(.init(rawValue: err) ?? .EIO)
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptPending() }
        acceptSource = src
        src.resume()
    }

    public func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 { close(listenFD) }
            listenFD = -1
            unlink(path)
        }
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            readEnvelope(from: client)
        }
    }

    /// Read one line on a per-client source so a slow writer never blocks other bridges.
    private func readEnvelope(from fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 { buffer.append(contentsOf: chunk[0..<n]) }
            let eof = n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)
            let newline = buffer.firstIndex(of: UInt8(ascii: "\n"))
            guard newline != nil || eof || buffer.count > Self.maxMessage else { return }

            src.cancel()
            let line = newline.map { buffer[..<$0] } ?? buffer[...]
            guard let envelope = try? wireJSONDecoder.decode(BridgeEnvelope.self, from: Data(line)) else {
                close(fd)
                return
            }
            if envelope.expectsReply && !eof {
                self.handler(envelope, BridgeConnection(fd: fd, queue: self.queue))
            } else {
                close(fd)
                self.handler(envelope, nil)
            }
        }
        src.resume()
    }
}
