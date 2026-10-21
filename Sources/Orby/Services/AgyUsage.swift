import Darwin
import Foundation
import NotchCore
import NotchShared

/// Opt-in: `agy -p "/usage" --output-format json`. agy answers it without an agent turn (no
/// quota spent, no conversation saved) but asks Google with the user's own login.
enum AgyUsage {
    enum Failure: LocalizedError {
        case notFound, tooOld(String), timedOut, failed(Int32), unreadable
        var errorDescription: String? {
            switch self {
            case .notFound: "agy not found in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin or PATH."
            case .tooOld(let v): "agy \(v) is too old for `agy -p /usage`; run `agy update`."
            case .timedOut: "`agy /usage` didn't answer within 20 seconds."
            case .failed(let code): "`agy /usage` exited with status \(code). Is agy signed in?"
            case .unreadable: "Unrecognized `agy /usage` output."
            }
        }
    }

    static func binary(home: URL = NotchPaths.homeDirectory, path: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
        let dirs = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (path ?? "").split(separator: ":").map(String.init)
        return dirs.map { URL(fileURLWithPath: $0).appendingPathComponent("agy") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func fetch(now: Date = Date()) -> Result<AntigravityQuota, Failure> {
        guard let agy = binary() else { return .failure(.notFound) }
        guard let version = run(agy, ["--version"], timeout: 5), version.status == 0 else { return .failure(.notFound) }
        let v = String(decoding: version.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard AntigravityQuota.supportsHeadlessUsage(version: v) else { return .failure(.tooOld(v)) }
        guard let result = run(agy, ["-p", "/usage", "--output-format", "json"], timeout: 20) else { return .failure(.timedOut) }
        guard result.status == 0 else { return .failure(.failed(result.status)) }
        guard let json = try? JSONValue.decode(result.out), let quota = AntigravityQuota.usageCommand(json, now: now) else {
            return .failure(.unreadable)
        }
        return .success(quota)
    }

    /// No shell, stdin closed, killed after `timeout`. nil: timed out or couldn't start.
    private static func run(_ exe: URL, _ args: [String], timeout: TimeInterval) -> (status: Int32, out: Data)? {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        let lock = NSLock()
        var out = Data()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            lock.withLock { out.append(chunk) }
        }
        guard (try? p.run()) != nil else { return nil }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        // Whatever is still in the pipe, without waiting on children that may hold it open.
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            lock.withLock { out.append(contentsOf: buf[0..<n]) }
        }
        return (p.terminationStatus, lock.withLock { out })
    }
}
