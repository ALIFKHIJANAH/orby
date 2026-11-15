import Foundation
import NotchShared

/// Builds the commands that focus a session's exact tab/pane in terminals that expose an API.
/// The app runs them; keeping them here makes them testable without the terminals installed.
public enum TerminalJump {
    public static let ghosttyBundleID = "com.mitchellh.ghostty"
    public static let cmuxDefaultSocket = "/tmp/cmux.sock"

    /// `zellij --session <name> action focus-pane-id terminal_<n>`. Needs both the session
    /// (the server holds the layout) and the pane, which ZELLIJ_PANE_ID gives as a bare number.
    public static func zellijArgs(_ t: TerminalContext) -> [String]? {
        guard let session = t.zellijSession, !session.isEmpty,
            let pane = t.zellijPane, !pane.isEmpty, pane.allSatisfy(\.isASCII), pane.allSatisfy(\.isNumber)
        else { return nil }
        return ["--session", session, "action", "focus-pane-id", "terminal_\(pane)"]
    }

    /// Newline-terminated JSON-RPC requests for cmux's socket: select the workspace first so a
    /// surface in a background workspace becomes visible, then focus the surface itself.
    public static func cmuxRequests(_ t: TerminalContext) -> [String]? {
        guard let surface = t.cmuxSurface, !surface.isEmpty else { return nil }
        var requests: [[String: Any]] = []
        if let ws = t.cmuxWorkspace, !ws.isEmpty {
            requests.append(["id": "orby-ws", "method": "workspace.select", "params": ["workspace_id": ws]])
        }
        var focus: [String: Any] = ["surface_id": surface]
        if let ws = t.cmuxWorkspace, !ws.isEmpty { focus["workspace_id"] = ws }
        requests.append(["id": "orby-surface", "method": "surface.focus", "params": focus])
        return requests.compactMap { r in
            (try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys, .withoutEscapingSlashes]))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    public static func cmuxSocketPath(_ t: TerminalContext) -> String {
        t.cmuxSocket.flatMap { $0.isEmpty ? nil : $0 } ?? cmuxDefaultSocket
    }

    /// A cmux reply line counts only when it says `"ok": true`.
    public static func cmuxReplyOK(_ line: String) -> Bool {
        guard let v = try? JSONValue.decode(Data(line.utf8)), case .object(let o) = v, case .bool(let ok)? = o["ok"] else {
            return false
        }
        return ok
    }

    /// Ghostty 1.3's AppleScript (a preview API) can focus a terminal, but Ghostty exports no
    /// per-terminal id to the shell. Match on working directory and focus only when exactly one
    /// terminal is there; with several, picking one could land on the wrong tab.
    public static func ghosttyScript(cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        let dir = appleScriptEscape(cwd)
        let alt = appleScriptEscape(cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd + "/")
        return """
            tell application id "\(ghosttyBundleID)"
              set matches to every terminal whose working directory is "\(dir)" or working directory is "\(alt)"
              if (count of matches) is 1 then focus (item 1 of matches)
              activate
            end tell
            """
    }

    public static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Sends one request per connection and reads the reply line. Short timeouts: a jump that
    /// hangs is worse than one that falls back to activating the app.
    public static func sendLine(_ line: String, toSocket path: String, timeout: TimeInterval = 1) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return nil }

        let out = Array((line.hasSuffix("\n") ? line : line + "\n").utf8)
        guard out.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == out.count else { return nil }

        var reply = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !reply.contains(0x0A) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply.append(buf, count: n)
        }
        guard !reply.isEmpty else { return nil }
        return String(decoding: reply.prefix { $0 != 0x0A }, as: UTF8.self)
    }
}
