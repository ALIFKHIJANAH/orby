import Foundation
import NotchShared

public struct Risk: Hashable, Sendable {
    public enum Severity: Sendable { case caution, danger }
    public var label: String
    public var severity: Severity
}

/// Flags commands and edits worth a second look before approving.
public enum RiskAssessor {
    private static let commandRules: [(pattern: String, label: String, severity: Risk.Severity)] = [
        (#"(^|[\s;&|(])rm\s+(-[a-z]*r[a-z]*|-[a-z]*R[a-z]*|--recursive)"#, "Deletes files", .danger),
        (#"git\s+push\b[^;&|]*\s(--force(-with-lease)?|-f)\b"#, "Force-pushes", .danger),
        (#"git\s+(reset\s+--hard|clean\s+-[a-z]*f|checkout\s+--\s+\.|restore\s+\.)"#, "Discards local changes", .danger),
        (#"(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(sh|bash|zsh)\b"#, "Runs a downloaded script", .danger),
        (#"(?i)\b(drop\s+(table|database|schema)|truncate\s+table|delete\s+from)\b"#, "Changes the database", .danger),
        (#"(^|[\s;&|(])sudo\s"#, "Runs as administrator", .caution),
        (#"chmod\s+(-R\b|[0-7]*777)"#, "Changes permissions", .caution),
        (#"(kill\s+-9|\bpkill\b|\bkillall\b)"#, "Stops processes", .caution),
        (#"((npm|pnpm|yarn|cargo)\s+publish|gh\s+release\s+create)"#, "Publishes", .caution),
    ]

    private static let fileTools: Set<String> = [
        "Edit", "MultiEdit", "Write", "NotebookEdit", "write_to_file", "replace_file_content", "multi_replace_file_content",
    ]

    public static func assess(tool: String, input: JSONValue) -> [Risk] {
        var risks: [Risk] = []
        let command = tool == "run_command" ? (input["CommandLine"]?.string ?? "") : ToolDescriber.command(from: input)
        if !command.isEmpty {
            for rule in commandRules where command.range(of: rule.pattern, options: .regularExpression) != nil {
                risks.append(Risk(label: rule.label, severity: rule.severity))
            }
        }
        if fileTools.contains(tool) {
            let path = input["file_path"]?.string ?? input["notebook_path"]?.string ?? input["TargetFile"]?.string ?? ""
            if isSecret(path) { risks.append(Risk(label: "Touches secrets", severity: .caution)) }
        }
        var seen = Set<String>()
        return risks.filter { seen.insert($0.label).inserted }.sorted { $0.severity == .danger && $1.severity != .danger }
    }

    static func isSecret(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard !name.isEmpty else { return false }
        if name == ".env.example" || name == ".env.sample" { return false }
        return name.hasPrefix(".env") || name.hasSuffix(".pem") || name.hasSuffix(".key") || name.hasPrefix("id_rsa")
            || name.hasPrefix("id_ed25519") || name.hasPrefix("credentials") || name == ".npmrc" || name.hasPrefix("secrets.")
    }
}
