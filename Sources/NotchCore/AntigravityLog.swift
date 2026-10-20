import Foundation

/// Antigravity CLI shows tool permission prompts in its own terminal and no hook fires for
/// them, but its log (~/.gemini/antigravity-cli/log/cli-*.log) records each one:
///
///     I1020 03:09:29.953108 7203 tool_confirmation_manager.go:226] Surfacing tool confirmation: "RunCommand" at step 2
///     I1020 03:10:25.863469  208 input_loop.go:706] Responding to tool confirmation: convID=6f36…, stepIdx=2, approved=true, …
public enum AntigravityLog {
    public enum Event: Equatable, Sendable {
        case confirmationShown(tool: String, step: Int)
        case confirmationAnswered(conversationID: String, step: Int, approved: Bool)
    }

    private static let shown = try! NSRegularExpression(pattern: #"Surfacing tool confirmation: "([^"]+)" at step (\d+)"#)
    private static let answered = try! NSRegularExpression(
        pattern: #"Responding to tool confirmation: convID=([0-9A-Za-z-]+), stepIdx=(\d+), approved=(true|false)"#)

    public static func parse<S: StringProtocol>(_ line: S) -> Event? {
        let s = String(line)
        guard s.contains("tool confirmation") else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
        if let m = shown.firstMatch(in: s, range: range), let tool = group(m, 1), let step = group(m, 2).flatMap(Int.init) {
            return .confirmationShown(tool: tool, step: step)
        }
        if let m = answered.firstMatch(in: s, range: range), let conv = group(m, 1),
            let step = group(m, 2).flatMap(Int.init), let approved = group(m, 3)
        {
            return .confirmationAnswered(conversationID: conv, step: step, approved: approved == "true")
        }
        return nil
    }

    /// "RunCommand" → "run_command", the name the hooks and ToolDescriber use.
    public static func hookToolName(_ logTool: String) -> String {
        var out = ""
        for (i, c) in logTool.enumerated() {
            if c.isUppercase, i > 0 { out.append("_") }
            out.append(Character(c.lowercased()))
        }
        return out
    }

    /// The log names tools in CamelCase ("RunCommand"), hooks in snake_case ("run_command").
    public static func toolMatches(_ logTool: String, _ hookTool: String?) -> Bool {
        guard let hookTool else { return false }
        func norm(_ s: String) -> String { s.replacingOccurrences(of: "_", with: "").lowercased() }
        return norm(logTool) == norm(hookTool)
    }
}
