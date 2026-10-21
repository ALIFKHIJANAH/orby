// `--statusline`: run as Antigravity CLI's statusLine command. Relays the payload to Orby
// fire-and-forget, then prints a status line: the wrapped user command's output when
// Orby wrapped one (`--wrap`), otherwise a short summary of its own.
import Darwin
import Foundation
import NotchShared

func runStatusLine() -> Never {
    // A wrapped command that never reads stdin must not kill us when we write to it.
    signal(SIGPIPE, SIG_IGN)
    let input = isatty(STDIN_FILENO) != 0 ? Data() : FileHandle.standardInput.readDataToEndOfFile()
    let payload = try? JSONValue.decode(input)
    if let payload { relayStatusLine(payload) }
    if let wrapped = argument("--wrap"), !wrapped.isEmpty {
        FileHandle.standardOutput.write(runWrapped(wrapped, input: input))
    } else if let payload {
        let line = AntigravityStatusLine.summary(payload)
        if !line.isEmpty { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
    }
    exit(0)
}

/// Never blocks the status line for long: short socket timeouts, silent when the app isn't running.
func relayStatusLine(_ payload: JSONValue) {
    guard var obj = payload.object else { return }
    obj["hook_event_name"] = .string(AntigravityStatusLine.eventName)
    let envelope = BridgeEnvelope(source: argument("--source") ?? "antigravity", payload: .object(obj))
    guard var line = try? wireJSONEncoder.encode(envelope), let fd = connectSocket(path: NotchPaths.socket.path) else { return }
    line.append(UInt8(ascii: "\n"))
    var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = writeAll(fd, line)
    close(fd)
}

/// The user's own status line command, fed the same stdin. Its stdout is what agy shows.
func runWrapped(_ command: String, input: Data) -> Data {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    let stdin = Pipe(), stdout = Pipe()
    p.standardInput = stdin
    p.standardOutput = stdout
    guard (try? p.run()) != nil else { return Data() }
    DispatchQueue.global().async {
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
    }
    // A hung command must not hang the status line.
    let pid = p.processIdentifier
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { kill(pid, SIGKILL) }
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return out
}
