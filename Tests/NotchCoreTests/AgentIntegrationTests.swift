import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func hook(
    _ event: String, source: String, session: String = "s1", extra: [String: JSONValue] = [:], expectsReply: Bool = false,
    id: String = UUID().uuidString
) -> BridgeEnvelope {
    var payload: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": .string(session), "cwd": "/tmp/proj"]
    payload.merge(extra) { _, new in new }
    return BridgeEnvelope(id: id, source: source, payload: .object(payload), expectsReply: expectsReply)
}

private func tempHome() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

private func mkdir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

// MARK: Installers

@Suite struct QwenInstallerTests {
    let foreign = HookInstallerTests().foreign

    @Test func installKeepsOtherHooksAndIsIdempotent() throws {
        let out = HookInstaller.installing(.qwen, into: foreign)
        #expect(out["model"]?.string == "opus")
        #expect(out["hooks"]?["Stop"]?.array?.first?["hooks"]?.array?.first?["command"]?.string == "afplay done.wav")
        #expect(HookInstaller.isInstalled(.qwen, in: out))
        let perm = try #require(out["hooks"]?["PermissionRequest"]?.array?.last?["hooks"]?.array?.first)
        #expect(perm["command"]?.string?.contains("--source qwen") == true)
        // Qwen reads 1000 and up as milliseconds.
        #expect(perm["timeout"]?.int == 600)
        #expect(HookInstaller.installing(.qwen, into: out) == out)
        #expect(HookInstaller.uninstalling(from: out) == foreign)
    }

    @Test func applyNeedsQwenDirectoryAndRestoresOnRemove() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(HookInstaller.status(.qwen, home: home) == .agentMissing)
        try mkdir(home.appendingPathComponent(".qwen"))
        #expect(HookInstaller.status(.qwen, home: home) == .notInstalled)
        let url = home.appendingPathComponent(".qwen/settings.json")
        try foreign.encoded().write(to: url)

        let backups = home.appendingPathComponent("b")
        let backup = try #require(try HookInstaller.apply(.qwen, install: true, home: home, backupDir: backups))
        #expect(try JSONValue.decode(Data(contentsOf: backup)) == foreign)
        #expect(HookInstaller.status(.qwen, home: home) == .installed)
        try HookInstaller.apply(.qwen, install: false, home: home, backupDir: backups)
        #expect(try JSONValue.decode(Data(contentsOf: url)) == foreign)
    }
}

@Suite struct CommandCodeInstallerTests {
    let foreign: JSONValue = [
        "theme": "dark",
        "hooks": ["PreToolUse": [["matcher": "shell", "hooks": [["type": "command", "command": "./guard.sh", "timeout": 5]]]]],
    ]

    @Test func installsHooksAndModWithoutTouchingOthers() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".commandcode")
        try mkdir(dir.appendingPathComponent("mods"))
        let settings = dir.appendingPathComponent("settings.json")
        try foreign.encoded().write(to: settings)
        let otherMod = dir.appendingPathComponent("mods/mine.ts")
        try Data("export default () => {}".utf8).write(to: otherMod)
        #expect(HookInstaller.status(.commandcode, home: home) == .notInstalled)

        let backups = home.appendingPathComponent("b")
        try HookInstaller.apply(.commandcode, install: true, home: home, backupDir: backups)
        #expect(HookInstaller.status(.commandcode, home: home) == .installed)
        let root = try JSONValue.decode(Data(contentsOf: settings))
        #expect(root["theme"]?.string == "dark")
        #expect(root["hooks"]?["PreToolUse"]?.array?.first == foreign["hooks"]?["PreToolUse"]?.array?.first)
        // Command Code's own hook events only, and SessionStart/Stop must not carry a matcher.
        #expect(Set(root["hooks"]?.object?.keys.map { $0 } ?? []) == ["SessionStart", "PreToolUse", "PostToolUse", "Stop"])
        #expect(root["hooks"]?["Stop"]?.array?.first?["matcher"] == nil)
        let mod = try String(contentsOf: dir.appendingPathComponent("mods/orby.ts"), encoding: .utf8)
        #expect(mod == PluginInstaller.source(for: .commandcode))

        // Idempotent.
        try HookInstaller.apply(.commandcode, install: true, home: home, backupDir: backups)
        #expect(try JSONValue.decode(Data(contentsOf: settings)) == root)

        try HookInstaller.apply(.commandcode, install: false, home: home, backupDir: backups)
        #expect(try JSONValue.decode(Data(contentsOf: settings)) == foreign)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("mods/orby.ts").path))
        #expect(FileManager.default.fileExists(atPath: otherMod.path))
        #expect(HookInstaller.status(.commandcode, home: home) == .notInstalled)
    }

    @Test func missingModIsPartial() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".commandcode"))
        try HookInstaller.apply(.commandcode, install: true, home: home, backupDir: home.appendingPathComponent("b"))
        try FileManager.default.removeItem(at: home.appendingPathComponent(".commandcode/mods/orby.ts"))
        #expect(HookInstaller.status(.commandcode, home: home) == .partial)
    }
}

@Suite struct PluginInstallerTests {
    static let targets: [HookTarget] = [.opencode, .pi]

    /// The directory each agent's plugins live in, under `home`.
    func pluginDir(_ target: HookTarget, home: URL) -> URL { target.pluginURL(home: home)!.deletingLastPathComponent() }

    @Test(arguments: targets) func installIsIdempotentAndKeepsOtherPlugins(target: HookTarget) throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(HookInstaller.status(target, home: home) == .agentMissing)
        let dir = pluginDir(target, home: home)
        try mkdir(dir)
        let other = dir.appendingPathComponent("other-tool.js")
        try Data("export const Other = async () => ({})".utf8).write(to: other)
        #expect(HookInstaller.status(target, home: home) == .notInstalled)

        let backups = home.appendingPathComponent("b")
        #expect(try HookInstaller.apply(target, install: true, home: home, backupDir: backups) == nil)
        #expect(HookInstaller.status(target, home: home) == .installed)
        let url = target.pluginURL(home: home)!
        #expect(try String(contentsOf: url, encoding: .utf8) == PluginInstaller.source(for: target))
        // Nothing changed, so nothing to back up.
        #expect(try HookInstaller.apply(target, install: true, home: home, backupDir: backups) == nil)
        #expect(!FileManager.default.fileExists(atPath: backups.path))

        let backup = try #require(try HookInstaller.apply(target, install: false, home: home, backupDir: backups))
        #expect(try String(contentsOf: backup, encoding: .utf8) == PluginInstaller.source(for: target))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: other, encoding: .utf8) == "export const Other = async () => ({})")
        #expect(HookInstaller.status(target, home: home) == .notInstalled)
    }

    @Test(arguments: targets) func outdatedPluginIsRepaired(target: HookTarget) throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(pluginDir(target, home: home))
        let url = target.pluginURL(home: home)!
        try Data((PluginInstaller.header + "\n// an older version\n").utf8).write(to: url)
        #expect(HookInstaller.status(target, home: home) == .partial)
        #expect(try HookInstaller.apply(target, install: true, home: home, backupDir: home.appendingPathComponent("b")) != nil)
        #expect(HookInstaller.status(target, home: home) == .installed)
    }

    @Test(arguments: targets) func neverTouchesAForeignFileWithOurName(target: HookTarget) throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(pluginDir(target, home: home))
        let url = target.pluginURL(home: home)!
        try Data("// someone else's orby plugin".utf8).write(to: url)
        guard case .unreadable = HookInstaller.status(target, home: home) else {
            Issue.record("expected unreadable")
            return
        }
        for install in [true, false] {
            #expect(throws: HookInstaller.InstallError.self) {
                try HookInstaller.apply(target, install: install, home: home, backupDir: home)
            }
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "// someone else's orby plugin")
    }

    @Test func pluginLocations() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(HookTarget.opencode.pluginURL(home: home)?.path == "/Users/x/.config/opencode/plugins/orby.js")
        #expect(HookTarget.pi.pluginURL(home: home)?.path == "/Users/x/.pi/agent/extensions/orby.ts")
        #expect(HookTarget.commandcode.pluginURL(home: home)?.path == "/Users/x/.commandcode/mods/orby.ts")
        #expect(HookTarget.opencode.configURL(home: home) == HookTarget.opencode.pluginURL(home: home))
        #expect(!HookTarget.opencode.hasHookConfig && !HookTarget.pi.hasHookConfig && HookTarget.commandcode.hasHookConfig)
        // The OpenCode curl installer's folder counts as installed too.
        #expect(HookTarget.opencode.agentDirectories(home: home).map(\.path).contains("/Users/x/.opencode"))
    }

    @Test func pluginSourcesCarryTheMarker() throws {
        for target in [HookTarget.opencode, .pi, .commandcode] {
            let source = try #require(PluginInstaller.source(for: target))
            #expect(PluginInstaller.isOurs(source))
            #expect(source.contains(HookInstaller.marker))
            #expect(source.contains(#"["--source", "\#(target.rawValue)"]"#))
        }
    }
}

// MARK: Event mapping

@Suite struct AgentEventTests {
    @Test func qwenApprovalUsesClaudeToolNames() {
        var engine = SessionEngine()
        let input: JSONValue = ["command": "npm test", "description": "Run the tests"]
        _ = engine.handle(hook("UserPromptSubmit", source: "qwen", extra: ["prompt": "Fix it"]))
        let out = engine.handle(
            hook("PermissionRequest", source: "qwen", extra: ["tool_name": "run_shell_command", "tool_input": input], expectsReply: true, id: "q1"))
        #expect(out.cue == .approval)
        let request = engine.pending.first
        #expect(request?.toolName == "Bash")
        #expect(request?.sessionKey == "qwen:s1")
        #expect(engine.sessions["qwen:s1"]?.agent == .qwen)
        #expect(engine.sessions["qwen:s1"]?.phase == .needsApproval)
        // Answered in Qwen's terminal: the tool ran.
        let post = engine.handle(hook("PostToolUse", source: "qwen", extra: ["tool_name": "run_shell_command", "tool_input": input]))
        #expect(post.cancelledRequests == ["q1"])
    }

    @Test func toolArgumentsAreRenamed() {
        let p: JSONValue = [
            "tool_name": "edit", "tool_input": ["filePath": "/tmp/proj/App.swift", "oldString": "a", "newString": "b"],
        ]
        let out = ToolAliases.normalized(p)
        #expect(out["tool_name"]?.string == "Edit")
        #expect(out["tool_input"] == ["file_path": "/tmp/proj/App.swift", "old_string": "a", "new_string": "b"])
        #expect(ToolAliases.normalized(["tool_name": "mcp__x__y"]) == ["tool_name": "mcp__x__y"])
        #expect(ToolAliases.normalized(["tool_name": "read", "tool_input": ["path": "/a/b.md"]])["tool_input"] == ["file_path": "/a/b.md"])
    }

    @Test func openCodeSessionWithSubagentAndQuestion() {
        var engine = SessionEngine()
        let key = "opencode:ses1"
        _ = engine.handle(hook("SessionStart", source: "opencode", session: "ses1"))
        _ = engine.handle(hook("UserPromptSubmit", source: "opencode", session: "ses1", extra: ["prompt": "Add a test", "model": "gpt-5"]))
        #expect(engine.sessions[key]?.agent == .opencode)
        #expect(engine.sessions[key]?.model == "gpt-5")

        _ = engine.handle(
            hook("PreToolUse", source: "opencode", session: "ses1", extra: ["tool_name": "write", "tool_input": ["filePath": "/tmp/proj/a.swift", "content": "x"]]))
        #expect(engine.sessions[key]?.currentTool == "Writing a.swift")

        // A subagent session reports into its parent with agent_id.
        _ = engine.handle(hook("SubagentStart", source: "opencode", session: "ses1", extra: ["agent_id": "ses2"]))
        #expect(engine.sessions[key]?.activeSubagents == 1)
        _ = engine.handle(
            hook("PermissionRequest", source: "opencode", session: "ses1", extra: [
                "agent_id": "ses2", "tool_name": "bash", "tool_input": ["command": "rm -rf build"],
                "permission_suggestions": [["type": "addRules", "rules": [["toolName": "bash", "ruleContent": "rm *"]]]],
            ], expectsReply: true, id: "per1"))
        #expect(engine.pending.first?.agentScope == "ses2")
        #expect(engine.pending.first?.suggestions.count == 1)
        // A tool from the main agent doesn't release the subagent's prompt.
        _ = engine.handle(hook("PreToolUse", source: "opencode", session: "ses1", extra: ["tool_name": "read", "tool_input": ["filePath": "/a"]]))
        #expect(engine.pending.map(\.id) == ["per1"])
        _ = engine.resolve(requestID: "per1")

        let question: JSONValue = ["questions": [["question": "Which DB?", "options": [["label": "SQLite"], ["label": "Postgres"]]]]]
        _ = engine.handle(
            hook("PermissionRequest", source: "opencode", session: "ses1", extra: ["tool_name": "AskUserQuestion", "tool_input": question],
                 expectsReply: true, id: "que1"))
        #expect(engine.pending.first?.kind == .question)
        #expect(engine.pending.first?.questions.first?.options.map(\.label) == ["SQLite", "Postgres"])
        #expect(engine.sessions[key]?.phase == .needsAnswer)

        let stop = engine.handle(hook("Stop", source: "opencode", session: "ses1"))
        #expect(stop.cancelledRequests == ["que1"])
        #expect(engine.sessions[key]?.phase == .done)
        _ = engine.handle(hook("SessionEnd", source: "opencode", session: "ses1"))
        #expect(engine.sessions[key] == nil)
    }

    @Test func openCodeErrorAndInterrupt() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", source: "opencode", session: "ses1"))
        _ = engine.handle(hook("StopFailure", source: "opencode", session: "ses1", extra: ["error": "Rate limited"]))
        #expect(engine.sessions["opencode:ses1"]?.phase == .error)
        #expect(engine.sessions["opencode:ses1"]?.lastMessage == "Rate limited")
        _ = engine.handle(hook("Interrupt", source: "opencode", session: "ses1"))
        #expect(engine.sessions["opencode:ses1"]?.phase == .done)
    }

    @Test func piIsStatusOnly() {
        var engine = SessionEngine()
        let key = "pi:p1"
        _ = engine.handle(hook("SessionStart", source: "pi", session: "p1"))
        _ = engine.handle(hook("UserPromptSubmit", source: "pi", session: "p1", extra: ["prompt": "Refactor"]))
        _ = engine.handle(hook("PreToolUse", source: "pi", session: "p1", extra: ["tool_name": "bash", "tool_input": ["command": "npm test"]]))
        #expect(engine.sessions[key]?.agent == .pi)
        #expect(engine.sessions[key]?.currentTool == "Running tests")
        _ = engine.handle(hook("PostToolUseFailure", source: "pi", session: "p1", extra: ["tool_name": "bash"]))
        #expect(engine.sessions[key]?.phase == .thinking)
        _ = engine.handle(hook("Stop", source: "pi", session: "p1"))
        #expect(engine.sessions[key]?.phase == .done)
        #expect(engine.pending.isEmpty)
    }

    @Test func commandCodeHooksAndModShareASession() {
        var engine = SessionEngine()
        let key = "commandcode:c1"
        _ = engine.handle(hook("SessionStart", source: "commandcode", session: "c1"))
        _ = engine.handle(
            hook("PreToolUse", source: "commandcode", session: "c1", extra: ["tool_name": "edit_file", "tool_input": ["file_path": "/tmp/proj/x.ts"]]))
        #expect(engine.sessions[key]?.currentTool == "Editing x.ts")
        // From the mod's onPermissionRequest.
        _ = engine.handle(
            hook("PermissionRequest", source: "commandcode", session: "c1", extra: ["tool_name": "shell_command", "tool_input": ["command": "git push"]],
                 expectsReply: true, id: "cc1"))
        #expect(engine.pending.first?.toolName == "Bash")
        #expect(engine.sessions.count == 1)
        // A safety prompt only alerts.
        _ = engine.resolve(requestID: "cc1")
        let alert = engine.handle(
            hook("Notification", source: "commandcode", session: "c1", extra: ["notification_type": "permission_prompt", "message": "Delete files outside the project?"]))
        #expect(alert.cue == .approval)
        #expect(engine.sessions[key]?.phase == .needsApproval)
    }

    @Test func cursorRunningClaudeHooksIsNotClaude() {
        var engine = SessionEngine()
        func cursor(_ event: String, _ extra: [String: JSONValue] = [:]) -> SessionEngine.Outcome {
            var payload: [String: JSONValue] = [
                "hook_event_name": .string(event), "conversation_id": "conv1", "cursor_version": "2.4.1",
                "workspace_roots": ["/tmp/proj"], "generation_id": "g1",
            ]
            payload.merge(extra) { _, new in new }
            return engine.handle(BridgeEnvelope(source: "claude", payload: .object(payload)))
        }
        _ = cursor("sessionStart", ["session_id": "conv1"])
        _ = cursor("beforeSubmitPrompt", ["prompt": "Fix the build"])
        _ = cursor("preToolUse", ["tool_name": "Shell", "tool_input": ["command": "npm test"]])
        let s = engine.sessions["cursor:conv1"]
        #expect(engine.sessions.count == 1)
        #expect(s?.agent == .cursor)
        #expect(s?.cwd == "/tmp/proj")
        #expect(s?.title == "Fix the build")
        #expect(s?.currentTool == "Running tests")
        _ = cursor("Stop")
        #expect(engine.sessions["cursor:conv1"]?.phase == .done)
        // Plain Claude payloads are unaffected.
        _ = engine.handle(hook("SessionStart", source: "claude"))
        #expect(engine.sessions["claude:s1"]?.agent == .claude)
    }
}
