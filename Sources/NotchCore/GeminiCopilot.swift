import Foundation
import NotchShared

/// Gemini CLI's hook input has Claude's field names but its own event and tool names.
/// It can't be approved from outside (a hook's "allow" doesn't skip its prompt), so its
/// `ToolPermission` notification becomes an external prompt: the notch alerts and jumps.
public enum GeminiPayload {
    private static let events = [
        "BeforeAgent": "UserPromptSubmit", "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse", "AfterAgent": "Stop",
        "PreCompress": "PreCompact",
    ]

    public static func normalized(_ p: JSONValue) -> JSONValue {
        guard var out = p.object else { return p }
        let name = out["hook_event_name"]?.string ?? ""
        out["hook_event_name"] = .string(events[name] ?? name)
        if name == "AfterTool", let error = out["tool_response"]?["error"], error != .null {
            out["hook_event_name"] = "PostToolUseFailure"
        }
        if name == "Notification", out["notification_type"]?.string == "ToolPermission" {
            out["notification_type"] = "permission_prompt"
            if let details = out["details"], let (tool, input) = promptedTool(details) {
                out["tool_name"] = .string(tool)
                out["tool_input"] = input
            }
        }
        if let server = out["mcp_context"]?["server_name"]?.string, let tool = out["mcp_context"]?["tool_name"]?.string {
            out["tool_name"] = .string("mcp__\(server)__\(tool)")
        }
        return ToolAliases.normalized(.object(out))
    }

    /// The call a permission prompt is about, from its confirmation details, in Claude's terms.
    static func promptedTool(_ d: JSONValue) -> (String, JSONValue)? {
        switch d["type"]?.string {
        case "exec": d["command"].map { ("Bash", ["command": $0]) }
        case "edit": d["filePath"].map { ("Edit", ["file_path": $0]) }
        case "info": d["urls"]?.array?.first.map { ("WebFetch", ["url": $0]) }
        case "mcp":
            d["serverName"]?.string.flatMap { server in d["toolName"]?.string.map { ("mcp__\(server)__\($0)", .object([:])) } }
        default: nil
        }
    }
}

/// GitHub Copilot CLI. PascalCase hook keys get Claude-shaped snake_case input, but its
/// permission and notification hooks always send camelCase, and its tools keep their own names.
public enum CopilotPayload {
    /// `approvals` off: Copilot's permission hook is observed, not answered, because it fires
    /// before Copilot's own rules and would ask about calls Copilot itself auto-allows.
    public static func normalized(_ p: JSONValue, approvals: Bool) -> JSONValue {
        guard var out = p.object else { return p }
        for (snake, camel) in [
            ("session_id", "sessionId"), ("tool_name", "toolName"), ("tool_input", "toolInput"), ("transcript_path", "transcriptPath"),
        ] where out[snake] == nil {
            if let value = out[camel] { out[snake] = value }
        }
        if out["tool_input"] == nil, let args = out["toolArgs"] { out["tool_input"] = args }
        // Older payloads carry tool arguments as a JSON string.
        if let raw = out["tool_input"]?.string, let parsed = try? JSONValue.decode(Data(raw.utf8)), parsed.object != nil {
            out["tool_input"] = parsed
        }
        switch out["hook_event_name"]?.string {
        case "PermissionRequest" where !approvals:
            out["hook_event_name"] = "PermissionObserved"
        case "Notification" where out["notification_type"]?.string == "agent_idle":
            out["notification_type"] = "idle_prompt"
        case "ErrorOccurred" where out["recoverable"]?.bool == false:
            out["hook_event_name"] = "StopFailure"
            if let message = out["error"]?["message"] { out["error"] = message }
        default:
            break
        }
        // MCP tools are "server/tool".
        if let tool = out["tool_name"]?.string, let slash = tool.firstIndex(of: "/") {
            out["tool_name"] = .string("mcp__\(tool[..<slash])__\(tool[tool.index(after: slash)...])")
        }
        return ToolAliases.normalized(.object(out))
    }
}

extension AgentKind {
    /// Agents whose permission prompts Orby only hears about (a notification hook) and can't
    /// answer, so it raises an external prompt that jumps to the terminal.
    var promptsInTerminalOnly: Bool { self == .gemini || self == .copilot }
}
