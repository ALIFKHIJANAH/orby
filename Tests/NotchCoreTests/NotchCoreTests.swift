import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func envelope(
    _ event: String, session: String = "s1", source: String = "claude", extra: [String: JSONValue] = [:],
    expectsReply: Bool = false, id: String = UUID().uuidString
) -> BridgeEnvelope {
    var payload: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": .string(session), "cwd": "/tmp/proj"]
    payload.merge(extra) { _, new in new }
    return BridgeEnvelope(id: id, source: source, payload: .object(payload), expectsReply: expectsReply)
}

@Suite struct HookInstallerTests {
    let foreign: JSONValue = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "afplay done.wav"]]]],
            "PermissionRequest": [["hooks": [["type": "command", "command": "other-tool", "timeout": 10]]]],
        ],
    ]

    @Test func installKeepsOtherHooksAndSettings() throws {
        let out = HookInstaller.installing(.claude, into: foreign)
        #expect(out["model"]?.string == "opus")
        let stop = out["hooks"]?["Stop"]?.array ?? []
        #expect(stop.count == 2)
        #expect(stop[0]["hooks"]?.array?.first?["command"]?.string == "afplay done.wav")
        #expect(HookInstaller.isInstalled(.claude, in: out))
        let perm = out["hooks"]?["PermissionRequest"]?.array?.last?["hooks"]?.array?.first
        #expect(perm?["timeout"]?.int == 86400)
    }

    @Test func installIsIdempotent() {
        let once = HookInstaller.installing(.claude, into: foreign)
        let twice = HookInstaller.installing(.claude, into: once)
        #expect(once == twice)
    }

    @Test func uninstallRestoresOriginal() {
        let installed = HookInstaller.installing(.claude, into: foreign)
        #expect(HookInstaller.uninstalling(from: installed) == foreign)
    }

    @Test func applyWritesBackupAndFollowsSymlink() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = home.appendingPathComponent("dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try foreign.encoded().write(to: real)
        let link = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let backup = try HookInstaller.apply(.claude, install: true, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(backup != nil)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(HookInstaller.status(.claude, home: home) == .installed)
        try HookInstaller.apply(.claude, install: false, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(try JSONValue.decode(Data(contentsOf: real)) == foreign)
    }

    @Test func refusesInvalidJSON() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(throws: HookInstaller.InstallError.self) {
            try HookInstaller.apply(.claude, install: true, home: home, backupDir: home)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ not json")
    }
}

@Suite struct AntigravityInstallerTests {
    let foreign: JSONValue = [
        "orca-status": [
            "Stop": [["type": "command", "command": "orca-hook Stop", "timeout": 10]],
            "PreToolUse": [["matcher": "*", "hooks": [["type": "command", "command": "orca-hook PreToolUse"]]]],
        ]
    ]

    @Test func installAddsOwnHookAndKeepsOthers() throws {
        let out = HookInstaller.installing(.antigravity, into: foreign)
        #expect(out["orca-status"] == foreign["orca-status"])
        #expect(HookInstaller.isInstalled(.antigravity, in: out))
        let ours = try #require(out[HookInstaller.antigravityHookName])
        #expect(ours["PreToolUse"]?.array?.first?["matcher"]?.string == "*")
        let pre = ours["PreToolUse"]?.array?.first?["hooks"]?.array?.first?["command"]?.string ?? ""
        #expect(pre.contains("--source antigravity --event PreToolUse"))
        #expect(pre.contains(#"{"decision":"allow"}"#))
        #expect(ours["Stop"]?.array?.first?["command"]?.string?.contains("--event Stop") == true)
    }

    @Test func installIsIdempotentAndUninstallRestores() {
        let once = HookInstaller.installing(.antigravity, into: foreign)
        #expect(HookInstaller.installing(.antigravity, into: once) == once)
        #expect(HookInstaller.uninstalling(from: once) == foreign)
    }

    @Test func statusNeedsAntigravityDataDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(HookInstaller.status(.antigravity, home: home) == .agentMissing)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini/antigravity-ide"), withIntermediateDirectories: true)
        #expect(HookInstaller.status(.antigravity, home: home) == .notInstalled)
        try HookInstaller.apply(.antigravity, install: true, home: home, backupDir: home.appendingPathComponent("b"))
        #expect(HookInstaller.status(.antigravity, home: home) == .installed)
    }
}

/// Rewrites a config the way the app wrote it back when it was called NotchIsland.
private func legacy(_ config: JSONValue) throws -> JSONValue {
    var obj = config.object ?? [:]
    if let hook = obj.removeValue(forKey: HookInstaller.antigravityHookName) {
        obj[HookInstaller.legacyAntigravityHookName] = hook
    }
    let text = String(decoding: try JSONValue.object(obj).encoded(), as: UTF8.self)
        .replacingOccurrences(of: "orby-bridge", with: "notchisland-bridge")
        .replacingOccurrences(of: ".orby", with: ".notchisland")
    return try JSONValue.decode(Data(text.utf8))
}

@Suite struct LegacyHookTests {
    static let configs: [(HookTarget, JSONValue)] = [
        (.claude, HookInstallerTests().foreign), (.codex, HookInstallerTests().foreign),
        (.antigravity, AntigravityInstallerTests().foreign), (.qwen, HookInstallerTests().foreign),
        (.commandcode, CommandCodeInstallerTests().foreign),
    ]

    @Test(arguments: configs) func reinstallReplacesNotchIslandHooks(target: HookTarget, foreign: JSONValue) throws {
        let old = try legacy(HookInstaller.installing(target, into: foreign))
        #expect(HookInstaller.hasLegacy(in: old))
        #expect(!HookInstaller.hasLegacy(in: foreign))
        let migrated = HookInstaller.installing(target, into: old)
        #expect(!HookInstaller.hasLegacy(in: migrated))
        #expect(migrated == HookInstaller.installing(target, into: foreign))
    }

    @Test(arguments: configs) func uninstallRemovesNotchIslandHooks(target: HookTarget, foreign: JSONValue) throws {
        let old = try legacy(HookInstaller.installing(target, into: foreign))
        #expect(HookInstaller.uninstalling(from: old) == foreign)
    }
}

@Suite struct SessionEngineTests {
    @Test func lifecycle() {
        var engine = SessionEngine()
        _ = engine.handle(envelope("SessionStart"))
        _ = engine.handle(envelope("UserPromptSubmit", extra: ["prompt": "Fix the login bug\nplease"]))
        let key = "claude:s1"
        #expect(engine.sessions[key]?.phase == .thinking)
        #expect(engine.sessions[key]?.title == "Fix the login bug")

        let input: JSONValue = ["command": "npm test"]
        let out = engine.handle(
            envelope("PermissionRequest", extra: ["tool_name": "Bash", "tool_input": input], expectsReply: true, id: "r1"))
        #expect(out.cue == .approval)
        #expect(out.reveal == .attention(key))
        #expect(engine.pending.map(\.id) == ["r1"])
        #expect(engine.sessions[key]?.phase == .needsApproval)

        // Answered in the terminal: the tool ran, so the notch request is stale.
        let post = engine.handle(envelope("PostToolUse", extra: ["tool_name": "Bash", "tool_input": input]))
        #expect(post.cancelledRequests == ["r1"])
        #expect(engine.pending.isEmpty)

        let stop = engine.handle(envelope("Stop"))
        #expect(stop.cue == .done)
        #expect(engine.sessions[key]?.phase == .done)
        #expect(engine.sessions[key]?.unread == true)

        _ = engine.handle(envelope("SessionEnd"))
        #expect(engine.sessions.isEmpty)
    }

    @Test func antigravityLifecycle() {
        var engine = SessionEngine()
        func send(_ event: String, _ extra: [String: JSONValue] = [:]) -> SessionEngine.Outcome {
            var payload: [String: JSONValue] = [
                "hook_event_name": .string(event), "conversationId": "c1", "workspacePaths": ["/tmp/proj"],
                "modelName": "gemini-3-pro",
            ]
            payload.merge(extra) { _, new in new }
            return engine.handle(BridgeEnvelope(source: "antigravity", payload: .object(payload)))
        }
        let key = "antigravity:c1"
        _ = send("PreInvocation", ["invocationNum": 0])
        #expect(engine.sessions[key]?.phase == .thinking)
        #expect(engine.sessions[key]?.cwd == "/tmp/proj")
        #expect(engine.sessions[key]?.model == "gemini-3-pro")

        _ = send("PreToolUse", ["toolCall": ["name": "run_command", "args": ["CommandLine": "npm test", "Cwd": "/tmp/proj"]]])
        #expect(engine.sessions[key]?.currentTool == "Running tests")
        #expect(engine.sessions[key]?.activity?.detail == "npm test")

        _ = send("Stop", ["fullyIdle": false, "terminationReason": "model_stop"])
        #expect(engine.sessions[key]?.phase == .working)
        let stop = send("Stop", ["fullyIdle": true, "terminationReason": "model_stop"])
        #expect(stop.cue == .done)
        #expect(engine.sessions[key]?.phase == .done)

        _ = send("Stop", ["fullyIdle": true, "terminationReason": "error", "error": "quota exceeded"])
        #expect(engine.sessions[key]?.phase == .error)
        #expect(engine.sessions[key]?.lastMessage == "quota exceeded")
    }

    @Test func thinkingBetweenTools() {
        var engine = SessionEngine()
        let key = "claude:s1"
        _ = engine.handle(envelope("UserPromptSubmit", extra: ["prompt": "go"]))
        #expect(engine.sessions[key]?.phase == .thinking)

        _ = engine.handle(envelope("PreToolUse", extra: ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        #expect(engine.sessions[key]?.phase == .working)
        #expect(engine.sessions[key]?.currentTool == "Listing files")

        _ = engine.handle(envelope("PostToolUse", extra: ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        #expect(engine.sessions[key]?.phase == .thinking)
        #expect(engine.sessions[key]?.currentTool == nil)

        // The snippet is kept only while the session is still thinking.
        var info = TranscriptInfo()
        info.latestThinking = "Listing files first.\nThe config lives in src/, so check there next."
        engine.apply(info, to: key)
        #expect(engine.sessions[key]?.thinking == "The config lives in src/, so check there next.")

        _ = engine.handle(envelope("PreToolUse", extra: ["tool_name": "Read", "tool_input": ["file_path": "/a/b.json"]]))
        #expect(engine.sessions[key]?.thinking == nil)
        engine.apply(info, to: key)
        #expect(engine.sessions[key]?.thinking == nil)
    }

    @Test func thinkingSessionsAreNotPrunedAsStale() {
        var engine = SessionEngine()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = engine.handle(envelope("UserPromptSubmit", extra: ["prompt": "long think"]), now: start)
        _ = engine.prune(now: start.addingTimeInterval(7200), doneTTL: 60, isAlive: { _ in true })
        #expect(engine.sessions["claude:s1"]?.phase == .thinking)
    }

    @Test func questionAndPlanKinds() {
        var engine = SessionEngine()
        _ = engine.handle(envelope("PermissionRequest", extra: ["tool_name": "AskUserQuestion"], expectsReply: true, id: "q"))
        _ = engine.handle(
            envelope("PermissionRequest", session: "s2", extra: ["tool_name": "ExitPlanMode", "tool_input": ["plan": "# P"]],
                expectsReply: true, id: "p"))
        #expect(engine.pending.first { $0.id == "q" }?.kind == .question)
        #expect(engine.pending.first { $0.id == "p" }?.planMarkdown == "# P")
        #expect(engine.sessions["claude:s2"]?.phase == .planReview)
        #expect(engine.resolve(requestID: "p")?.kind == .plan)
        #expect(engine.sessions["claude:s2"]?.phase == .working)
    }

    @Test func pruneDeadProcesses() {
        var engine = SessionEngine()
        var e = envelope("SessionStart")
        e.agentPID = 999_999
        _ = engine.handle(e)
        _ = engine.prune(doneTTL: 3600, isAlive: { _ in false })
        #expect(engine.sessions.isEmpty)
    }

    @Test func ordersNeedsYouFirst() {
        var engine = SessionEngine()
        _ = engine.handle(envelope("UserPromptSubmit", session: "a"))
        _ = engine.handle(envelope("Stop", session: "b"))
        _ = engine.handle(envelope("PermissionRequest", session: "c", extra: ["tool_name": "Bash"], expectsReply: true))
        #expect(engine.orderedSessions.map(\.sessionID) == ["c", "a", "b"])
    }
}

@Suite struct DecisionTests {
    @Test func allowAndDenyShapes() throws {
        let allow = PermissionDecision.allow().hookOutput()
        #expect(allow?["hookSpecificOutput"]?["hookEventName"]?.string == "PermissionRequest")
        #expect(allow?["hookSpecificOutput"]?["decision"]?["behavior"]?.string == "allow")

        let deny = PermissionDecision.deny(message: "no").hookOutput()
        #expect(deny?["hookSpecificOutput"]?["decision"]?["message"]?.string == "no")
        #expect(PermissionDecision.passthrough.hookOutput() == nil)
    }

    @Test func answersMergeIntoInput() {
        let input: JSONValue = [
            "questions": [
                ["question": "Which DB?", "header": "DB", "multiSelect": true, "options": [["label": "Postgres"], ["label": "SQLite"]]]
            ]
        ]
        let req = PendingRequest(
            id: "x", sessionKey: "k", kind: .question, toolName: "AskUserQuestion", toolInput: input, summary: "",
            suggestions: [], receivedAt: Date())
        #expect(req.questions.first?.options.map(\.label) == ["Postgres", "SQLite"])
        let d = PermissionDecision.answering(req, answers: ["Which DB?": ["Postgres", "SQLite"]])
        guard case .allow(let updated?, _) = d else { Issue.record("expected allow"); return }
        #expect(updated["answers"]?["Which DB?"]?.string == "Postgres, SQLite")
        #expect(updated["questions"] == input["questions"])
    }
}

@Suite struct ParsingTests {
    @Test func describesTools() {
        // Raw commands become plain phrases; the exact command stays in `detail`.
        let ls = ToolDescriber.activity(tool: "Bash", input: ["command": "ls -la\nrm x"])
        #expect(ls.progressive == "Listing files")
        #expect(ls.detail == "ls -la\nrm x")
        #expect(ToolDescriber.describe(tool: "Edit", input: ["file_path": "/a/b/App.swift"]) == "Editing App.swift")
        #expect(ToolDescriber.describe(tool: "mcp__github__create_pr", input: [:]) == "Using GitHub: create PR")
        #expect(ToolDescriber.describe(tool: "shell", input: ["command": ["bash", "-lc", "cargo test"]]) == "Running tests")
        // Antigravity tool names map to the same verbs as Claude's.
        #expect(ToolDescriber.describe(tool: "write_to_file", input: ["TargetFile": "/a/b/main.go"]) == "Writing main.go")
        let run = ToolDescriber.activity(tool: "run_command", input: ["CommandLine": "npm test"])
        #expect(run.progressive == "Running tests")
        #expect(run.detail == "npm test")
    }

    @Test func gitWorktree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let main = root.appendingPathComponent("myrepo")
        let wtGit = main.appendingPathComponent(".git/worktrees/feature")
        try FileManager.default.createDirectory(at: wtGit, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: main.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feature-x\n".write(to: wtGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try "../..\n".write(to: wtGit.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
        let wt = root.appendingPathComponent("myrepo-feature/src")
        try FileManager.default.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: \(wtGit.path)\n".write(
            to: root.appendingPathComponent("myrepo-feature/.git"), atomically: true, encoding: .utf8)

        let info = try #require(GitInfo.resolve(cwd: wt.path))
        #expect(info.branch == "feature-x")
        #expect(info.isWorktree)
        #expect(info.projectName == "myrepo")
        #expect(GitInfo.resolve(cwd: main.path)?.branch == "main")
    }

    @Test func claudeTranscript() {
        let lines = [
            #"{"type":"user","gitBranch":"dev","message":{"content":"hi"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"All done."}],"usage":{"input_tokens":10,"cache_read_input_tokens":40000,"cache_creation_input_tokens":0,"output_tokens":90}}}"#,
        ]
        let info = TranscriptReader.parseClaude(lines)
        #expect(info.lastAssistantText == "All done.")
        #expect(info.contextTokens == 40100)
        #expect(info.contextLimit == 200_000)
        #expect(info.gitBranch == "dev")
    }

    @Test func claudeTranscriptStopsAtEmptyBranch() {
        // Outside a repo the branch is "": still settled, and older lines aren't consulted.
        let lines = [
            #"{"type":"user","gitBranch":"old","message":{"content":"hi"}}"#,
            #"{"type":"assistant","gitBranch":"","message":{"content":[{"type":"text","text":"Done."}],"usage":{"input_tokens":5}}}"#,
        ]
        let info = TranscriptReader.parseClaude(lines)
        #expect(info.gitBranch == nil)
        #expect(info.lastAssistantText == "Done.")
    }

    @Test func tailSurvivesCutInsideCharacter() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        // "é" is two bytes; a 10-byte tail of the 11-byte file starts inside it.
        try Data("é\n{\"a\":1}\n".utf8).write(to: url)
        #expect(TranscriptReader.tailLines(path: url.path, maxBytes: 10) == [#"{"a":1}"#])
    }

    @Test func jsonValueDecodesEveryKind() throws {
        let v = try JSONValue.decode(Data(#"{"n":null,"t":true,"f":false,"i":1,"d":1.5,"s":"x","a":[0,"y"],"o":{"k":"v"}}"#.utf8))
        #expect(v == ["n": nil, "t": true, "f": false, "i": 1, "d": 1.5, "s": "x", "a": [0, "y"], "o": ["k": "v"]])
        // Through Codable (bridge envelopes) as well.
        #expect(try JSONDecoder().decode(JSONValue.self, from: v.encoded()) == v)
    }

    @Test func claudeLiveThinkingOnlyWhenNewest() {
        let thinking = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Check the cache first."}]}}"#
        let toolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}"#
        let toolResult = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#
        let redacted = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":""}]}}"#
        #expect(TranscriptReader.parseClaude([toolResult, thinking]).latestThinking == "Check the cache first.")
        #expect(TranscriptReader.parseClaude([thinking, toolUse]).latestThinking == nil)
        #expect(TranscriptReader.parseClaude([thinking, toolResult]).latestThinking == nil)
        #expect(TranscriptReader.parseClaude([redacted]).latestThinking == nil)
    }

    @Test func codexReasoningSummary() {
        let reasoning = #"{"type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"**Planning the patch**"}]}}"#
        let call = #"{"type":"response_item","payload":{"type":"function_call","name":"shell"}}"#
        let empty = #"{"type":"response_item","payload":{"type":"reasoning","summary":[]}}"#
        #expect(TranscriptReader.parseCodex([reasoning]).latestThinking == "**Planning the patch**")
        #expect(TranscriptReader.parseCodex([reasoning, call]).latestThinking == nil)
        #expect(TranscriptReader.parseCodex([reasoning, empty]).latestThinking == nil)
    }

    @Test func codexUsageLine() throws {
        let line =
            #"{"timestamp":"2026-10-04T13:06:19.123Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":1234,"input_tokens":1000},"model_context_window":258400},"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1791135645},"secondary":{"used_percent":3,"window_minutes":10080,"resets_at":1791722445},"plan_type":"plus"}}}"#
        let u = try #require(UsageScanner.codexUsage(line: line))
        #expect(u.tokens == 1234)
        #expect(u.limits?.windows.map(\.label) == ["5h", "7d"])
        #expect(u.limits?.windows.first?.used == 0.125)
        #expect(TranscriptReader.parseCodex([line]).contextLimit == 258_400)
    }

    @Test func claudeLimits() {
        let v: JSONValue = ["five_hour": ["utilization": 34, "resets_at": "2026-10-19T18:00:00.000Z"], "seven_day": .null]
        let limits = RateLimits.claude(v)
        #expect(limits?.windows.count == 1)
        #expect(limits?.windows.first?.used == 0.34)
        #expect(limits?.windows.first?.resetsAt != nil)
    }
}

/// Runs the real bridge binary against a real socket server.
@Suite(.serialized) struct BridgeEndToEndTests {
    static var bridgePath: String? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent(".build/debug/orby-bridge").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func runBridge(home: String, stdin: String, arguments: [String] = ["--source", "claude"]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.bridgePath!)
        p.arguments = arguments
        p.environment = ["ORBY_HOME": home, "TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0:ABC"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        try inPipe.fileHandleForWriting.close()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @Test(.enabled(if: bridgePath != nil)) func permissionRoundTrip() throws {
        // Short path: sockaddr_un caps at 104 bytes, and $TMPDIR is long on macOS.
        let home = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let received = Locked<[BridgeEnvelope]>([])
        let server = SocketServer(path: home + "/run/app.sock") { env, conn in
            received.mutate { $0.append(env) }
            conn?.reply(BridgeReply(stdout: PermissionDecision.allow().hookOutput()))
        }
        try server.start()
        defer { server.stop() }

        let out = try runBridge(
            home: home,
            stdin: #"{"hook_event_name":"PermissionRequest","session_id":"e2e","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        let json = try JSONValue.decode(Data(out.utf8))
        #expect(json["hookSpecificOutput"]?["decision"]?["behavior"]?.string == "allow")

        let env = try #require(received.value.first)
        #expect(env.expectsReply)
        #expect(env.env["ITERM_SESSION_ID"] == "w0t0p0:ABC")
        #expect(!env.processChain.isEmpty)
    }

    @Test(.enabled(if: bridgePath != nil)) func silentWhenAppNotRunning() throws {
        let out = try runBridge(
            home: "/tmp/ni-missing-\(UUID().uuidString.prefix(6))",
            stdin: #"{"hook_event_name":"PermissionRequest","session_id":"x","tool_name":"Bash"}"#)
        #expect(out.isEmpty)
    }

    @Test(.enabled(if: bridgePath != nil)) func antigravityAlwaysGetsPassthroughReply() throws {
        let home = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let args = ["--source", "antigravity", "--event", "PreToolUse"]
        let stdin = #"{"conversationId":"ag","toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}"#
        // App not running.
        #expect(try JSONValue.decode(Data(runBridge(home: home, stdin: stdin, arguments: args).utf8)) == ["decision": "allow"])

        let received = Locked<[BridgeEnvelope]>([])
        let server = SocketServer(path: home + "/run/app.sock") { env, _ in received.mutate { $0.append(env) } }
        try server.start()
        defer { server.stop() }
        #expect(try JSONValue.decode(Data(runBridge(home: home, stdin: stdin, arguments: args).utf8)) == ["decision": "allow"])
        let stop = try runBridge(home: home, stdin: #"{"conversationId":"ag","fullyIdle":true}"#, arguments: ["--source", "antigravity", "--event", "Stop"])
        #expect(try JSONValue.decode(Data(stop.utf8)) == [:])
        for _ in 0..<50 where received.value.count < 2 { usleep(20_000) }
        #expect(received.value.map(\.eventName) == ["PreToolUse", "Stop"])
        #expect(received.value.first?.sessionID == "ag")
    }

    @Test(.enabled(if: bridgePath != nil)) func nonBlockingEventGetsNoOutput() throws {
        let home = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let received = Locked<[String]>([])
        let server = SocketServer(path: home + "/run/app.sock") { env, conn in
            #expect(conn == nil)
            received.mutate { $0.append(env.eventName) }
        }
        try server.start()
        defer { server.stop() }
        let out = try runBridge(home: home, stdin: #"{"hook_event_name":"Stop","session_id":"e2e"}"#)
        #expect(out.isEmpty)
        for _ in 0..<50 where received.value.isEmpty { usleep(20_000) }
        #expect(received.value == ["Stop"])
    }
}

final class Locked<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    init(_ v: T) { _value = v }
    var value: T { lock.withLock { _value } }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&_value) } }
}
