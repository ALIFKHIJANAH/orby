import Foundation
import NotchShared

/// Antigravity's hook input is camelCase, has no cwd and names tools differently, so it is
/// translated into the Claude-shaped payload the session engine already understands.
public enum AntigravityPayload {
    public static func normalized(_ p: JSONValue) -> JSONValue {
        var out: [String: JSONValue] = [:]
        if let id = p["conversationId"] { out["session_id"] = id }
        if let cwd = p["workspacePaths"]?.array?.first { out["cwd"] = cwd }
        if let model = p["modelName"] { out["model"] = model }
        if let step = p["stepIdx"] { out["step_idx"] = step }
        if let tool = p["toolCall"] {
            out["tool_name"] = tool["name"]
            out["tool_input"] = tool["args"] ?? .object([:])
        }
        if let error = p["error"]?.string, !error.isEmpty { out["error"] = .string(error) }
        out["hook_event_name"] = .string(event(for: p))
        return .object(out)
    }

    private static func event(for p: JSONValue) -> String {
        let name = p["hook_event_name"]?.string ?? ""
        let failed = !(p["error"]?.string ?? "").isEmpty
        switch name {
        // Every model invocation means the agent is busy again.
        case "PreInvocation": return "UserPromptSubmit"
        case "PostToolUse" where failed: return "PostToolUseFailure"
        case "Stop":
            if p["terminationReason"]?.string == "error" { return "StopFailure" }
            // Still running other work (subagents, queued steps): not finished yet.
            return p["fullyIdle"]?.bool == false ? "PostInvocation" : "Stop"
        default: return name
        }
    }
}
