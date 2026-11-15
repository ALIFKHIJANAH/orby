import Foundation
import NotchShared

/// Agents that speak Claude's hook events (Qwen, Command Code, Cursor, Factory Droid, Kimi Code,
/// and the OpenCode/Pi plugins) still name their tools and arguments their own way. Their calls are renamed to
/// Claude's so descriptions, diffs and risk checks work unchanged.
public enum ToolAliases {
    private static let names: [String: String] = [
        // Shell
        "run_shell_command": "Bash", "shell_command": "Bash", "bash": "Bash", "Shell": "Bash",
        // Files
        "read_file": "Read", "read": "Read",
        "write_file": "Write", "write": "Write",
        "edit_file": "Edit", "edit": "Edit", "replace": "Edit",
        // Search and web
        "grep_search": "Grep", "grep": "Grep", "glob": "Glob", "find": "Glob",
        "web_fetch": "WebFetch", "webfetch": "WebFetch",
        "web_search": "WebSearch", "websearch": "WebSearch", "google_web_search": "WebSearch",
        // Planning
        "todo_write": "TodoWrite", "todowrite": "TodoWrite", "task": "Task", "exit_plan_mode": "ExitPlanMode",
        // Factory Droid
        "Execute": "Bash", "Create": "Write", "ApplyPatch": "apply_patch", "FetchUrl": "WebFetch", "AskUser": "AskUserQuestion",
        // Kimi Code
        "FetchURL": "WebFetch", "TodoList": "TodoWrite",
    ]

    /// Claude's argument name → the names other agents use for it.
    private static let keys: [String: [String]] = [
        "file_path": ["filePath", "absolute_path", "path"],
        "old_string": ["oldString", "oldText", "old_str"],
        "new_string": ["newString", "newText", "new_str"],
    ]

    public static func claudeName(_ tool: String) -> String { names[tool] ?? tool }

    public static func normalized(_ p: JSONValue) -> JSONValue {
        guard var out = p.object, let tool = out["tool_name"]?.string else { return p }
        // Kimi keeps Claude's tool names but calls the file argument "path".
        let name = names[tool] ?? tool
        out["tool_name"] = .string(name)
        // Grep and Glob already call their directory "path".
        if var input = out["tool_input"]?.object, ["Read", "Write", "Edit"].contains(name) {
            for (claude, others) in keys where input[claude] == nil {
                if let other = others.first(where: { input[$0] != nil }) { input[claude] = input.removeValue(forKey: other) }
            }
            out["tool_input"] = .object(input)
        }
        return .object(out)
    }
}
