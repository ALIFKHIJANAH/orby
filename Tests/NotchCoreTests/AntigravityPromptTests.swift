import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func agy(_ event: String, conv: String = "c1", step: Int? = nil, command: String? = nil) -> BridgeEnvelope {
    var p: [String: JSONValue] = [
        "hook_event_name": .string(event), "conversationId": .string(conv), "workspacePaths": ["/tmp/proj"],
    ]
    if let step { p["stepIdx"] = .number(Double(step)) }
    if let command { p["toolCall"] = ["name": "run_command", "args": ["CommandLine": .string(command), "Cwd": "/tmp/proj"]] }
    return BridgeEnvelope(source: "antigravity", payload: .object(p))
}

@Suite struct AntigravityLogTests {
    @Test func parsesRealLines() {
        #expect(
            AntigravityLog.parse(
                #"I1020 03:09:29.953108    7203 tool_confirmation_manager.go:226] Surfacing tool confirmation: "RunCommand" at step 2"#)
                == .confirmationShown(tool: "RunCommand", step: 2))
        #expect(
            AntigravityLog.parse(
                "I1020 03:10:25.863469     208 input_loop.go:706] Responding to tool confirmation: convID=6f368e30-8d1e-4c10-932f-8f68ac1196ab, stepIdx=2, approved=true, sandboxOverride=false, persistGrants=[]")
                == .confirmationAnswered(conversationID: "6f368e30-8d1e-4c10-932f-8f68ac1196ab", step: 2, approved: true))
        #expect(AntigravityLog.parse("I1020 03:09:08.105214 1 cli_setting_manager.go:92] CLI settings initialized") == nil)
    }

    @Test func toolNames() {
        #expect(AntigravityLog.toolMatches("RunCommand", "run_command"))
        #expect(!AntigravityLog.toolMatches("RunCommand", "view_file"))
        #expect(AntigravityLog.hookToolName("RunCommand") == "run_command")
        #expect(AntigravityPayload.normalized(["stepIdx": 4])["step_idx"]?.int == 4)
    }
}

@Suite struct AntigravityPromptTests {
    @Test func hookThenPromptThenAnswer() {
        var engine = SessionEngine()
        let key = "antigravity:c1"
        _ = engine.handle(agy("PreInvocation"))
        _ = engine.handle(agy("PreToolUse", step: 2, command: "npm run build"))
        let shown = engine.externalPromptShown(tool: "RunCommand", step: 2, logID: "log1")
        #expect(shown.cue == .approval)
        #expect(shown.reveal == .attention(key))
        let req = engine.pending.first
        #expect(req?.kind == .external)
        #expect(req?.sessionKey == key)
        #expect(req?.toolInput["CommandLine"]?.string == "npm run build")
        #expect(engine.sessions[key]?.phase == .needsApproval)
        #expect(engine.sessions[key]?.attention == "Wants to build")

        let answered = engine.externalPromptAnswered(conversationID: "c1", step: 2, approved: true, logID: "log1")
        #expect(answered.cancelledRequests == [req?.id ?? "?"])
        #expect(engine.pending.isEmpty)
        #expect(engine.sessions[key]?.phase == .working)
    }

    @Test func promptBeforeHookIsParkedThenAttached() {
        var engine = SessionEngine()
        // App just started: no Antigravity session known yet.
        let shown = engine.externalPromptShown(tool: "RunCommand", step: 5, logID: "log1")
        #expect(shown.reveal == nil)
        #expect(engine.pending.isEmpty)
        let hook = engine.handle(agy("PreToolUse", step: 5, command: "rm -rf dist"))
        #expect(hook.reveal == .attention("antigravity:c1"))
        #expect(engine.pending.first?.toolInput["CommandLine"]?.string == "rm -rf dist")
    }

    @Test func sameStepHookDoesNotCancelButNextStepDoes() {
        var engine = SessionEngine()
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = engine.handle(agy("PreInvocation"), now: t0)
        _ = engine.externalPromptShown(tool: "RunCommand", step: 2, logID: "log1", now: t0 + 1)
        // Hook for the same step arrives second: keeps the prompt and fills in the command.
        let same = engine.handle(agy("PreToolUse", step: 2, command: "make deploy"), now: t0 + 2)
        #expect(same.cancelledRequests.isEmpty)
        #expect(engine.pending.first?.toolInput["CommandLine"]?.string == "make deploy")
        #expect(engine.sessions["antigravity:c1"]?.phase == .needsApproval)
        // The next step starting means the prompt was settled.
        let next = engine.handle(agy("PreToolUse", step: 3, command: "ls"), now: t0 + 30)
        #expect(next.cancelledRequests.count == 1)
        #expect(engine.pending.isEmpty)
    }
}
