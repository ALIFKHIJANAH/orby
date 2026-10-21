import Foundation

/// Antigravity CLI status line: agy pipes its state (model, quota, ...) to a `statusLine`
/// command on every update. The bridge relays it to Orby and prints a line back.
public enum AntigravityStatusLine {
    /// Set as `hook_event_name` on relayed payloads so the app can tell them from hook events.
    public static let eventName = "StatusLine"

    /// "gemini-weekly" → "Gemini 7d", "3p-5h" → "Claude/GPT 5h"; unknown ids are prettified.
    public static func label(bucket id: String) -> String {
        var parts = id.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard !parts.isEmpty else { return id }
        var window: String?
        if let last = parts.last, parts.count > 1 {
            switch last.lowercased() {
            case "weekly", "week", "7d": window = "7d"
            case "daily", "day", "1d": window = "1d"
            case "monthly", "month": window = "30d"
            case let w where w.range(of: #"^\d+[hdm]$"#, options: .regularExpression) != nil: window = w
            default: break
            }
            if window != nil { parts.removeLast() }
        }
        let group = parts.map { part -> String in
            switch part.lowercased() {
            case "3p": "Claude/GPT"
            case "gpt": "GPT"
            default: part.prefix(1).uppercased() + part.dropFirst()
            }
        }.joined(separator: " ")
        return [group, window].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// One short line for agy's status bar: model and the bucket with the least left.
    public static func summary(_ payload: JSONValue) -> String {
        let model = payload["model"]?["display_name"]?.string ?? payload["model"]?["id"]?.string
        let tightest = (payload["quota"]?.object ?? [:])
            .compactMap { id, bucket in bucket["remaining_fraction"]?.double.map { (id, $0) } }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        let quota = tightest.map { "\(label(bucket: $0.0)) \(Int((max(0, min(1, $0.1)) * 100).rounded()))% left" }
        return [model, quota].compactMap { $0 }.joined(separator: " · ")
    }
}
