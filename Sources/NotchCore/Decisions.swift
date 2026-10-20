import Foundation
import NotchShared

/// What the user chose in the notch, rendered as the agent's PermissionRequest hook output.
public enum PermissionDecision: Sendable, Equatable {
    case allow(updatedInput: JSONValue? = nil, updatedPermissions: [JSONValue]? = nil)
    case deny(message: String, interrupt: Bool = false)
    /// Print nothing; the agent shows its usual terminal prompt.
    case passthrough

    public func hookOutput() -> JSONValue? {
        let decision: JSONValue
        switch self {
        case .passthrough:
            return nil
        case .allow(let updatedInput, let updatedPermissions):
            var d: [String: JSONValue] = ["behavior": "allow"]
            if let updatedInput { d["updatedInput"] = updatedInput }
            if let updatedPermissions, !updatedPermissions.isEmpty { d["updatedPermissions"] = .array(updatedPermissions) }
            decision = .object(d)
        case .deny(let message, let interrupt):
            decision = ["behavior": "deny", "message": .string(message), "interrupt": .bool(interrupt)]
        }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }

    /// AskUserQuestion is answered by allowing the tool with `answers` merged into its input.
    /// Multi-select answers are joined with ", " (the format Claude Code itself produces).
    public static func answering(_ request: PendingRequest, answers: [String: [String]]) -> PermissionDecision {
        var input = request.toolInput.object ?? [:]
        var map: [String: JSONValue] = [:]
        for (question, labels) in answers where !labels.isEmpty {
            map[question] = .string(labels.joined(separator: ", "))
        }
        input["answers"] = .object(map)
        return .allow(updatedInput: .object(input))
    }

    /// Approve a plan. Claude Code only leaves its own plan dialog when the approval echoes the
    /// tool input back as `updatedInput`; a bare "allow" is ignored for ExitPlanMode.
    /// `mode` optionally switches the session (e.g. "acceptEdits"); nil keeps the mode Claude
    /// restores after planning.
    public static func approvePlan(_ request: PendingRequest, mode: String? = nil) -> PermissionDecision {
        .allow(
            updatedInput: request.toolInput,
            updatedPermissions: mode.map { [["type": "setMode", "mode": .string($0), "destination": "session"]] })
    }
}
