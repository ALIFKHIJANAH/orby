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

private func todo(_ content: String, _ status: String, active: String? = nil) -> JSONValue {
    var o: [String: JSONValue] = ["content": .string(content), "status": .string(status)]
    if let active { o["activeForm"] = .string(active) }
    return .object(o)
}

private func todoWrite(_ session: String, _ todos: [JSONValue]) -> BridgeEnvelope {
    event("PreToolUse", session, ["tool_name": "TodoWrite", "tool_input": ["todos": .array(todos)]])
}

private func request(kind: RequestKind = .permission, tool: String, input: JSONValue) -> PendingRequest {
    PendingRequest(
        id: "r", sessionKey: "claude:s", kind: kind, toolName: tool, toolInput: input, summary: "",
        suggestions: [], receivedAt: Date(timeIntervalSince1970: 0))
}

@Suite struct TaskProgressTests {
    @Test func parsesClaudeTodoWrite() throws {
        let list = try #require(
            TaskProgress.parse(
                tool: "TodoWrite",
                input: [
                    "todos": [
                        todo("Read the code", "completed", active: "Reading the code"),
                        todo("Run the tests", "in_progress", active: "Running the tests"),
                        todo("Ship it", "pending"),
                    ]
                ]))
        #expect(list.total == 3)
        #expect(list.done == 1)
        #expect(list.current == "Running the tests")
        #expect(!list.isFinished)
        #expect(list.fraction == 1.0 / 3.0)
        #expect(list.items.map(\.status) == [.completed, .inProgress, .pending])
    }

    @Test func currentFallsBackToTitle() throws {
        let list = try #require(TaskProgress.parse(tool: "TodoWrite", input: ["todos": [todo("Run the tests", "in_progress")]]))
        #expect(list.current == "Run the tests")
    }

    @Test func parsesCodexUpdatePlan() throws {
        let list = try #require(
            TaskProgress.parse(
                tool: "update_plan",
                input: [
                    "plan": [
                        ["step": "Inspect", "status": "completed"],
                        ["step": "Patch", "status": "in_progress"],
                    ]
                ]))
        #expect(list.items.map(\.title) == ["Inspect", "Patch"])
        #expect(list.done == 1)
        #expect(list.current == "Patch")
    }

    @Test(arguments: ["todo_write", "todowrite"]) func aliasesResolve(tool: String) throws {
        let list = try #require(TaskProgress.parse(tool: tool, input: ["todos": [todo("A", "completed")]]))
        #expect(list.total == 1)
    }

    @Test func nonTodoToolIsNil() {
        #expect(TaskProgress.parse(tool: "Bash", input: ["command": "ls"]) == nil)
        #expect(TaskProgress.parse(tool: "Bash", input: ["todos": [todo("A", "pending")]]) == nil)
    }

    @Test func malformedInput() throws {
        #expect(TaskProgress.parse(tool: "TodoWrite", input: [:]) == nil)
        #expect(TaskProgress.parse(tool: "TodoWrite", input: ["todos": "not a list"]) == nil)
        #expect(TaskProgress.parse(tool: "update_plan", input: ["todos": [todo("A", "pending")]]) == nil)

        let list = try #require(
            TaskProgress.parse(
                tool: "TodoWrite",
                input: ["todos": [todo("", "pending"), todo("   ", "completed"), ["status": "pending"], todo("Kept", "pending")]]))
        #expect(list.items.map(\.title) == ["Kept"])
    }

    @Test func finishedAndFraction() throws {
        let empty = TaskList(items: [])
        #expect(!empty.isFinished)
        #expect(empty.fraction == 0)
        #expect(empty.current == nil)

        let all = try #require(TaskProgress.parse(tool: "TodoWrite", input: ["todos": [todo("A", "completed"), todo("B", "completed")]]))
        #expect(all.isFinished)
        #expect(all.fraction == 1)
        #expect(all.current == nil)

        let half = try #require(TaskProgress.parse(tool: "TodoWrite", input: ["todos": [todo("A", "completed"), todo("B", "pending")]]))
        #expect(!half.isFinished)
        #expect(half.fraction == 0.5)
    }
}

@Suite struct SessionTasksTests {
    @Test func todoWriteStoresAndReplacesTasks() throws {
        var engine = SessionEngine()
        _ = engine.handle(todoWrite("s", [todo("A", "in_progress"), todo("B", "pending")]), now: Date(timeIntervalSince1970: 1))
        let first = try #require(engine.sessions["claude:s"]?.tasks)
        #expect(first.items.map(\.title) == ["A", "B"])
        #expect(first.done == 0)

        _ = engine.handle(todoWrite("s", [todo("A", "completed"), todo("B", "in_progress"), todo("C", "pending")]), now: Date(timeIntervalSince1970: 2))
        let second = try #require(engine.sessions["claude:s"]?.tasks)
        #expect(second.items.map(\.title) == ["A", "B", "C"])
        #expect(second.done == 1)
        #expect(second.current == "B")
    }

    @Test func otherToolsKeepTasks() {
        var engine = SessionEngine()
        _ = engine.handle(todoWrite("s", [todo("A", "in_progress")]), now: Date(timeIntervalSince1970: 1))
        _ = engine.handle(event("PreToolUse", "s", ["tool_name": "Bash", "tool_input": ["command": "ls"]]), now: Date(timeIntervalSince1970: 2))
        #expect(engine.sessions["claude:s"]?.tasks?.total == 1)
    }

    @Test func promptClearsOnlyFinishedList() {
        var engine = SessionEngine()
        _ = engine.handle(todoWrite("s", [todo("A", "completed"), todo("B", "pending")]), now: Date(timeIntervalSince1970: 1))
        _ = engine.handle(event("UserPromptSubmit", "s", ["prompt": "keep going"]), now: Date(timeIntervalSince1970: 2))
        #expect(engine.sessions["claude:s"]?.tasks?.total == 2)

        _ = engine.handle(todoWrite("s", [todo("A", "completed"), todo("B", "completed")]), now: Date(timeIntervalSince1970: 3))
        _ = engine.handle(event("UserPromptSubmit", "s", ["prompt": "next thing"]), now: Date(timeIntervalSince1970: 4))
        #expect(engine.sessions["claude:s"]?.tasks == nil)
    }
}

@Suite struct MarkInterruptedTests {
    @Test func settlesPendingRequest() {
        var engine = SessionEngine()
        _ = engine.handle(event("PreToolUse", "s", ["tool_name": "Read", "tool_input": ["file_path": "/a"]]), now: Date(timeIntervalSince1970: 1))
        _ = engine.handle(permission("s", id: "r"), now: Date(timeIntervalSince1970: 2))
        #expect(engine.pending.map(\.id) == ["r"])

        let cancelled = engine.markInterrupted(sessionKey: "claude:s", now: Date(timeIntervalSince1970: 3))
        #expect(cancelled == ["r"])
        #expect(engine.pending.isEmpty)
        #expect(engine.sessions["claude:s"]?.phase == .waitingInput)
        #expect(engine.sessions["claude:s"]?.activity == nil)
    }

    @Test func unknownSessionIsNoop() {
        var engine = SessionEngine()
        _ = engine.handle(permission("s", id: "r"))
        #expect(engine.markInterrupted(sessionKey: "claude:nope") == [])
        #expect(engine.pending.map(\.id) == ["r"])
    }
}

@Suite struct TrustPolicyTests {
    @Test func allowsHarmlessCommandFromEngine() throws {
        var engine = SessionEngine()
        _ = engine.handle(permission("s", command: "ls", id: "r"))
        let req = try #require(engine.pending.first)
        #expect(TrustPolicy.autoAllows(req))
    }

    @Test func allowsPlainRequests() {
        #expect(TrustPolicy.autoAllows(request(tool: "Bash", input: ["command": "ls"])))
        #expect(TrustPolicy.autoAllows(request(tool: "Edit", input: ["file_path": "/tmp/p/a.swift", "old_string": "a", "new_string": "b"])))
    }

    @Test func refusesRiskyRequests() {
        #expect(!TrustPolicy.autoAllows(request(tool: "Bash", input: ["command": "rm -rf build"])))
        #expect(!TrustPolicy.autoAllows(request(tool: "Bash", input: ["command": "sudo ls"])))
        #expect(!TrustPolicy.autoAllows(request(tool: "Edit", input: ["file_path": "/tmp/p/.env", "old_string": "a", "new_string": "b"])))
    }

    @Test func refusesNonPermissionKinds() {
        #expect(!TrustPolicy.autoAllows(request(kind: .question, tool: "AskUserQuestion", input: ["questions": []])))
        #expect(!TrustPolicy.autoAllows(request(kind: .plan, tool: "ExitPlanMode", input: ["plan": "Do it"])))
        #expect(!TrustPolicy.autoAllows(request(kind: .external, tool: "run_command", input: ["CommandLine": "ls"])))
    }

    @Test func engineKindsAreRefused() throws {
        var engine = SessionEngine()
        _ = engine.handle(permission("q", tool: "AskUserQuestion", id: "q1"))
        _ = engine.handle(permission("p", tool: "ExitPlanMode", id: "p1"))
        let kinds = Dictionary(uniqueKeysWithValues: engine.pending.map { ($0.id, $0) })
        let question = try #require(kinds["q1"])
        let plan = try #require(kinds["p1"])
        #expect(question.kind == .question)
        #expect(plan.kind == .plan)
        #expect(!TrustPolicy.autoAllows(question))
        #expect(!TrustPolicy.autoAllows(plan))
    }
}

@Suite struct QuietHoursTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: hour, minute: minute))!
    }

    private func quiet(_ hour: Int, _ minute: Int = 0, _ start: Int, _ end: Int) -> Bool {
        QuietHours.contains(Self.at(hour, minute), start: start, end: end, calendar: Self.calendar)
    }

    @Test func overnightWindowWraps() {
        #expect(quiet(23, 0, 22, 8))
        #expect(quiet(3, 0, 22, 8))
        #expect(quiet(22, 0, 22, 8))
        #expect(quiet(7, 59, 22, 8))
        #expect(!quiet(8, 0, 22, 8))
        #expect(!quiet(12, 0, 22, 8))
        #expect(!quiet(21, 59, 22, 8))
    }

    @Test func daytimeWindow() {
        #expect(quiet(9, 0, 9, 17))
        #expect(quiet(16, 59, 9, 17))
        #expect(!quiet(17, 0, 9, 17))
        #expect(!quiet(8, 59, 9, 17))
        #expect(!quiet(23, 0, 9, 17))
    }

    @Test(arguments: [0, 3, 12, 22]) func equalBoundsMeanNoQuietHours(hour: Int) {
        #expect(!quiet(hour, 0, 22, 22))
        #expect(!quiet(hour, 0, 0, 0))
    }
}
