import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func context(_ env: [String: String]) -> TerminalContext {
    TerminalContext(envelope: BridgeEnvelope(source: "claude", payload: .object([:]), env: env))
}

@Suite struct TerminalJumpTests {
    @Test func bridgeForwardsJumpEnv() {
        for key in ["ZELLIJ_SESSION_NAME", "ZELLIJ_PANE_ID", "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH"] {
            #expect(terminalEnvKeys.contains(key))
        }
    }

    @Test func zellijFocusesThePaneInItsSession() {
        let t = context(["ZELLIJ": "0", "ZELLIJ_SESSION_NAME": "brave-cat", "ZELLIJ_PANE_ID": "3"])
        #expect(TerminalJump.zellijArgs(t) == ["--session", "brave-cat", "action", "focus-pane-id", "terminal_3"])
    }

    @Test func zellijNeedsSessionAndNumericPane() {
        #expect(TerminalJump.zellijArgs(context(["ZELLIJ_PANE_ID": "3"])) == nil)
        #expect(TerminalJump.zellijArgs(context(["ZELLIJ_SESSION_NAME": "s"])) == nil)
        #expect(TerminalJump.zellijArgs(context(["ZELLIJ_SESSION_NAME": "s", "ZELLIJ_PANE_ID": "3; rm"])) == nil)
        #expect(TerminalJump.zellijArgs(context(["ZELLIJ_SESSION_NAME": "s", "ZELLIJ_PANE_ID": "٣"])) == nil)
    }

    @Test func cmuxSelectsWorkspaceThenFocusesSurface() throws {
        let t = context(["TERM_PROGRAM": "ghostty", "CMUX_WORKSPACE_ID": "ws-1", "CMUX_SURFACE_ID": "sf-2"])
        let lines = try #require(TerminalJump.cmuxRequests(t))
        #expect(lines == [
            #"{"id":"orby-ws","method":"workspace.select","params":{"workspace_id":"ws-1"}}"#,
            #"{"id":"orby-surface","method":"surface.focus","params":{"surface_id":"sf-2","workspace_id":"ws-1"}}"#,
        ])
        #expect(TerminalJump.cmuxSocketPath(t) == "/tmp/cmux.sock")
    }

    @Test func cmuxSurfaceAloneAndCustomSocket() {
        let t = context(["CMUX_SURFACE_ID": "sf", "CMUX_SOCKET_PATH": "/tmp/x.sock"])
        #expect(TerminalJump.cmuxRequests(t) == [#"{"id":"orby-surface","method":"surface.focus","params":{"surface_id":"sf"}}"#])
        #expect(TerminalJump.cmuxSocketPath(t) == "/tmp/x.sock")
        #expect(TerminalJump.cmuxRequests(context(["CMUX_WORKSPACE_ID": "ws"])) == nil)
    }

    @Test func cmuxReplyMustBeOK() {
        #expect(TerminalJump.cmuxReplyOK(#"{"id":"a","ok":true,"result":{}}"#))
        #expect(!TerminalJump.cmuxReplyOK(#"{"id":"a","ok":false,"error":{"message":"denied"}}"#))
        #expect(!TerminalJump.cmuxReplyOK("not json"))
    }

    @Test func ghosttyFocusesTheOnlyTerminalInTheFolder() throws {
        let script = try #require(TerminalJump.ghosttyScript(cwd: #"/Users/me/My "app""#))
        #expect(script.contains(#"tell application id "com.mitchellh.ghostty""#))
        #expect(script.contains(#"working directory is "/Users/me/My \"app\"" or working directory is "/Users/me/My \"app\"/""#))
        #expect(script.contains("if (count of matches) is 1 then focus (item 1 of matches)"))
        #expect(TerminalJump.ghosttyScript(cwd: "") == nil)
    }

    @Test func mergeKeepsLearnedJumpIDs() {
        let old = context(["ZELLIJ_SESSION_NAME": "s", "ZELLIJ_PANE_ID": "1", "CMUX_SURFACE_ID": "sf", "CMUX_WORKSPACE_ID": "ws"])
        let m = context([:]).merged(over: old)
        #expect(m.zellijSession == "s" && m.zellijPane == "1" && m.cmuxSurface == "sf" && m.cmuxWorkspace == "ws")
    }

    @Test func sendLineRoundTripsOverAUnixSocket() throws {
        let path = NSTemporaryDirectory() + "orby-jump-\(UUID().uuidString.prefix(8)).sock"
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(server); unlink(path) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let b = Array(path.utf8); raw.copyBytes(from: b); raw[b.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(bound == 0 && listen(server, 1) == 0)
        let thread = Thread {
            let c = accept(server, nil, nil)
            var buf = [UInt8](repeating: 0, count: 256)
            _ = read(c, &buf, buf.count)
            let reply = Array(#"{"id":"orby-surface","ok":true}"#.utf8) + [0x0A]
            _ = reply.withUnsafeBytes { write(c, $0.baseAddress, $0.count) }
            close(c)
        }
        thread.start()
        let reply = try #require(TerminalJump.sendLine("{}", toSocket: path))
        #expect(TerminalJump.cmuxReplyOK(reply))
        #expect(TerminalJump.sendLine("{}", toSocket: path + ".missing") == nil)
    }
}
