import Foundation

/// Builds the shell command that starts an agent from the notch.
public enum AgentLaunch {
    /// Agents whose CLI can be started with a first prompt.
    public static let agents: [AgentKind] = [.claude, .codex, .antigravity, .opencode]

    /// The agent's interactive CLI, opening on `prompt` when there is one. The prompt becomes one
    /// line: it is typed into a shell, where a newline would run the command early.
    public static func command(_ agent: AgentKind, prompt: String = "") -> String {
        let line = prompt.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let bin: String
        var flag: String?
        switch agent {
        case .codex: bin = "codex"
        case .antigravity:
            bin = "agy"
            flag = "-i"  // runs the prompt and stays interactive
        case .opencode:
            bin = "opencode"
            flag = "--prompt"
        default: bin = "claude"
        }
        guard !line.isEmpty else { return bin }
        return ([bin] + [flag].compactMap { $0 } + [Shell.quote(line)]).joined(separator: " ")
    }

    public static func inFolder(_ dir: String, _ command: String) -> String {
        "cd \(Shell.quote(dir)) && \(command)"
    }

    /// Recent folders, newest first.
    public static func remember(_ folder: String, in recents: [String], max: Int = 8) -> [String] {
        Array(([folder] + recents.filter { $0 != folder }).prefix(max))
    }
}

public enum Shell {
    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
