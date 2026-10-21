import Foundation
import NotchShared

/// Cursor (IDE and `agent` CLI) also runs the hooks in ~/.claude/settings.json, so its sessions
/// reach Orby as `--source claude`. They carry `cursor_version`, are keyed by `conversation_id`,
/// may use Cursor's camelCase event names and name tools their own way (`Shell`).
/// Status only: Cursor sends neither PermissionRequest nor Notification to Claude hooks.
public enum CursorPayload {
    private static let events = ["beforeSubmitPrompt": "UserPromptSubmit"]

    public static func normalized(_ p: JSONValue) -> JSONValue {
        guard var out = ToolAliases.normalized(p).object else { return p }
        if let name = out["hook_event_name"]?.string, let first = name.first, first.isLowercase {
            out["hook_event_name"] = .string(events[name] ?? first.uppercased() + name.dropFirst())
        }
        if out["cwd"]?.string?.isEmpty ?? true, let root = out["workspace_roots"]?.array?.first {
            out["cwd"] = root
        }
        return .object(out)
    }
}
