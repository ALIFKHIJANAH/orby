import Foundation

/// Which requests a session the user trusts may get without asking: plain permission prompts
/// that `RiskAssessor` has nothing to say about. Questions, plans, Antigravity prompts and
/// anything flagged (even as a caution) still go to the user.
public enum TrustPolicy {
    public static func autoAllows(_ request: PendingRequest) -> Bool {
        request.kind == .permission && RiskAssessor.assess(tool: request.toolName, input: request.toolInput).isEmpty
    }
}
