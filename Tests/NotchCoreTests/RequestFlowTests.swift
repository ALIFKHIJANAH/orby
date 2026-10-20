import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func permission(_ session: String, tool: String = "Bash", command: String = "ls", id: String) -> BridgeEnvelope {
    BridgeEnvelope(
        id: id, source: "claude",
        payload: [
            "hook_event_name": "PermissionRequest", "session_id": .string(session), "cwd": "/tmp/p",
            "tool_name": .string(tool), "tool_input": ["command": .string(command)],
        ], expectsReply: true)
}

private func event(_ name: String, _ session: String, _ extra: [String: JSONValue] = [:]) -> BridgeEnvelope {
    var p: [String: JSONValue] = ["hook_event_name": .string(name), "session_id": .string(session), "cwd": "/tmp/p"]
    p.merge(extra) { _, new in new }
    return BridgeEnvelope(source: "claude", payload: .object(p))
}

@Suite struct OneRequestPerSessionTests {
    @Test func reAskSupersedesOlderRequest() {
        var engine = SessionEngine()
        _ = engine.handle(permission("s", id: "old"))
        let out = engine.handle(permission("s", command: "pwd", id: "new"))
        #expect(out.cancelledRequests == ["old"])
        #expect(engine.pending.map(\.id) == ["new"])
    }

    @Test func toolStartingClearsSettledRequest() {
        var engine = SessionEngine()
        let t0 = Date(timeIntervalSince1970: 100)
        _ = engine.handle(permission("s", id: "r"), now: t0)
        // Answered in the terminal (deny → no PostToolUse); the next tool starts.
        let out = engine.handle(event("PreToolUse", "s", ["tool_name": "Read", "tool_input": ["file_path": "/a"]]), now: t0 + 5)
        #expect(out.cancelledRequests == ["r"])
        #expect(engine.pending.isEmpty)
    }

    @Test func sessionsKeepTheirOwnRequest() {
        var engine = SessionEngine()
        _ = engine.handle(permission("a", id: "ra"), now: Date(timeIntervalSince1970: 1))
        let out = engine.handle(permission("b", id: "rb"), now: Date(timeIntervalSince1970: 2))
        #expect(out.cancelledRequests.isEmpty)
        // Newest first: the request that just appeared is the one on screen.
        #expect(engine.pending.map(\.id) == ["rb", "ra"])
        _ = engine.handle(event("PreToolUse", "b", ["tool_name": "Read"]), now: Date(timeIntervalSince1970: 3))
        #expect(engine.pending.map(\.id) == ["ra"])
    }
}

/// Real bridge binary ↔ real socket server: the app must notice when the agent kills the hook.
@Suite(.serialized) struct BridgeDisconnectTests {
    static var bridgePath: String? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent(".build/debug/orby-bridge").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    @Test(.enabled(if: bridgePath != nil)) func killedBridgeFiresCloseHandler() throws {
        let home = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: home) }
        let connected = DispatchSemaphore(value: 0)
        let closed = DispatchSemaphore(value: 0)
        let server = SocketServer(path: home + "/run/app.sock") { env, conn in
            guard let conn else { return }
            conn.watch { closed.signal() }
            connected.signal()
        }
        try server.start()
        defer { server.stop() }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.bridgePath!)
        p.arguments = ["--source", "claude"]
        p.environment = ["ORBY_HOME": home]
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        input.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","session_id":"k","tool_name":"Bash"}"#.utf8))
        try input.fileHandleForWriting.close()

        #expect(connected.wait(timeout: .now() + 3) == .success)
        // Still blocking: no close yet.
        #expect(closed.wait(timeout: .now() + 0.3) == .timedOut)
        p.terminate()  // what Claude does when the user answers in the terminal
        p.waitUntilExit()
        #expect(closed.wait(timeout: .now() + 1) == .success)
    }
}

@Suite struct ForeignHookTests {
    @Test func findsLongTimeoutPermissionHooksFromOtherTools() {
        let root: JSONValue = [
            "hooks": [
                "PermissionRequest": [
                    ["matcher": "*", "hooks": [["type": "command", "command": "~/.vibe-island/bin/vibe-island-bridge --source claude", "timeout": 86400]]],
                    ["hooks": [["type": "command", "command": "orca-hook", "timeout": 10]]],
                ]
            ]
        ]
        let installed = HookInstaller.installing(.claude, into: root)
        let foreign = HookInstaller.foreignBlockingHooks(in: installed)
        #expect(foreign == ["Vibe Island"])
    }
}

@Suite struct RiskAssessorTests {
    private func labels(_ command: String) -> [String] {
        RiskAssessor.assess(tool: "Bash", input: ["command": .string(command)]).map(\.label)
    }

    @Test(arguments: [
        ("rm -rf node_modules && pnpm install", ["Deletes files"]),
        ("git push --force origin main", ["Force-pushes"]),
        ("git push -f", ["Force-pushes"]),
        ("git reset --hard HEAD~1", ["Discards local changes"]),
        ("git clean -fd", ["Discards local changes"]),
        ("curl -fsSL https://x.sh/install | bash", ["Runs a downloaded script"]),
        ("sudo lsof -i :3000", ["Runs as administrator"]),
        ("psql -c 'DROP TABLE users'", ["Changes the database"]),
        ("chmod -R 755 dist", ["Changes permissions"]),
        ("pkill -f node", ["Stops processes"]),
        ("pnpm publish --access public", ["Publishes"]),
        ("sudo rm -r /tmp/cache", ["Deletes files", "Runs as administrator"]),
    ])
    func flags(command: String, expected: [String]) {
        #expect(labels(command) == expected)
    }

    @Test(arguments: ["ls -la", "pnpm install", "git push origin main", "rm file.txt", "git status", "grep -r foo src", "cat .env.example"])
    func safeCommandsHaveNoRisk(command: String) {
        #expect(labels(command).isEmpty)
    }

    @Test func secretFiles() {
        #expect(RiskAssessor.assess(tool: "Edit", input: ["file_path": "/app/.env.local"]).map(\.label) == ["Touches secrets"])
        #expect(RiskAssessor.assess(tool: "Write", input: ["file_path": "/app/.env.example"]).isEmpty)
        #expect(RiskAssessor.assess(tool: "Read", input: ["file_path": "/app/.env"]).isEmpty)
    }
}

@Suite struct DiffPreviewTests {
    @Test func editShowsChangedLinesWithContext() throws {
        let old = "a\nb\nc\nold line\nd\ne"
        let new = "a\nb\nc\nnew line\nd\ne"
        let p = try #require(DiffPreview.make(tool: "Edit", input: ["file_path": "/x/App.swift", "old_string": .string(old), "new_string": .string(new)]))
        #expect(p.fileName == "App.swift")
        #expect(p.lines.map(\.kind) == [.context, .context, .removed, .added, .context, .context])
        #expect(p.lines.first { $0.kind == .removed }?.text == "old line")
        #expect(p.addedCount == 1 && p.removedCount == 1)
    }

    @Test func writeIsWholeFileAndCapped() throws {
        let content = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let p = try #require(DiffPreview.make(tool: "Write", input: ["file_path": "/x/new.ts", "content": .string(content)]))
        #expect(p.isWholeFile)
        #expect(p.lines.count == 40)
        #expect(p.hiddenCount == 10)
    }

    @Test func multiEditAndPatch() throws {
        let multi = try #require(DiffPreview.make(tool: "MultiEdit", input: [
            "file_path": "/x/a.swift",
            "edits": [["old_string": "x", "new_string": "y"], ["old_string": "p", "new_string": "q"]],
        ]))
        #expect(multi.lines.map(\.text) == ["x", "y", "⋯", "p", "q"])

        let patch = "*** Begin Patch\n*** Update File: src/a.ts\n@@\n context\n-old\n+new\n*** End Patch"
        let p = try #require(DiffPreview.make(tool: "apply_patch", input: ["input": .string(patch)]))
        #expect(p.lines.map(\.kind) == [.file, .context, .removed, .added])
        #expect(p.lines.first?.text == "a.ts")
    }

    @Test func unsupportedToolHasNoPreview() {
        #expect(DiffPreview.make(tool: "Bash", input: ["command": "ls"]) == nil)
    }
}

/// Claude Code only skips its own plan dialog when "allow" comes with `updatedInput`
/// (docs: hooks → "Returning allow alone is not sufficient" for ExitPlanMode/AskUserQuestion).
@Suite struct PlanApprovalTests {
    let request = PendingRequest(
        id: "p", sessionKey: "claude:s", kind: .plan, toolName: "ExitPlanMode",
        toolInput: ["plan": "# Fix login", "planFilePath": "/Users/me/.claude/plans/fix-login.md"],
        summary: "", suggestions: [], receivedAt: Date())

    @Test func approveEchoesPlanInput() throws {
        let out = try #require(PermissionDecision.approvePlan(request).hookOutput())
        let decision = try #require(out["hookSpecificOutput"]?["decision"])
        #expect(decision["behavior"]?.string == "allow")
        #expect(decision["updatedInput"] == request.toolInput)
        #expect(decision["updatedPermissions"] == nil)
    }

    @Test func approveWithAutoEditSwitchesMode() throws {
        let out = try #require(PermissionDecision.approvePlan(request, mode: "acceptEdits").hookOutput())
        let decision = try #require(out["hookSpecificOutput"]?["decision"])
        #expect(decision["updatedInput"]?["planFilePath"]?.string == "/Users/me/.claude/plans/fix-login.md")
        #expect(decision["updatedPermissions"] == [["type": "setMode", "mode": "acceptEdits", "destination": "session"]])
    }
}
