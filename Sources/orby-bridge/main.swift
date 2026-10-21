// Hook bridge: invoked by an agent's hook config, forwards the hook input to Orby
// over a Unix socket and, for permission requests, prints the decision the user picked.
// It must never break the agent: every failure path exits 0 with empty stdout (or, for
// Antigravity, which requires a reply, the passthrough answer).
import Darwin
import Foundation
import NotchShared

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func connectSocket(path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard ok == 0 else { close(fd); return nil }
    return fd
}

func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw -> Bool in
        var offset = 0
        while offset < raw.count {
            let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
            if n <= 0 { return false }
            offset += n
        }
        return true
    }
}

func readLine(_ fd: Int32) -> Data? {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let n = read(fd, &chunk, chunk.count)
        if n <= 0 { return buffer.isEmpty ? nil : buffer }
        buffer.append(contentsOf: chunk[0..<n])
        if let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) { return buffer[..<nl] }
    }
}

let source = argument("--source") ?? "claude"
// Antigravity doesn't name the event in its hook input, so its hook config passes it.
let eventArgument = argument("--event")

func finish(_ stdout: JSONValue? = nil) -> Never {
    var reply = stdout
    if reply == nil, source == "antigravity" { reply = antigravityPassthrough(event: eventArgument ?? "") }
    if let reply, let out = try? reply.encoded() {
        FileHandle.standardOutput.write(out)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(0)
}

if CommandLine.arguments.contains("--statusline") { runStatusLine() }

// Run by hand in a terminal: don't hang waiting for stdin.
if isatty(STDIN_FILENO) != 0 {
    FileHandle.standardError.write(
        Data("orby-bridge: expects hook JSON on stdin (--source claude|codex|antigravity|opencode|pi|commandcode|qwen [--event name], or --statusline --source antigravity [--wrap command])\n".utf8))
    exit(0)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard var payload = try? JSONValue.decode(input) else { finish() }
if let eventArgument, payload["hook_event_name"] == nil, var obj = payload.object {
    obj["hook_event_name"] = .string(eventArgument)
    payload = .object(obj)
}

let env = ProcessInfo.processInfo.environment
var terminalEnv: [String: String] = [:]
for key in terminalEnvKeys { if let v = env[key], !v.isEmpty { terminalEnv[key] = v } }
if let pwd = env["PWD"] { terminalEnv["PWD"] = pwd }

let chain = ProcessTree.chain(from: getppid())
let agent = ProcessTree.agentProcess(in: chain)
let eventName = payload["hook_event_name"]?.string ?? ""
let expectsReply = blockingEvents.contains(eventName)

let envelope = BridgeEnvelope(
    source: source,
    payload: payload,
    env: terminalEnv,
    agentPID: agent?.pid,
    tty: agent.flatMap { ProcessTree.info(pid: $0.pid)?.tty },
    processChain: chain,
    expectsReply: expectsReply
)

guard var line = try? wireJSONEncoder.encode(envelope),
    let fd = connectSocket(path: NotchPaths.socket.path)
else { finish() }  // App not running: stay silent so the agent uses its own prompt.
line.append(UInt8(ascii: "\n"))

var sendTimeout = timeval(tv_sec: 3, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
guard writeAll(fd, line) else { close(fd); finish() }

var decision: JSONValue?
if expectsReply {
    // Block until the user decides in the notch. The agent's hook timeout bounds this,
    // and if the user answers in the terminal instead, the agent kills us and the app sees EOF.
    if let replyData = readLine(fd), let reply = try? wireJSONDecoder.decode(BridgeReply.self, from: replyData) {
        decision = reply.stdout
    }
}
close(fd)
finish(decision)
