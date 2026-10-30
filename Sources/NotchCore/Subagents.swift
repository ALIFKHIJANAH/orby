import Foundation
import NotchShared

/// Claude Code writes each subagent's transcript beside the session's:
/// `<session>.jsonl` → `<session>/subagents/agent-<id>.jsonl` plus a `.meta.json` with how it was launched.
public enum SubagentMeta {
    public static func path(transcript: String, agentID: String) -> String {
        let session = transcript.hasSuffix(".jsonl") ? String(transcript.dropLast(".jsonl".count)) : transcript
        return "\(session)/subagents/agent-\(agentID).meta.json"
    }

    /// `agentType` and `description`, or nil until the file exists.
    public static func read(path: String) -> (type: String?, task: String?)? {
        guard let data = FileManager.default.contents(atPath: path), let json = try? JSONValue.decode(data) else { return nil }
        return parse(json)
    }

    static func parse(_ json: JSONValue) -> (type: String?, task: String?) {
        func nonEmpty(_ v: JSONValue?) -> String? { v?.string.flatMap { $0.isEmpty ? nil : $0 } }
        return (nonEmpty(json["agentType"]), nonEmpty(json["description"]))
    }
}
