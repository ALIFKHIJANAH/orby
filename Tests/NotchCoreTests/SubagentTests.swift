import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func hook(
    _ event: String, session: String = "s1", source: String = "claude", extra: [String: JSONValue] = [:], env: [String: String] = [:],
    expectsReply: Bool = false, id: String = UUID().uuidString
) -> BridgeEnvelope {
    var payload: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": .string(session), "cwd": "/tmp/proj"]
    payload.merge(extra) { _, new in new }
    return BridgeEnvelope(id: id, source: source, payload: .object(payload), env: env, expectsReply: expectsReply)
}

@Suite struct SubagentTests {
    let key = "claude:s1"

    @Test func claudeSubagentLifecycle() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", extra: ["prompt": "Find the bug"]))
        _ = engine.handle(hook("PreToolUse", extra: ["tool_name": "Agent", "tool_input": ["description": "Find the auth code", "subagent_type": "Explore"]]))
        let main = engine.sessions[key]?.activity

        let start = engine.handle(hook("SubagentStart", extra: ["agent_id": "a1", "agent_type": "Explore"]))
        #expect(start.startedSubagent == "a1")
        #expect(engine.sessions[key]?.subagents.map(\.id) == ["a1"])
        #expect(engine.sessions[key]?.subagents.first?.type == "Explore")
        #expect(engine.sessions[key]?.activeSubagents == 1)

        // Its tool shows on its own line; the main agent is still delegating.
        let pre = engine.handle(hook("PreToolUse", extra: ["agent_id": "a1", "tool_name": "Read", "tool_input": ["file_path": "/tmp/proj/auth.ts"]]))
        #expect(pre.startedSubagent == nil)
        #expect(engine.sessions[key]?.subagents.first?.activity?.progressive == "Reading auth.ts")
        #expect(engine.sessions[key]?.activity == main)
        #expect(engine.sessions[key]?.phase == .working)

        _ = engine.handle(hook("PostToolUse", extra: ["agent_id": "a1", "tool_name": "Read", "tool_input": ["file_path": "/tmp/proj/auth.ts"]]))
        #expect(engine.sessions[key]?.subagents.first?.activity == nil)
        #expect(engine.sessions[key]?.phase == .working)
        #expect(engine.sessions[key]?.activity == main)

        engine.describeSubagent("a1", in: key, type: nil, task: "Find the auth code")
        #expect(engine.sessions[key]?.subagents.first?.task == "Find the auth code")
        #expect(engine.sessions[key]?.subagents.first?.type == "Explore")

        _ = engine.handle(hook("SubagentStop", extra: ["agent_id": "a1"]))
        #expect(engine.sessions[key]?.subagents.isEmpty == true)
    }

    @Test func subagentToDoListDoesNotReplaceTheMainOne() throws {
        var engine = SessionEngine()
        let todos: JSONValue = ["todos": [["content": "Main step", "status": "in_progress", "activeForm": "Doing the main step"]]]
        _ = engine.handle(hook("PreToolUse", extra: ["tool_name": "TodoWrite", "tool_input": todos]))
        let sub: JSONValue = ["todos": [["content": "Sub step", "status": "pending", "activeForm": "Doing the sub step"]]]
        _ = engine.handle(hook("PreToolUse", extra: ["agent_id": "a1", "tool_name": "TodoWrite", "tool_input": sub]))
        #expect(try #require(engine.sessions[key]?.tasks).items.map(\.title) == ["Main step"])
    }

    @Test func stopClearsSubagentsAndALaterToolBringsOneBack() {
        var engine = SessionEngine()
        _ = engine.handle(hook("SubagentStart", extra: ["agent_id": "a1"]))
        _ = engine.handle(hook("SubagentStart", extra: ["agent_id": "a2"]))
        _ = engine.handle(hook("Stop"))
        #expect(engine.sessions[key]?.subagents.isEmpty == true)

        // A background subagent keeps going after the turn ends.
        let out = engine.handle(hook("PreToolUse", extra: ["agent_id": "a2", "agent_type": "Explore", "tool_name": "Grep", "tool_input": ["pattern": "x"]]))
        #expect(out.startedSubagent == "a2")
        #expect(engine.sessions[key]?.subagents.map(\.id) == ["a2"])
        #expect(engine.sessions[key]?.subagents.first?.type == "Explore")
        #expect(engine.sessions[key]?.phase == .done)
        // A stop for a subagent we no longer list is a no-op.
        _ = engine.handle(hook("SubagentStop", extra: ["agent_id": "a1"]))
        #expect(engine.sessions[key]?.subagents.map(\.id) == ["a2"])
    }

    @Test func unnamedSubagentsStillCount() {
        var engine = SessionEngine()
        _ = engine.handle(hook("SubagentStart"))
        _ = engine.handle(hook("SubagentStart"))
        #expect(engine.sessions[key]?.subagents.map(\.id) == ["#1", "#2"])
        _ = engine.handle(hook("SubagentStop"))
        #expect(engine.sessions[key]?.subagents.map(\.id) == ["#2"])
        _ = engine.handle(hook("SubagentStart"))
        #expect(engine.sessions[key]?.subagents.map(\.id) == ["#2", "#3"])
    }

    @Test func subagentPermissionKeepsMainSessionWaiting() {
        var engine = SessionEngine()
        _ = engine.handle(hook("SubagentStart", extra: ["agent_id": "a1"]))
        _ = engine.handle(
            hook("PermissionRequest", extra: ["agent_id": "a1", "tool_name": "Bash", "tool_input": ["command": "rm -rf build"]],
                 expectsReply: true, id: "p1"))
        #expect(engine.sessions[key]?.phase == .needsApproval)
        #expect(engine.pending.first?.agentScope == "a1")
        #expect(engine.sessions[key]?.subagents.first?.activity != nil)
    }

    @Test func interruptClearsSubagents() {
        var engine = SessionEngine()
        _ = engine.handle(hook("SubagentStart", extra: ["agent_id": "a1"]))
        _ = engine.markInterrupted(sessionKey: key)
        #expect(engine.sessions[key]?.subagents.isEmpty == true)
    }

    @Test func metaPathSitsBesideTheTranscript() {
        let path = SubagentMeta.path(transcript: "/u/.claude/projects/-p/abc.jsonl", agentID: "a1f")
        #expect(path == "/u/.claude/projects/-p/abc/subagents/agent-a1f.meta.json")
        let meta = SubagentMeta.parse(["agentType": "Explore", "description": "Find the auth code", "toolUseId": "toolu_1"])
        #expect(meta.type == "Explore")
        #expect(meta.task == "Find the auth code")
        #expect(SubagentMeta.parse(["agentType": ""]).type == nil)
    }

    @Test func orcaTerminalHandleIsKept() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", extra: ["prompt": "hi"], env: ["ORCA_TERMINAL_HANDLE": "term_1"]))
        _ = engine.handle(hook("Stop"))
        #expect(engine.sessions[key]?.terminal.orcaTerminal == "term_1")
    }
}

@Suite struct OrcaFleetTests {
    // Trimmed from real `orca orchestration worker-list --json` / `task-list --run <id> --json` output.
    let workerList: JSONValue = [
        "ok": true,
        "result": ["workers": [
            ["dispatchId": "ctx_2", "taskId": "task_b", "runId": "run_1", "agentTerminalHandle": "term_w2", "workerState": "running"],
            ["dispatchId": "ctx_1", "taskId": "task_a", "runId": "run_1", "agentTerminalHandle": "term_w1", "workerState": "succeeded"],
            ["dispatchId": "ctx_0", "taskId": "task_old", "runId": "run_0", "agentTerminalHandle": "term_w1", "workerState": "succeeded"],
        ]],
    ]
    let taskList: JSONValue = [
        "ok": true,
        "result": ["runId": "run_1", "tasks": [
            ["id": "task_a", "created_by_terminal_handle": "term_coord", "task_title": "Review BE PR #146", "display_name": "Review BE PR #146"],
            ["id": "task_b", "created_by_terminal_handle": "term_coord", "task_title": "Review FE PR #105", "display_name": ""],
        ]],
    ]

    @Test func parsesWorkersAndTasks() {
        let d = OrcaFleet.dispatches(workerList)
        #expect(d["term_w2"] == OrcaFleet.Dispatch(run: "run_1", task: "task_b"))
        // Newest first: a reused terminal keeps its latest dispatch.
        #expect(d["term_w1"] == OrcaFleet.Dispatch(run: "run_1", task: "task_a"))
        let t = OrcaFleet.tasks(taskList)
        #expect(t["task_a"] == OrcaFleet.TaskInfo(parent: "term_coord", title: "Review BE PR #146"))
        // An empty display name falls back to the title.
        #expect(t["task_b"]?.title == "Review FE PR #105")
        #expect(OrcaFleet.dispatches(["ok": false]).isEmpty)
    }

    private func session(_ id: String, handle: String?) -> AgentSession {
        var s = AgentSession(agent: .claude, sessionID: id, cwd: "/tmp/proj", now: Date())
        s.terminal.orcaTerminal = handle
        return s
    }

    @Test func nestsWorkersUnderTheirCoordinator() {
        let coord = session("c", handle: "term_coord")
        let w1 = session("w1", handle: "term_w1")
        let w2 = session("w2", handle: "term_w2")
        let other = session("x", handle: nil)
        let workers = [
            "term_w1": OrcaWorker(handle: "term_w1", parent: "term_coord", task: "A"),
            "term_w2": OrcaWorker(handle: "term_w2", parent: "term_w1", task: "B"),
        ]
        let nested = OrcaFleet.nest([w2, coord, other, w1], workers: workers)
        #expect(nested.top.map(\.id) == [coord.id, other.id])
        #expect(nested.children[coord.id]?.map(\.id) == [w1.id])
        // A worker's own worker nests under it.
        #expect(nested.children[w1.id]?.map(\.id) == [w2.id])
    }

    @Test func workerWithoutItsCoordinatorStaysTopLevel() {
        let w1 = session("w1", handle: "term_w1")
        let nested = OrcaFleet.nest([w1], workers: ["term_w1": OrcaWorker(handle: "term_w1", parent: "term_gone", task: "A")])
        #expect(nested.top.map(\.id) == [w1.id])
        #expect(nested.children.isEmpty)
    }

    @Test func cycleInBadDataHidesNothing() {
        let a = session("a", handle: "term_a")
        let b = session("b", handle: "term_b")
        let workers = [
            "term_a": OrcaWorker(handle: "term_a", parent: "term_b", task: nil),
            "term_b": OrcaWorker(handle: "term_b", parent: "term_a", task: nil),
        ]
        let nested = OrcaFleet.nest([a, b], workers: workers)
        #expect(nested.top.map(\.id) == [a.id, b.id])
    }
}
