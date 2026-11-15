import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func hook(
    _ event: String, source: String, session: String = "s1", extra: [String: JSONValue] = [:], id: String = UUID().uuidString
) -> BridgeEnvelope {
    var payload: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": .string(session), "cwd": "/tmp/proj"]
    payload.merge(extra) { _, new in new }
    // What the bridge would decide for this source and event.
    return BridgeEnvelope(id: id, source: source, payload: .object(payload), expectsReply: expectsReply(source: source, event: event))
}

private func tempHome() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

private func mkdir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

// MARK: TOML block

@Suite struct TOMLHookBlockTests {
    let block = TOMLHookBlock.block(
        events: HookTarget.kimi.events, command: { HookInstaller.command(for: .kimi, event: $0) }, timeout: HookTarget.kimi.timeout(for:))

    static let samples = [
        "",
        "default_model = \"kimi-k2\"\n",
        // No final newline.
        "default_model = \"kimi-k2\"\n[mcp]\nenabled = true",
        // CRLF line endings, comments, and someone else's hook.
        "# my config\r\ntheme = 'dark'\r\n\r\n[[hooks]]\r\nevent = \"Stop\"\r\ncommand = \"afplay done.wav\"\r\n",
        // Ends inside a table and with blank lines.
        "[providers.moonshot]\napi_key = \"sk-x\"   # keep me\n\n\n",
        // Root key named like ours, but inside a table: not a conflict.
        "[tui]\nhooks = true\n",
    ]

    @Test(arguments: samples) func uninstallRestoresEveryByte(original: String) throws {
        let installed = try TOMLHookBlock.installing(block, into: original)
        #expect(installed.hasPrefix(original.last?.isNewline != false ? original : original + "\n"))
        #expect(try TOMLHookBlock.installing(block, into: installed) == installed)
        #expect(Data(try TOMLHookBlock.uninstalling(from: installed).utf8) == Data(original.utf8))
        #expect(TOMLHookBlock.events(in: installed) == Set(HookTarget.kimi.events))
    }

    @Test func blockIsOneTablePerEventWithLiteralCommands() {
        let tables = block.components(separatedBy: "[[hooks]]\n").dropFirst()
        #expect(tables.count == HookTarget.kimi.events.count)
        for table in tables {
            let keys = table.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }.map { $0.split(separator: " ").first! }
            // Kimi rejects the whole config on any key besides these four.
            #expect(Set(keys).isSubset(of: ["event", "matcher", "command", "timeout"]))
        }
        #expect(block.contains("command = '[ -x \"$HOME/.orby/bin/orby-bridge\" ] && exec \"$HOME/.orby/bin/orby-bridge\" --source kimi || true'"))
        // Observe-only: Kimi never waits on PermissionRequest, so neither does the hook.
        #expect(block.contains("event = \"PermissionRequest\"\ncommand = '[ -x \"$HOME/.orby/bin/orby-bridge\" ] && exec \"$HOME/.orby/bin/orby-bridge\" --source kimi || true'\ntimeout = 10\n"))
        #expect(!block.contains("timeout = 7200"))
    }

    @Test func refusesFilesItCantSafelyExtend() {
        #expect(throws: TOMLHookBlock.EditError.conflictingHooksKey) { try TOMLHookBlock.installing(block, into: "hooks = []\n") }
        #expect(throws: TOMLHookBlock.EditError.conflictingHooksKey) { try TOMLHookBlock.installing(block, into: "[hooks]\nx = 1\n") }
        #expect(throws: TOMLHookBlock.EditError.conflictingHooksKey) { try TOMLHookBlock.installing(block, into: "hooks.a = 1\n") }
        // A multi-line string that merely mentions hooks is not a key.
        #expect((try? TOMLHookBlock.installing(block, into: "note = \"\"\"\nhooks = no\n\"\"\"\n")) != nil)
        let broken = "a = 1\n" + TOMLHookBlock.begin + "\n[[hooks]]\n"
        #expect(throws: TOMLHookBlock.EditError.brokenBlock) { try TOMLHookBlock.uninstalling(from: broken) }
    }
}

// MARK: Installers

@Suite struct KimiInstallerTests {
    let original = "# Kimi Code config\ndefault_model = \"kimi-k2\"\n\n[[hooks]]\nevent = \"PreToolUse\"\nmatcher = \"Bash\"\ncommand = \"node ~/.kimi-code/hooks/guard.mjs\"\ntimeout = 5\n"

    @Test func roundTripInTempHomeLeavesFileByteIdentical() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(HookInstaller.status(.kimi, home: home) == .agentMissing)
        let url = home.appendingPathComponent(".kimi-code/config.toml")
        #expect(HookTarget.kimi.configURL(home: home) == url)
        try mkdir(url.deletingLastPathComponent())
        #expect(HookInstaller.status(.kimi, home: home) == .notInstalled)
        try Data(original.utf8).write(to: url)

        let backups = home.appendingPathComponent("b")
        let backup = try #require(try HookInstaller.apply(.kimi, install: true, home: home, backupDir: backups))
        #expect(try Data(contentsOf: backup) == Data(original.utf8))
        #expect(HookInstaller.status(.kimi, home: home) == .installed)
        let installed = try String(contentsOf: url, encoding: .utf8)
        #expect(installed.hasPrefix(original))
        // Re-installing changes nothing and writes no backup.
        #expect(try HookInstaller.apply(.kimi, install: true, home: home, backupDir: backups) == nil)

        try HookInstaller.apply(.kimi, install: false, home: home, backupDir: backups)
        #expect(try Data(contentsOf: url) == Data(original.utf8))
        #expect(HookInstaller.status(.kimi, home: home) == .notInstalled)
        // Nothing to remove: the file isn't touched again.
        #expect(try HookInstaller.apply(.kimi, install: false, home: home, backupDir: backups) == nil)
    }

    @Test func createsConfigWhenMissingAndRemovesToEmpty() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home.appendingPathComponent(".kimi-code"))
        #expect(try HookInstaller.apply(.kimi, install: true, home: home, backupDir: home.appendingPathComponent("b")) == nil)
        #expect(HookInstaller.status(.kimi, home: home) == .installed)
        try HookInstaller.apply(.kimi, install: false, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(try Data(contentsOf: HookTarget.kimi.configURL(home: home)).isEmpty)
    }

    @Test func partialAndUntouchableConfigs() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = HookTarget.kimi.configURL(home: home)
        try mkdir(url.deletingLastPathComponent())
        let partial = TOMLHookBlock.block(events: ["Stop"], command: { HookInstaller.command(for: .kimi, event: $0) }, timeout: { _ in 10 })
        try Data(partial.utf8).write(to: url)
        #expect(HookInstaller.status(.kimi, home: home) == .partial)

        let conflicting = Data("hooks = []\n".utf8)
        try conflicting.write(to: url)
        #expect(throws: HookInstaller.InstallError.self) { try HookInstaller.apply(.kimi, install: true, home: home, backupDir: home) }
        #expect(try Data(contentsOf: url) == conflicting)

        let latin1 = Data([0x61, 0x3D, 0x22, 0xE9, 0x22, 0x0A])  // a="é" in Latin-1
        try latin1.write(to: url)
        #expect(throws: HookInstaller.InstallError.self) { try HookInstaller.apply(.kimi, install: true, home: home, backupDir: home) }
        #expect(try Data(contentsOf: url) == latin1)
    }
}

@Suite struct DroidInstallerTests {
    let foreign: JSONValue = [
        "PreToolUse": [["matcher": "Execute", "hooks": [["type": "command", "command": "./audit.sh", "timeout": 30]]]],
    ]

    @Test func hooksJSONIsTheHookMapWithoutWrapper() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(HookInstaller.status(.droid, home: home) == .agentMissing)
        let url = home.appendingPathComponent(".factory/hooks.json")
        try mkdir(url.deletingLastPathComponent())
        #expect(HookInstaller.status(.droid, home: home) == .notInstalled)
        try foreign.encoded().write(to: url)

        let backups = home.appendingPathComponent("b")
        let backup = try #require(try HookInstaller.apply(.droid, install: true, home: home, backupDir: backups))
        #expect(try JSONValue.decode(Data(contentsOf: backup)) == foreign)
        let root = try JSONValue.decode(Data(contentsOf: url))
        #expect(root["hooks"] == nil)
        #expect(root["PreToolUse"]?.array?.first == foreign["PreToolUse"]?.array?.first)
        let notification = try #require(root["Notification"]?.array?.first?["hooks"]?.array?.first)
        #expect(notification["command"]?.string?.contains("--source droid") == true)
        #expect(notification["timeout"]?.int == 10)
        #expect(root["PermissionRequest"] == nil)
        #expect(HookInstaller.status(.droid, home: home) == .installed)

        try HookInstaller.apply(.droid, install: false, home: home, backupDir: backups)
        #expect(try JSONValue.decode(Data(contentsOf: url)) == foreign)
        #expect(HookInstaller.status(.droid, home: home) == .notInstalled)
    }

    @Test func usesSettingsHooksWhenThereIsNoHooksJSON() throws {
        let home = tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".factory")
        try mkdir(dir)
        let settings: JSONValue = ["model": "gpt-5", "hooks": foreign]
        try settings.encoded().write(to: dir.appendingPathComponent("settings.json"))
        // Creating hooks.json would make Droid ignore the hooks already in settings.json.
        #expect(HookTarget.droid.configURL(home: home).lastPathComponent == "settings.json")
        try HookInstaller.apply(.droid, install: true, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("hooks.json").path))
        let written = try JSONValue.decode(Data(contentsOf: dir.appendingPathComponent("settings.json")))
        #expect(written["model"]?.string == "gpt-5")
        #expect(HookInstaller.isInstalled(.droid, in: written))
        try HookInstaller.apply(.droid, install: false, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(try JSONValue.decode(Data(contentsOf: dir.appendingPathComponent("settings.json"))) == settings)
    }

    @Test func neverBlocks() {
        #expect(!HookTarget.droid.events.contains("PermissionRequest"))
        #expect(HookTarget.droid.events.allSatisfy { HookTarget.droid.timeout(for: $0) == 10 })
        #expect(HookTarget.kimi.events.allSatisfy { HookTarget.kimi.timeout(for: $0) == 10 })
        #expect(!expectsReply(source: "kimi", event: "PermissionRequest"))
        #expect(expectsReply(source: "claude", event: "PermissionRequest"))
        #expect(!expectsReply(source: "droid", event: "PreToolUse"))
    }
}

// MARK: Payloads → phases

@Suite struct DroidKimiSessionTests {
    @Test func droidStatusAndPermissionPromptAlert() {
        var engine = SessionEngine()
        let start = engine.handle(hook("SessionStart", source: "droid", extra: ["source": "startup", "permission_mode": "auto-low"]))
        #expect(start.sessionKey == "droid:s1")
        #expect(engine.sessions["droid:s1"]?.agent == .droid)
        #expect(engine.sessions["droid:s1"]?.phase == .ready)
        _ = engine.handle(hook("UserPromptSubmit", source: "droid", extra: ["prompt": "Fix the build"]))
        #expect(engine.sessions["droid:s1"]?.phase == .thinking)
        _ = engine.handle(
            hook("PreToolUse", source: "droid", extra: ["tool_name": "Execute", "tool_input": ["command": "rm -rf build"]]))
        #expect(engine.sessions["droid:s1"]?.phase == .working)
        #expect(engine.sessions["droid:s1"]?.lastToolName == "Bash")

        let ask = engine.handle(
            hook("Notification", source: "droid", extra: ["notification_type": "permission_prompt", "message": "Droid needs your permission to run rm"]))
        #expect(ask.cue == .approval)
        #expect(ask.reveal == .attention("droid:s1"))
        #expect(engine.sessions["droid:s1"]?.phase == .needsApproval)
        #expect(engine.pending.isEmpty)

        _ = engine.handle(hook("PostToolUse", source: "droid", extra: ["tool_name": "Execute", "tool_input": ["command": "rm -rf build"]]))
        #expect(engine.sessions["droid:s1"]?.phase == .thinking)
        let stop = engine.handle(hook("Stop", source: "droid"))
        #expect(stop.cue == .done)
        #expect(engine.sessions["droid:s1"]?.phase == .done)
    }

    @Test func droidCancelSendsIdleNotificationInsteadOfStop() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", source: "droid", extra: ["prompt": "Go"]))
        _ = engine.handle(hook("Notification", source: "droid", extra: ["notification_type": "idle_prompt"]))
        #expect(engine.sessions["droid:s1"]?.phase == .waitingInput)
    }

    @Test func kimiPermissionRequestIsAnExternalPromptClearedByResult() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", source: "kimi", extra: ["prompt": "Clean up"]))
        let input: JSONValue = ["command": "git clean -fd"]
        let env = hook("PermissionRequest", source: "kimi", extra: ["tool_name": "Bash", "tool_input": input, "tool_call_id": "call_1"])
        #expect(!env.expectsReply)
        let out = engine.handle(env)
        #expect(out.cue == .approval)
        #expect(out.reveal == .attention("kimi:s1"))
        let request = engine.pending.first
        #expect(request?.kind == .external)
        #expect(request?.toolName == "Bash")
        #expect(request?.toolInput == input)
        #expect(engine.sessions["kimi:s1"]?.phase == .needsApproval)
        #expect(engine.sessions["kimi:s1"]?.attention?.hasPrefix("Wants to") == true)

        let result = engine.handle(hook("PermissionResult", source: "kimi", extra: ["tool_name": "Bash", "tool_call_id": "call_1"]))
        #expect(result.cancelledRequests == [request?.id].compactMap { $0 })
        #expect(engine.pending.isEmpty)
        #expect(engine.sessions["kimi:s1"]?.phase == .working)
    }

    @Test func kimiResultWithoutIDClearsTheSessionsPrompt() {
        var engine = SessionEngine()
        _ = engine.handle(hook("PermissionRequest", source: "kimi", extra: ["tool_name": "Write", "tool_input": ["path": "/tmp/proj/a.txt"]]))
        #expect(engine.pending.first?.toolInput["file_path"]?.string == "/tmp/proj/a.txt")
        #expect(engine.pending.first?.summary == "Writing a.txt")
        _ = engine.handle(hook("PermissionResult", source: "kimi"))
        #expect(engine.pending.isEmpty)
    }

    @Test func kimiLifecycleEvents() {
        var engine = SessionEngine()
        _ = engine.handle(hook("SessionStart", source: "kimi", extra: ["source": "startup", "model": "kimi-k2"]))
        #expect(engine.sessions["kimi:s1"]?.agent == .kimi)
        #expect(engine.sessions["kimi:s1"]?.model == "kimi-k2")
        _ = engine.handle(hook("PreToolUse", source: "kimi", extra: ["tool_name": "Read", "tool_input": ["path": "/tmp/proj/README.md"]]))
        #expect(engine.sessions["kimi:s1"]?.activity?.progressive == "Reading README.md")
        _ = engine.handle(hook("PreCompact", source: "kimi", extra: ["trigger": "auto"]))
        #expect(engine.sessions["kimi:s1"]?.phase == .compacting)
        _ = engine.handle(hook("PostCompact", source: "kimi", extra: ["trigger": "auto"]))
        #expect(engine.sessions["kimi:s1"]?.phase == .thinking)
        _ = engine.handle(hook("Interrupt", source: "kimi", extra: ["reason": "user"]))
        #expect(engine.sessions["kimi:s1"]?.phase == .done)
        _ = engine.handle(hook("StopFailure", source: "kimi", extra: ["error": "rate limited"]))
        #expect(engine.sessions["kimi:s1"]?.phase == .error)
        _ = engine.handle(hook("SessionEnd", source: "kimi"))
        #expect(engine.sessions["kimi:s1"] == nil)
    }
}

// MARK: Tool descriptions

@Suite struct DroidKimiToolTests {
    func describe(_ tool: String, _ input: JSONValue) -> String {
        let p = ToolAliases.normalized(["tool_name": .string(tool), "tool_input": input])
        return ToolDescriber.describe(tool: p["tool_name"]?.string ?? tool, input: p["tool_input"] ?? .object([:]))
    }

    @Test func droidTools() {
        #expect(describe("Execute", ["command": "git status"]) == ToolDescriber.describe(tool: "Bash", input: ["command": "git status"]))
        #expect(describe("Create", ["file_path": "/tmp/proj/new.txt", "content": "x"]) == "Writing new.txt")
        #expect(describe("Edit", ["file_path": "/tmp/proj/App.swift", "old_str": "a", "new_str": "b"]) == "Editing App.swift")
        #expect(ToolAliases.normalized(["tool_name": "Edit", "tool_input": ["file_path": "/a", "old_str": "a", "new_str": "b"]])["tool_input"]
            == ["file_path": "/a", "old_string": "a", "new_string": "b"])
        #expect(describe("FetchUrl", ["url": "https://docs.factory.com/x"]) == "Reading docs.factory.com")
        #expect(describe("LS", ["path": "/tmp/proj/Sources"]) == "Listing Sources")
        #expect(describe("LS", [:]) == "Listing files")
        #expect(describe("ApplyPatch", ["patch": "*** Begin Patch\n*** Update File: Sources/App.swift\n*** End Patch"]).contains("App.swift"))
        #expect(describe("Task", ["description": "Review the diff", "subagent_type": "reviewer"]) == "Delegating: Review the diff")
    }

    @Test func kimiTools() {
        #expect(describe("Read", ["path": "/tmp/proj/notes.md"]) == "Reading notes.md")
        #expect(describe("Edit", ["path": "/tmp/proj/a.ts", "old_string": "x", "new_string": "y"]) == "Editing a.ts")
        #expect(describe("FetchURL", ["url": "https://moonshot.ai/"]) == "Reading moonshot.ai")
        #expect(describe("WebSearch", ["query": "swift testing"]) == "Searching the web for “swift testing”")
        #expect(describe("Agent", ["prompt": "Look around", "description": "Explore the repo"]) == "Delegating: Explore the repo")
        #expect(describe("TodoList", ["todos": []]) == "Updating the to-do list")
        let tasks = TaskProgress.parse(
            tool: "TodoList", input: ["todos": [["title": "Write tests", "status": "done"], ["title": "Ship", "status": "in_progress"]]])
        #expect(tasks?.total == 2)
        #expect(tasks?.done == 1)
        #expect(tasks?.items.last?.status == .inProgress)
    }
}
