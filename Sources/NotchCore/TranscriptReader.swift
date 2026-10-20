import Foundation
import NotchShared

/// Snapshot read from the tail of an agent transcript: model, context fill, last reply.
public struct TranscriptInfo: Equatable, Sendable {
    public var model: String?
    public var contextTokens: Int?
    public var contextLimit: Int?
    public var lastAssistantText: String?
    public var gitBranch: String?
    public var codexLimits: RateLimits?
    /// Reasoning text, only when it is the newest thing in the transcript (no reply,
    /// tool call or tool result after it yet). Often empty: thinking can be redacted.
    public var latestThinking: String?

    public init() {}
}

public enum TranscriptReader {
    /// Reads at most the last `maxBytes` of the file; transcripts can be hundreds of MB.
    public static func tailLines(path: String, maxBytes: Int = 512 * 1024) -> [Substring] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }  // likely a partial line
        return lines
    }

    public static func read(path: String, agent: AgentKind) -> TranscriptInfo {
        let lines = tailLines(path: path)
        return agent == .codex ? parseCodex(lines) : parseClaude(lines)
    }

    public static func parseClaude<S: StringProtocol>(_ lines: [S]) -> TranscriptInfo {
        var info = TranscriptInfo()
        var newestSeen = false
        for line in lines.reversed() {
            guard let obj = try? JSONValue.decode(Data(line.utf8)) else { continue }
            if info.gitBranch == nil, let b = obj["gitBranch"]?.string, !b.isEmpty { info.gitBranch = b }
            if !newestSeen, ["user", "assistant"].contains(obj["type"]?.string), obj["isSidechain"]?.bool != true {
                newestSeen = true
                // Claude writes one line per content block, so a trailing thinking block is live.
                if obj["type"]?.string == "assistant", let last = obj["message"]?["content"]?.array?.last,
                    last["type"]?.string == "thinking",
                    let text = last["thinking"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
                {
                    info.latestThinking = text
                }
            }
            guard obj["type"]?.string == "assistant", obj["isSidechain"]?.bool != true,
                let message = obj["message"]
            else { continue }

            if info.lastAssistantText == nil {
                let text = (message["content"]?.array ?? [])
                    .filter { $0["type"]?.string == "text" }
                    .compactMap { $0["text"]?.string }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { info.lastAssistantText = text }
            }
            if info.contextTokens == nil, let usage = message["usage"] {
                let used = [
                    "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens",
                ].compactMap { usage[$0]?.int }.reduce(0, +)
                if used > 0 {
                    info.contextTokens = used
                    info.model = message["model"]?.string
                    info.contextLimit = claudeContextLimit(model: info.model, used: used)
                }
            }
            if info.contextTokens != nil, info.lastAssistantText != nil, info.gitBranch != nil { break }
        }
        return info
    }

    static func claudeContextLimit(model: String?, used: Int) -> Int {
        if let model, model.contains("[1m]") { return 1_000_000 }
        return used > 200_000 ? 1_000_000 : 200_000
    }

    public static func parseCodex<S: StringProtocol>(_ lines: [S]) -> TranscriptInfo {
        var info = TranscriptInfo()
        var newestSeen = false
        for line in lines.reversed() {
            guard let obj = try? JSONValue.decode(Data(line.utf8)), let payload = obj["payload"] else { continue }
            if !newestSeen { newestSeen = codexNewestThinking(type: obj["type"]?.string, payload: payload, into: &info) }
            switch (obj["type"]?.string, payload["type"]?.string) {
            case ("event_msg", "token_count"):
                if info.contextTokens == nil, let tokenInfo = payload["info"],
                    let last = tokenInfo["last_token_usage"]
                {
                    info.contextTokens = last["input_tokens"]?.int
                    info.contextLimit = tokenInfo["model_context_window"]?.int
                }
                if info.codexLimits == nil, let limits = payload["rate_limits"] {
                    info.codexLimits = RateLimits.codex(limits)
                }
            case ("event_msg", "agent_message"):
                if info.lastAssistantText == nil { info.lastAssistantText = payload["message"]?.string }
            case ("turn_context", _):
                if info.model == nil { info.model = payload["model"]?.string }
            default: break
            }
            if info.contextTokens != nil, info.lastAssistantText != nil, info.model != nil { break }
        }
        return info
    }

    /// Returns true once the newest conversational item has been seen (reasoning or not).
    private static func codexNewestThinking(type: String?, payload: JSONValue, into info: inout TranscriptInfo) -> Bool {
        switch (type, payload["type"]?.string) {
        case ("event_msg", "agent_reasoning"):
            let text = payload["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { info.latestThinking = text }
            return true
        case ("response_item", "reasoning"):
            let text = (payload["summary"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { info.latestThinking = text }
            return true
        case ("response_item", _), ("event_msg", "agent_message"), ("event_msg", "user_message"):
            return true
        default:
            return false
        }
    }
}
