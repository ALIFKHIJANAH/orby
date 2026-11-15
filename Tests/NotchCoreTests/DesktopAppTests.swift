import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

/// Process chains as the bridge sees them (nearest first). The Claude Desktop paths match the
/// installed app (5.1231.2); the helper hop and the Codex.app layout are assumptions.
private let bundledCLI = "/Users/me/Library/Application Support/Claude/claude-code/2.1.321/ddbdf2b334e1/claude.app/Contents/MacOS/claude"
private let claudeDesktopChain = [
    ProcessEntry(pid: 500, name: "sh", path: "/bin/sh"),
    ProcessEntry(pid: 501, name: "claude", path: bundledCLI),
    ProcessEntry(pid: 400, name: "Claude Helper", path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"),
    ProcessEntry(pid: 300, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude"),
]
private let codexDesktopChain = [
    ProcessEntry(pid: 600, name: "sh", path: "/bin/sh"),
    ProcessEntry(pid: 601, name: "codex", path: "/Applications/Codex.app/Contents/Resources/codex"),
    ProcessEntry(pid: 350, name: "Codex", path: "/Applications/Codex.app/Contents/MacOS/Codex"),
]
private let terminalChain = [
    ProcessEntry(pid: 700, name: "sh", path: "/bin/sh"),
    ProcessEntry(pid: 701, name: "claude", path: "/opt/homebrew/bin/claude"),
    ProcessEntry(pid: 702, name: "zsh", path: "/bin/zsh"),
    ProcessEntry(pid: 703, name: "Terminal", path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
]

private func envelope(
    source: String = "claude", event: String = "SessionStart", session: String = "s1", env: [String: String] = [:],
    chain: [ProcessEntry] = [], agentPID: Int32? = nil
) -> BridgeEnvelope {
    let payload: JSONValue = ["hook_event_name": .string(event), "session_id": .string(session), "cwd": "/tmp/proj"]
    return BridgeEnvelope(source: source, payload: payload, env: env, agentPID: agentPID, processChain: chain)
}

@Suite struct DesktopDetectionTests {
    @Test func claudeDesktopFromProcessTreeUsesTheAppNotItsBundledCLI() {
        let host = DesktopApp.detect(env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], chain: claudeDesktopChain)
        #expect(host == DesktopHost(app: .claude, pid: 300, bundlePath: "/Applications/Claude.app"))
    }

    @Test func claudeDesktopFromEntrypointAlone() {
        #expect(DesktopApp.detect(env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], chain: [])?.app == .claude)
        #expect(DesktopApp.detect(env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop-3p"], chain: [])?.app == .claude)
        #expect(DesktopApp.detect(env: ["CLAUDE_CODE_ENTRYPOINT": "cli"], chain: []) == nil)
    }

    @Test func desktopFromBundleIdentifierEnv() {
        #expect(DesktopApp.detect(env: ["__CFBundleIdentifier": "com.anthropic.claudefordesktop"], chain: [])?.app == .claude)
        let codex = DesktopApp.detect(env: ["__CFBundleIdentifier": "com.openai.codex"], chain: [])
        #expect(codex == DesktopHost(app: .codex))
    }

    @Test func codexDesktopFromProcessTree() {
        #expect(DesktopApp.detect(env: [:], chain: codexDesktopChain) == DesktopHost(app: .codex, pid: 350, bundlePath: "/Applications/Codex.app"))
    }

    @Test func terminalSessionsAreNotDesktop() {
        #expect(DesktopApp.detect(env: ["TERM_PROGRAM": "Apple_Terminal"], chain: terminalChain) == nil)
        #expect(DesktopApp.detect(env: ["__CFBundleIdentifier": "com.microsoft.VSCode"], chain: []) == nil)
        // The bundled CLI alone (lowercase claude.app) isn't Claude Desktop.
        #expect(DesktopApp.detect(env: [:], chain: [ProcessEntry(pid: 1, name: "claude", path: bundledCLI)]) == nil)
    }

    @Test func terminalContextPointsAtTheDesktopApp() {
        let t = TerminalContext(envelope: envelope(env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], chain: claudeDesktopChain, agentPID: 501))
        #expect(t.desktop?.app == .claude)
        #expect(t.bundleID == "com.anthropic.claudefordesktop")
        #expect(t.appBundlePath == "/Applications/Claude.app")
        #expect(t.tty == nil)
        // A later event that lost the env keeps what was learned.
        #expect(TerminalContext().merged(over: t).desktop?.pid == 300)
    }

    @Test func protocolForwardsTheEntrypoint() {
        #expect(terminalEnvKeys.contains("CLAUDE_CODE_ENTRYPOINT"))
    }
}

@Suite struct DesktopLivenessTests {
    @Test func desktopSessionOutlivesItsPerTurnProcess() {
        var engine = SessionEngine()
        _ = engine.handle(envelope(source: "codex", session: "t1", chain: codexDesktopChain, agentPID: 601))
        // The CLI (601) exited after the turn; Codex.app (350) is still up.
        _ = engine.prune(doneTTL: 3600, isAlive: { $0 == 350 })
        #expect(engine.sessions["codex:t1"] != nil)
        _ = engine.prune(doneTTL: 3600, isAlive: { _ in false })
        #expect(engine.sessions.isEmpty)
    }

    @Test func desktopWithoutAPIDFollowsTheRunningApp() {
        let t = TerminalContext(envelope: envelope(env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], agentPID: 42))
        #expect(!t.hostIsGone(isAlive: { _ in false }, isAppRunning: { $0 == "com.anthropic.claudefordesktop" }))
        #expect(t.hostIsGone(isAlive: { _ in true }, isAppRunning: { _ in false }))
    }

    @Test func terminalSessionsStillFollowTheAgentPID() {
        let t = TerminalContext(envelope: envelope(chain: terminalChain, agentPID: 701))
        #expect(t.hostIsGone(isAlive: { _ in false }, isAppRunning: { _ in true }))
        #expect(!t.hostIsGone(isAlive: { $0 == 701 }, isAppRunning: { _ in false }))
        #expect(!TerminalContext().hostIsGone(isAlive: { _ in false }, isAppRunning: { _ in false }))
    }

    @Test func approvalsWorkTheSameForDesktopSessions() {
        var engine = SessionEngine()
        var e = envelope(event: "PermissionRequest", env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], chain: claudeDesktopChain)
        if var obj = e.payload.object { obj["tool_name"] = "Bash"; obj["tool_input"] = ["command": "ls"]; e.payload = .object(obj) }
        e.expectsReply = true
        _ = engine.handle(e)
        #expect(engine.pending.count == 1)
        #expect(engine.sessions["claude:s1"]?.phase == .needsApproval)
    }
}

@Suite struct DesktopJumpTests {
    private func session(_ e: BridgeEnvelope) -> AgentSession {
        var engine = SessionEngine()
        _ = engine.handle(e)
        return engine.sessions.values.first!
    }

    @Test func codexJumpsToTheThread() {
        let s = session(envelope(source: "codex", session: "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b", chain: codexDesktopChain))
        #expect(s.desktopJumpTarget == .url(URL(string: "codex://threads/019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b")!))
    }

    @Test func codexWithAnOddIDJustActivates() {
        #expect(AgentSession.codexThreadURL("a/b?c") == nil)
        #expect(AgentSession.codexThreadURL("") == nil)
        let s = session(envelope(source: "codex", session: "../x", env: ["__CFBundleIdentifier": "com.openai.codex"]))
        #expect(s.desktopJumpTarget == .activate(bundleID: "com.openai.codex"))
    }

    @Test func claudeDesktopActivatesTheApp() {
        let s = session(envelope(env: ["CLAUDE_CODE_ENTRYPOINT": "claude-desktop"], chain: claudeDesktopChain))
        #expect(s.desktopJumpTarget == .activate(bundleID: "com.anthropic.claudefordesktop"))
    }

    @Test func terminalSessionsHaveNoDesktopTarget() {
        #expect(session(envelope(chain: terminalChain)).desktopJumpTarget == nil)
    }
}
