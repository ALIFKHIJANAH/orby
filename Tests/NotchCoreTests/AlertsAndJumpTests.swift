import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func limits(_ used: Double, agent: AgentKind = .claude, label: String = "5h", resets: Date? = nil) -> [RateLimits] {
    [RateLimits(provider: agent, plan: nil, windows: [UsageWindow(label: label, used: used, resetsAt: resets)], fetchedAt: Date())]
}

private func hook(_ event: String, session: String, extra: [String: JSONValue] = [:], expectsReply: Bool = false) -> BridgeEnvelope {
    var payload: [String: JSONValue] = ["hook_event_name": .string(event), "session_id": .string(session), "cwd": "/tmp/proj"]
    payload.merge(extra) { _, new in new }
    return BridgeEnvelope(id: UUID().uuidString, source: "claude", payload: .object(payload), env: [:], expectsReply: expectsReply)
}

@Suite struct UsageAlertTests {
    @Test func firstReadingIsABaseline() {
        var t = UsageAlertTracker()
        #expect(t.check(limits(0.9)).isEmpty)
        #expect(t.check(limits(0.92)).isEmpty)
    }

    @Test func alertsOncePerThresholdAsUsageClimbs() {
        var t = UsageAlertTracker()
        _ = t.check(limits(0.5))
        #expect(t.check(limits(0.81)).map(\.threshold) == [0.8])
        #expect(t.check(limits(0.85)).isEmpty)
        let high = t.check(limits(0.97))
        #expect(high.map(\.threshold) == [0.95])
        #expect(high.first?.title == "Claude Code 5h limit at 97%")
        #expect(t.check(limits(0.99)).isEmpty)
    }

    @Test func jumpingStraightPastBothAlertsOnceAtTheTop() {
        var t = UsageAlertTracker()
        _ = t.check(limits(0.1))
        #expect(t.check(limits(0.96)).map(\.threshold) == [0.95])
    }

    @Test func aResetReArmsTheThresholds() {
        var t = UsageAlertTracker()
        _ = t.check(limits(0.5))
        #expect(t.check(limits(0.82)).count == 1)
        _ = t.check(limits(0.03))
        #expect(t.check(limits(0.8)).count == 1)
    }

    @Test func windowsAreTrackedSeparatelyAndStaleOnesSkipped() {
        var t = UsageAlertTracker()
        let past = Date().addingTimeInterval(-60)
        _ = t.check(limits(0.5, agent: .codex, label: "weekly") + limits(0.5, resets: past))
        let out = t.check(limits(0.9, agent: .codex, label: "weekly") + limits(0.9, resets: past))
        #expect(out.map(\.agent) == [.codex])
    }

    @Test func relativeResetText() {
        let now = Date()
        #expect(UsageWindow.relative(now.addingTimeInterval(-5), now: now) == "now")
        #expect(UsageWindow.relative(now.addingTimeInterval(125 * 60), now: now) == "in 2h 5m")
        #expect(UsageWindow.relative(now.addingTimeInterval(2 * 86400 + 3 * 3600), now: now) == "in 2d 3h")
    }
}

@Suite struct JumpTargetTests {
    @Test func prefersTheSessionWaitingLongest() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", session: "busy", extra: ["prompt": "x"]))
        _ = engine.handle(hook("PermissionRequest", session: "first", extra: ["tool_name": "Bash", "tool_input": ["command": "ls"]], expectsReply: true))
        _ = engine.handle(hook("PermissionRequest", session: "second", extra: ["tool_name": "Bash", "tool_input": ["command": "ls"]], expectsReply: true))
        _ = engine.handle(hook("Stop", session: "done"))
        #expect(SessionEngine.jumpTarget(engine.orderedSessions)?.sessionID == "first")
    }

    @Test func fallsBackToTheLatestUnreadFinishedSession() {
        var engine = SessionEngine()
        _ = engine.handle(hook("Stop", session: "old"))
        _ = engine.handle(hook("Stop", session: "new"))
        _ = engine.handle(hook("UserPromptSubmit", session: "busy", extra: ["prompt": "x"]))
        #expect(SessionEngine.jumpTarget(engine.orderedSessions)?.sessionID == "new")
        engine.markRead(sessionKey: "claude:new")
        #expect(SessionEngine.jumpTarget(engine.orderedSessions)?.sessionID == "old")
    }

    @Test func nothingToJumpTo() {
        var engine = SessionEngine()
        _ = engine.handle(hook("UserPromptSubmit", session: "busy", extra: ["prompt": "x"]))
        #expect(SessionEngine.jumpTarget(engine.orderedSessions) == nil)
    }
}
