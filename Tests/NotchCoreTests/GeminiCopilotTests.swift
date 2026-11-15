import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func envelope(
    _ payload: [String: JSONValue], source: String, expectsReply: Bool = false, id: String = UUID().uuidString
) -> BridgeEnvelope {
    BridgeEnvelope(id: id, source: source, payload: .object(payload), expectsReply: expectsReply)
}

private func tempHome() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

private func mkdir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

// MARK: JSONC

@Suite struct JSONCTests {
    static let commented = """
        // Gemini CLI settings
        {
          /* theme picked in /theme */
          "theme": "GitHub", // trailing note
          "url": "https://example.com/a//b", // a "//" inside a string isn't a comment
          "general": {
            "vimMode": true,
          },
        }

        """

    @Test func parsesCommentsAndTrailingCommas() throws {
        let value = try JSONC.parse(Data(Self.commented.utf8))
        #expect(value["theme"]?.string == "GitHub")
        #expect(value["url"]?.string == "https://example.com/a//b")
        #expect(value["general"]?["vimMode"]?.bool == true)
        #expect(try JSONC.parse(Data("  \n".utf8)) == .object([:]))
    }

    @Test func insertThenRemoveGivesBackTheSameText() throws {
        let fixtures = [
            Self.commented,
            "{\n  \"a\": 1 // last\n}\n",
            "{\n  \"a\": 1,\n  \"b\": [1, 2]\n}",
            "{\"a\":1}",
            "{\n}\n",
        ]
        let hooks: JSONValue = ["BeforeTool": [["matcher": "*", "hooks": [["name": "orby", "command": "x"]]]]]
        for original in fixtures {
            let added = try JSONC.setting("hooks", to: hooks, in: original)
            #expect(try JSONC.parse(Data(added.utf8))["hooks"] == hooks, "\(original)")
            let removed = try JSONC.setting("hooks", to: nil, in: added)
            if original != "{\n}\n" { #expect(removed == original) }
            #expect(try JSONC.parse(Data(removed.utf8))["hooks"] == nil)
        }
    }

    @Test func replacesOnlyTheMembersValue() throws {
        let original = "{\n  // keep me\n  \"hooks\": {\"Old\": []},\n  \"theme\": \"x\", /* and me */\n}\n"
        let out = try JSONC.setting("hooks", to: ["New": []], in: original)
        #expect(out.contains("// keep me"))
        #expect(out.contains("/* and me */"))
        #expect(out.contains("\"theme\": \"x\", /* and me */\n}"))
        #expect(try JSONC.parse(Data(out.utf8))["hooks"] == ["New": []])
        // Removing a member that isn't last keeps its neighbours' commas valid.
        let removed = try JSONC.setting("hooks", to: nil, in: out)
        #expect(try JSONC.parse(Data(removed.utf8)) == ["theme": "x"])
        #expect(removed.contains("// keep me"))
    }

    @Test func refusesToRewriteCommentedValue() {
        let original = "{\n  \"hooks\": {\n    // \"BeforeTool\": []\n  }\n}"
        #expect(throws: JSONC.EditError.commentsInside("hooks")) { try JSONC.setting("hooks", to: ["A": []], in: original) }
        #expect(throws: JSONC.EditError.malformed) { try JSONC.setting("hooks", to: ["A": []], in: "[1, 2]") }
    }
}

// MARK: Installers

@Suite struct GeminiInstallerTests {
    static let settings = """
        {
          // Picked with /theme
          "theme": "Dracula",
          "hooks": {
            "AfterAgent": [
              {"hooks": [{"name": "chime", "type": "command", "command": "afplay done.wav", "timeout": 2000}]},
            ],
          },
          "security": {"auth": {"selectedType": "oauth-personal"}}, /* signed in */
        }

        """

    @Test func notFoundWhenOnlyAntigravityUsesTheFolder() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".gemini/antigravity"))
        #expect(HookInstaller.status(.gemini, home: home) == .agentMissing)
        try mkdir(home.appendingPathComponent(".gemini/tmp"))
        #expect(HookInstaller.status(.gemini, home: home) == .notInstalled)
    }

    @Test func installKeepsCommentsAndRemoveRestoresTheFile() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".gemini/tmp"))
        let url = home.appendingPathComponent(".gemini/settings.json")
        try Self.settings.write(to: url, atomically: true, encoding: .utf8)
        let backups = home.appendingPathComponent("b")

        let backup = try #require(try HookInstaller.apply(.gemini, install: true, home: home, backupDir: backups))
        #expect(try text(backup) == Self.settings)
        let installed = try text(url)
        #expect(installed.contains("// Picked with /theme"))
        #expect(installed.contains("/* signed in */"))
        #expect(HookInstaller.status(.gemini, home: home) == .installed)

        let root = try JSONC.parse(Data(installed.utf8))
        #expect(root["theme"]?.string == "Dracula")
        #expect(root["hooks"]?["AfterAgent"]?.array?.first?["hooks"]?.array?.first?["name"]?.string == "chime")
        let tool = try #require(root["hooks"]?["BeforeTool"]?.array?.last)
        #expect(tool["matcher"]?.string == "*")
        let ours = try #require(tool["hooks"]?.array?.first)
        #expect(ours["name"]?.string == "orby")
        #expect(ours["timeout"]?.int == 5000)
        #expect(ours["command"]?.string?.contains("--source gemini") == true)
        #expect(root["hooks"]?["Notification"]?.array?.last?["matcher"] == nil)

        // Installing again changes nothing.
        try HookInstaller.apply(.gemini, install: true, home: home, backupDir: backups)
        #expect(try text(url) == installed)

        try HookInstaller.apply(.gemini, install: false, home: home, backupDir: backups)
        let removed = try text(url)
        #expect(removed.contains("// Picked with /theme"))
        #expect(removed.contains("/* signed in */"))
        #expect(try JSONC.parse(Data(removed.utf8)) == JSONC.parse(Data(Self.settings.utf8)))
        #expect(HookInstaller.status(.gemini, home: home) == .notInstalled)
    }

    @Test func roundTripWithoutHooksIsByteForByte() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".gemini/tmp"))
        let url = home.appendingPathComponent(".gemini/settings.json")
        let original = "{\n  // just a theme\n  \"theme\": \"Dracula\",\n}\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        try HookInstaller.apply(.gemini, install: true, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(HookInstaller.isInstalled(.gemini, in: try JSONC.parse(Data(contentsOf: url))))
        try HookInstaller.apply(.gemini, install: false, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(try text(url) == original)
    }

    @Test func refusesWhenHooksHoldComments() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".gemini/tmp"))
        let url = home.appendingPathComponent(".gemini/settings.json")
        let original = "{\n  \"hooks\": {\n    // \"BeforeTool\": []\n  }\n}\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: HookInstaller.InstallError.self) {
            try HookInstaller.apply(.gemini, install: true, home: home, backupDir: home.appendingPathComponent("b"))
        }
        #expect(try text(url) == original)
    }

    @Test func createsSettingsWhenMissing() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".gemini/tmp"))
        #expect(try HookInstaller.apply(.gemini, install: true, home: home, backupDir: home.appendingPathComponent("b")) == nil)
        #expect(HookInstaller.status(.gemini, home: home) == .installed)
    }
}

@Suite struct CopilotInstallerTests {
    @Test func ownsAFileInTheHooksFolder() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(HookInstaller.status(.copilot, home: home) == .agentMissing)
        let hooksDir = home.appendingPathComponent(".copilot/hooks")
        try mkdir(hooksDir)
        let other = hooksDir.appendingPathComponent("vibe-island.json")
        let otherText = "{\"hooks\":{\"PreToolUse\":[{\"type\":\"command\",\"command\":\"vibe\"}]}}"
        try otherText.write(to: other, atomically: true, encoding: .utf8)
        #expect(HookInstaller.status(.copilot, home: home) == .notInstalled)

        let backups = home.appendingPathComponent("b")
        #expect(try HookInstaller.apply(.copilot, install: true, home: home, backupDir: backups) == nil)
        let url = hooksDir.appendingPathComponent("orby.json")
        #expect(HookTarget.copilot.configURL(home: home) == url)
        let root = try JSONValue.decode(Data(contentsOf: url))
        #expect(root["version"]?.int == 1)
        #expect(HookInstaller.status(.copilot, home: home) == .installed)
        let perm = try #require(root["hooks"]?["PermissionRequest"]?.array?.first?["hooks"]?.array?.first)
        #expect(perm["command"]?.string?.contains("--source copilot --event PermissionRequest") == true)
        #expect(perm["command"]?.string?.hasSuffix("|| true") == true)
        #expect(perm["timeout"]?.int == 7200)
        #expect(root["hooks"]?["PreToolUse"]?.array?.first?["hooks"]?.array?.first?["timeout"]?.int == 10)
        #expect(try text(other) == otherText)

        try HookInstaller.apply(.copilot, install: false, home: home, backupDir: backups)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try text(other) == otherText)
        #expect(HookInstaller.status(.copilot, home: home) == .notInstalled)
    }
}

// MARK: Payloads → session phases

@Suite struct GeminiEventTests {
    func gemini(_ event: String, _ extra: [String: JSONValue] = [:]) -> BridgeEnvelope {
        var p: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": "g1", "cwd": "/tmp/proj"]
        p.merge(extra) { _, new in new }
        return envelope(p, source: "gemini")
    }

    @Test func turnWithTerminalPrompt() {
        var engine = SessionEngine()
        let key = "gemini:g1"
        _ = engine.handle(gemini("SessionStart", ["source": "startup"]))
        #expect(engine.sessions[key]?.agent == .gemini)
        #expect(engine.sessions[key]?.phase == .ready)
        _ = engine.handle(gemini("BeforeAgent", ["prompt": "Run the tests"]))
        #expect(engine.sessions[key]?.phase == .thinking)
        #expect(engine.sessions[key]?.lastPrompt == "Run the tests")

        let input: JSONValue = ["command": "npm test", "dir_path": "."]
        _ = engine.handle(gemini("BeforeTool", ["tool_name": "run_shell_command", "tool_input": input]))
        #expect(engine.sessions[key]?.phase == .working)
        #expect(engine.sessions[key]?.lastToolName == "Bash")

        let prompt = engine.handle(
            gemini("Notification", [
                "notification_type": "ToolPermission", "message": "Allow execution of: npm?",
                "details": ["type": "exec", "title": "Confirm Shell Command", "command": "npm test", "rootCommand": "npm"],
            ]))
        #expect(prompt.cue == .approval)
        #expect(prompt.reveal == .attention(key))
        #expect(engine.sessions[key]?.phase == .needsApproval)
        let request = engine.pending.first
        #expect(request?.kind == .external)
        #expect(request?.toolName == "Bash")
        #expect(request?.toolInput == input)

        // Approved in Gemini's terminal: the tool ran.
        let after = engine.handle(gemini("AfterTool", ["tool_name": "run_shell_command", "tool_input": input, "tool_response": ["llmContent": "ok"]]))
        #expect(after.cancelledRequests == [request?.id].compactMap { $0 })
        #expect(engine.sessions[key]?.phase == .thinking)

        _ = engine.handle(gemini("AfterAgent", ["prompt_response": "Done"]))
        #expect(engine.sessions[key]?.phase == .done)
        _ = engine.handle(gemini("SessionEnd", ["reason": "exit"]))
        #expect(engine.sessions[key] == nil)
    }

    @Test func promptBeforeItsToolUsesTheNotificationDetails() {
        var engine = SessionEngine()
        _ = engine.handle(gemini("BeforeTool", ["tool_name": "read_file", "tool_input": ["absolute_path": "/tmp/proj/a.md"]]))
        _ = engine.handle(
            gemini("Notification", [
                "notification_type": "ToolPermission", "message": "Apply this change?",
                "details": ["type": "edit", "fileName": "b.swift", "filePath": "/tmp/proj/b.swift", "fileDiff": "@@"],
            ]))
        #expect(engine.pending.first?.toolName == "Edit")
        #expect(engine.pending.first?.summary == "Editing b.swift")
        // The real call, with more arguments than the prompt showed, still settles it.
        let after = engine.handle(
            gemini("AfterTool", ["tool_name": "replace", "tool_input": ["file_path": "/tmp/proj/b.swift", "old_string": "a", "new_string": "b"]]))
        #expect(after.cancelledRequests.count == 1)
    }

    @Test func otherNotificationsAndFailuresAndMCP() {
        var engine = SessionEngine()
        let key = "gemini:g1"
        _ = engine.handle(gemini("Notification", ["notification_type": "SomethingElse", "message": "hi"]))
        #expect(engine.pending.isEmpty)
        #expect(engine.sessions[key]?.phase == .ready)

        _ = engine.handle(
            gemini("BeforeTool", [
                "tool_name": "mcp_github_create_issue", "tool_input": [:],
                "mcp_context": ["server_name": "github", "tool_name": "create_issue"],
            ]))
        #expect(engine.sessions[key]?.currentTool == "Using GitHub: create issue")
        let failed = GeminiPayload.normalized(["hook_event_name": "AfterTool", "tool_response": ["error": "boom"]])
        #expect(failed["hook_event_name"]?.string == "PostToolUseFailure")
        #expect(GeminiPayload.normalized(["hook_event_name": "AfterTool", "tool_response": ["error": .null]])["hook_event_name"]?.string == "PostToolUse")
    }
}

@Suite struct CopilotEventTests {
    /// Copilot's permission hook input, as 1.0.29 builds it (camelCase, event named by `--event`).
    func permission(_ tool: String, _ input: JSONValue, reply: Bool, id: String) -> BridgeEnvelope {
        envelope(
            [
                "hookName": "permissionRequest", "hook_event_name": "PermissionRequest", "sessionId": "c1", "timestamp": 1,
                "cwd": "/tmp/proj", "toolName": .string(tool), "toolInput": input, "permissionSuggestions": [],
            ], source: "copilot", expectsReply: reply, id: id)
    }

    func copilot(_ event: String, _ extra: [String: JSONValue] = [:]) -> BridgeEnvelope {
        var p: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": "c1", "cwd": "/tmp/proj"]
        p.merge(extra) { _, new in new }
        return envelope(p, source: "copilot")
    }

    @Test func statusOnlyByDefault() {
        var engine = SessionEngine()
        let key = "copilot:c1"
        _ = engine.handle(copilot("SessionStart", ["source": "new"]))
        _ = engine.handle(copilot("UserPromptSubmit", ["prompt": "List files"]))
        #expect(engine.sessions[key]?.agent == .copilot)
        #expect(engine.sessions[key]?.phase == .thinking)
        let input: JSONValue = ["command": "ls -la", "description": "List files"]
        _ = engine.handle(copilot("PreToolUse", ["tool_name": "bash", "tool_input": input]))
        #expect(engine.sessions[key]?.currentTool == "List files")

        // Without the setting the permission hook is only seen, never held.
        _ = engine.handle(permission("bash", ["command": "ls -la"], reply: true, id: "p1"))
        #expect(engine.pending.isEmpty)
        #expect(engine.sessions[key]?.phase == .working)

        // Copilot then asks in its terminal.
        let ask = engine.handle(copilot("Notification", ["notification_type": "permission_prompt", "message": "Allow bash?"]))
        #expect(ask.cue == .approval)
        #expect(engine.pending.first?.kind == .external)
        #expect(engine.pending.first?.toolName == "Bash")
        #expect(engine.sessions[key]?.phase == .needsApproval)
        let post = engine.handle(copilot("PostToolUse", ["tool_name": "bash", "tool_input": input]))
        #expect(post.cancelledRequests.count == 1)

        _ = engine.handle(copilot("Stop", ["stop_reason": "end_turn"]))
        #expect(engine.sessions[key]?.phase == .done)
        _ = engine.handle(copilot("Notification", ["notification_type": "agent_idle"]))
        #expect(engine.sessions[key]?.phase == .done)
        _ = engine.handle(copilot("UserPromptSubmit", ["prompt": "Again"]))
        _ = engine.handle(copilot("Notification", ["notification_type": "agent_idle"]))
        #expect(engine.sessions[key]?.phase == .waitingInput)
    }

    @Test func approvalsFromTheNotchWhenEnabled() {
        var engine = SessionEngine()
        engine.copilotApprovals = true
        _ = engine.handle(permission("edit", ["file_path": "/tmp/proj/a.swift", "diff": "@@"], reply: true, id: "p2"))
        let request = engine.pending.first
        #expect(request?.kind == .permission)
        #expect(request?.toolName == "Edit")
        #expect(request?.summary == "Editing a.swift")
        #expect(engine.sessions["copilot:c1"]?.phase == .needsApproval)

        _ = engine.handle(permission("github/create_issue", ["title": "x"], reply: true, id: "p3"))
        #expect(engine.pending.first?.toolName == "mcp__github__create_issue")
    }

    @Test func replyIsFlat() {
        #expect(PermissionDecision.allow().hookOutput(for: .copilot) == ["behavior": "allow"])
        #expect(
            PermissionDecision.deny(message: "No", interrupt: true).hookOutput(for: .copilot)
                == ["behavior": "deny", "message": "No", "interrupt": true])
        #expect(PermissionDecision.passthrough.hookOutput(for: .copilot) == nil)
        #expect(PermissionDecision.allow().hookOutput(for: .claude) == PermissionDecision.allow().hookOutput())
    }

    @Test func fatalErrorEndsTheTurn() {
        var engine = SessionEngine()
        _ = engine.handle(copilot("ErrorOccurred", ["error": ["message": "Rate limited", "name": "Error"], "recoverable": true]))
        #expect(engine.sessions["copilot:c1"]?.phase == .ready)
        _ = engine.handle(copilot("ErrorOccurred", ["error": ["message": "Rate limited", "name": "Error"], "recoverable": false]))
        #expect(engine.sessions["copilot:c1"]?.phase == .error)
        #expect(engine.sessions["copilot:c1"]?.lastMessage == "Rate limited")
    }

    @Test func olderCamelCasePayloads() {
        let out = CopilotPayload.normalized(
            ["hook_event_name": "PreToolUse", "sessionId": "c1", "toolName": "view", "toolArgs": "{\"path\":\"/tmp/a.md\"}"], approvals: false)
        #expect(out["session_id"]?.string == "c1")
        #expect(out["tool_name"]?.string == "Read")
        #expect(out["tool_input"] == ["file_path": "/tmp/a.md"])
    }
}

// MARK: Tool descriptions

@Suite struct GeminiCopilotToolTests {
    func describe(_ tool: String, _ input: JSONValue) -> String {
        let p = ToolAliases.normalized(["tool_name": .string(tool), "tool_input": input])
        return ToolDescriber.describe(tool: p["tool_name"]?.string ?? tool, input: p["tool_input"] ?? .object([:]))
    }

    @Test func geminiTools() {
        #expect(describe("run_shell_command", ["command": "git status"]) == ToolDescriber.describe(tool: "Bash", input: ["command": "git status"]))
        #expect(describe("read_file", ["absolute_path": "/tmp/proj/README.md"]) == "Reading README.md")
        #expect(describe("read_file", ["file_path": "/tmp/proj/README.md"]) == "Reading README.md")
        #expect(describe("write_file", ["file_path": "/tmp/proj/a.swift", "content": "x"]) == "Writing a.swift")
        #expect(describe("replace", ["file_path": "/tmp/proj/a.swift", "old_string": "a", "new_string": "b"]) == "Editing a.swift")
        #expect(describe("search_file_content", ["pattern": "fetchUser"]) == "Searching for “fetchUser”")
        #expect(describe("google_web_search", ["query": "swift testing"]) == "Searching the web for “swift testing”")
        #expect(describe("list_directory", ["dir_path": "/tmp/proj/Sources"]) == "Listing Sources")
        #expect(describe("write_todos", ["todos": []]) == "Updating the to-do list")
    }

    @Test func copilotTools() {
        #expect(describe("bash", ["command": "ls", "description": "List files"]) == "List files")
        #expect(describe("view", ["path": "/tmp/proj/App.swift"]) == "Reading App.swift")
        #expect(describe("create", ["path": "/tmp/proj/New.swift", "file_text": "x"]) == "Writing New.swift")
        #expect(describe("edit", ["path": "/tmp/proj/App.swift", "old_str": "a", "new_str": "b"]) == "Editing App.swift")
        #expect(describe("web_fetch", ["url": "https://docs.github.com/x"]) == "Reading docs.github.com")
        #expect(describe("report_intent", ["intent": "Exploring the codebase"]) == "Exploring the codebase")
        let edit = ToolAliases.normalized(["tool_name": "edit", "tool_input": ["path": "/a", "old_str": "x", "new_str": "y"]])
        #expect(edit["tool_input"] == ["file_path": "/a", "old_string": "x", "new_string": "y"])
        let create = ToolAliases.normalized(["tool_name": "create", "tool_input": ["path": "/a", "file_text": "z"]])
        #expect(create["tool_input"] == ["file_path": "/a", "content": "z"])
    }
}
