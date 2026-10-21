import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

/// Loads the real plugin sources in Node with a stand-in for the agent's plugin API, and lets
/// them talk to the real bridge and socket server.
@Suite(.serialized) struct PluginEndToEndTests {
    static let node: String? = {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        return dirs.map { $0 + "/node" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Node can load the TypeScript sources (Pi, Command Code) once it strips types.
    static let nodeStripsTypes: Bool = {
        guard let node else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = ["--experimental-strip-types", "-e", "const x: number = 1"]
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }()

    static var ready: Bool { node != nil && BridgeEndToEndTests.bridgePath != nil }

    /// A temp home with the bridge where the plugins look for it, and the app's socket server.
    final class Harness: @unchecked Sendable {
        let home = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        let received = Locked<[BridgeEnvelope]>([])
        let closed = Locked<[String]>([])
        var server: SocketServer!

        init(decide: @escaping @Sendable (BridgeEnvelope) -> JSONValue?) throws {
            let bin = home + "/.orby/bin"
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: bin + "/orby-bridge", withDestinationPath: BridgeEndToEndTests.bridgePath!)
            let received = received, closed = closed
            server = SocketServer(path: home + "/.orby/run/app.sock") { env, conn in
                received.mutate { $0.append(env) }
                guard let conn else { return }
                if let reply = decide(env) {
                    conn.reply(BridgeReply(stdout: reply))
                } else {
                    // Left waiting, as if the user hadn't decided yet.
                    let tool = env.payload["tool_name"]?.string ?? ""
                    conn.watch { closed.mutate { $0.append(tool) } }
                }
            }
            try server.start()
        }

        deinit {
            server.stop()
            try? FileManager.default.removeItem(atPath: home)
        }

        /// Writes the plugin and the driver script, runs the driver, returns its stdout.
        func run(plugin: String, pluginName: String, driver: String, stripTypes: Bool = false) throws -> String {
            let pluginPath = home + "/" + pluginName
            let driverPath = home + "/driver.mjs"
            try Data(plugin.utf8).write(to: URL(fileURLWithPath: pluginPath))
            try Data(driver.utf8).write(to: URL(fileURLWithPath: driverPath))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: PluginEndToEndTests.node!)
            p.arguments = (stripTypes ? ["--experimental-strip-types", "--no-warnings"] : []) + [driverPath, pluginPath]
            p.environment = ["HOME": home, "ORBY_HOME": home + "/.orby", "PATH": "/usr/bin:/bin"]
            let out = Pipe()
            p.standardOutput = out
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)
            // Node waits for every bridge to exit; give the server a moment to read the last lines.
            usleep(150_000)
            return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }

        var events: [String] { received.value.map(\.eventName) }
    }

    @Test(.enabled(if: ready)) func openCodePermissionsQuestionsAndTerminalAnswers() throws {
        let h = try Harness { env in
            guard env.eventName == "PermissionRequest" else { return nil }
            switch env.payload["tool_name"]?.string {
            case "bash":
                return PermissionDecision.allow(updatedPermissions: env.payload["permission_suggestions"]?.array).hookOutput()
            case "AskUserQuestion":
                let request = PendingRequest(
                    id: env.id, sessionKey: "", kind: .question, toolName: "AskUserQuestion",
                    toolInput: env.payload["tool_input"] ?? [:], summary: "", suggestions: [], receivedAt: Date())
                return PermissionDecision.answering(request, answers: ["Which DB?": ["Postgres"]]).hookOutput()
            default:
                return nil
            }
        }
        let driver = #"""
            const { OrbyPlugin } = await import(process.argv[2])
            const replies = []
            const ok = (kind) => async (args) => (replies.push({ kind, ...args }), {})
            const client = { permission: { reply: ok("permission") }, question: { reply: ok("question"), reject: ok("reject") } }
            const until = async (done) => { for (let i = 0; i < 200 && !done(); i++) await new Promise((r) => setTimeout(r, 25)) }
            const h = await OrbyPlugin({ client, directory: "/tmp/proj", serverUrl: new URL("http://127.0.0.1:9") })
            const event = (type, properties) => h.event({ event: { type, properties } })

            await event("session.created", { info: { id: "ses1", directory: "/tmp/proj" } })
            await h["chat.message"]({ sessionID: "ses1" }, { message: { model: { modelID: "big-model" } }, parts: [{ type: "text", text: "Clean up" }] })
            await event("session.created", { info: { id: "sub1", parentID: "ses1", directory: "/tmp/proj" } })
            await h["tool.execute.before"]({ tool: "bash", sessionID: "sub1", callID: "c1" }, { args: { command: "rm -rf build" } })
            await event("permission.asked", {
              id: "per1", sessionID: "sub1", permission: "bash", patterns: ["rm -rf build"], always: ["rm *"], metadata: {},
              tool: { messageID: "m1", callID: "c1" },
            })
            await until(() => replies.length >= 1)
            await h["tool.execute.after"]({ tool: "bash", sessionID: "sub1", callID: "c1" }, {})
            await event("session.status", { sessionID: "sub1", status: { type: "idle" } })
            await event("question.asked", {
              id: "que1", sessionID: "ses1",
              questions: [{ question: "Which DB?", header: "DB", options: [{ label: "SQLite" }, { label: "Postgres" }] }],
            })
            await until(() => replies.length >= 2)
            // Answered in OpenCode's own prompt: the waiting bridge is released.
            await event("permission.asked", { id: "per2", sessionID: "ses1", permission: "edit", patterns: ["a.swift"], metadata: {} })
            await new Promise((r) => setTimeout(r, 300))
            await event("permission.replied", { sessionID: "ses1", requestID: "per2", reply: "once" })
            await event("session.status", { sessionID: "ses1", status: { type: "idle" } })
            await event("session.idle", { sessionID: "ses1" })
            await event("session.deleted", { info: { id: "ses1" } })
            console.log(JSON.stringify(replies))
            """#
        let out = try h.run(plugin: PluginInstaller.source(for: .opencode)!, pluginName: "orby.mjs", driver: driver)
        #expect(
            try JSONValue.decode(Data(out.utf8)) == [
                ["kind": "permission", "requestID": "per1", "reply": "always"],
                ["kind": "question", "requestID": "que1", "answers": [["Postgres"]]],
            ])

        #expect(
            h.events == [
                "SessionStart", "UserPromptSubmit", "SubagentStart", "PreToolUse", "PermissionRequest", "PostToolUse", "SubagentStop",
                "PermissionRequest", "PermissionRequest", "Stop", "SessionEnd",
            ])
        let envs = h.received.value
        try #require(envs.count == 11)
        #expect(envs.allSatisfy { $0.source == "opencode" && $0.sessionID == "ses1" })
        #expect(envs[1].payload["prompt"]?.string == "Clean up")
        #expect(envs[1].payload["model"]?.string == "big-model")
        let permission = envs[4]
        #expect(permission.expectsReply)
        #expect(permission.payload["agent_id"]?.string == "sub1")
        #expect(permission.payload["tool_name"]?.string == "bash")
        #expect(permission.payload["tool_input"] == ["command": "rm -rf build"])
        let rule = permission.payload["permission_suggestions"]?.array?.first?["rules"]?.array?.first
        #expect(rule == ["toolName": "bash", "ruleContent": "rm *"])
        let options = envs[7].payload["tool_input"]?["questions"]?.array?.first?["options"]?.array
        #expect(options?.compactMap { $0["label"]?.string } == ["SQLite", "Postgres"])
        #expect(envs[8].payload["tool_input"]?["patterns"] == ["a.swift"])
        #expect(h.closed.value == ["edit"])
    }

    @Test(.enabled(if: ready && nodeStripsTypes)) func piReportsStatus() throws {
        let h = try Harness { _ in nil }
        let driver = #"""
            const ext = (await import(process.argv[2])).default
            const handlers = {}
            ext({ on: (name, fn) => (handlers[name] ??= []).push(fn) })
            const ctx = { cwd: "/tmp/proj", sessionManager: { getSessionId: () => "pi-1" } }
            const fire = (name, e = {}) => (handlers[name] ?? []).forEach((fn) => fn(e, ctx))
            const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

            fire("session_start", { reason: "startup" })
            fire("session_start", { reason: "reload" })
            fire("before_agent_start", { prompt: "Refactor" })
            fire("agent_start")
            fire("tool_call", { toolName: "bash", toolCallId: "t1", input: { command: "ls" } })
            fire("tool_execution_end", { toolName: "bash", isError: true })
            fire("agent_end")
            fire("agent_settled")
            // Older Pi without agent_settled: agent_end, an automatic retry, then the real end.
            fire("before_agent_start", { prompt: "Again" })
            fire("agent_end")
            fire("agent_start")
            fire("agent_end")
            await sleep(1800)
            fire("session_shutdown")
            """#
        _ = try h.run(plugin: PluginInstaller.source(for: .pi)!, pluginName: "orby.ts", driver: driver, stripTypes: true)
        #expect(
            h.events == [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUseFailure", "Stop", "UserPromptSubmit", "Stop", "SessionEnd",
            ])
        let envs = h.received.value
        try #require(envs.count == 8)
        #expect(envs.allSatisfy { $0.source == "pi" && $0.sessionID == "pi-1" && !$0.expectsReply })
        #expect(envs[2].payload["tool_input"] == ["command": "ls"])
        #expect(envs[0].payload["cwd"]?.string == "/tmp/proj")
    }

    @Test(.enabled(if: ready && nodeStripsTypes)) func commandCodeModAnswersPermissions() throws {
        let h = try Harness { env in env.eventName == "PermissionRequest" ? PermissionDecision.allow().hookOutput() : nil }
        let driver = #"""
            const mod = (await import(process.argv[2])).default
            const events = {}
            let hooks
            mod({ cwd: "/tmp/proj", on: (name, fn) => (events[name] ??= []).push(fn), hooks: (h) => (hooks = h) })
            // No session yet: Command Code's own prompt.
            const early = await hooks.onPermissionRequest({ toolName: "shell_command", input: { command: "ls" } })
            hooks.transformInput({ text: "Ship it" })
            events.run_start.forEach((fn) => fn({ sessionId: "cc-1" }))
            const asked = await hooks.onPermissionRequest({ toolName: "shell_command", input: { command: "git push" }, description: "Push" })
            const safety = await hooks.onPermissionRequest({ toolName: "shell_command", input: {}, description: "Outside the project", isSafetyPrompt: true })
            hooks.onSessionEnd({ reason: "reload" })
            hooks.onSessionEnd({ reason: "shutdown" })
            await new Promise((r) => setTimeout(r, 300))
            console.log(JSON.stringify([early ?? null, asked ?? null, safety ?? null]))
            """#
        let out = try h.run(plugin: PluginInstaller.source(for: .commandcode)!, pluginName: "orby.ts", driver: driver, stripTypes: true)
        #expect(try JSONValue.decode(Data(out.utf8)) == [nil, "allow", nil])
        #expect(h.events == ["UserPromptSubmit", "PermissionRequest", "Notification", "SessionEnd"])
        let envs = h.received.value
        try #require(envs.count == 4)
        #expect(envs.allSatisfy { $0.source == "commandcode" && $0.sessionID == "cc-1" })
        #expect(envs[0].payload["prompt"]?.string == "Ship it")
        #expect(envs[1].payload["tool_input"] == ["command": "git push"])
        #expect(envs[2].payload["notification_type"]?.string == "permission_prompt")
    }
}
