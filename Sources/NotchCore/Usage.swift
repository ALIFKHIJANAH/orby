import Foundation
import NotchShared

public struct UsageWindow: Hashable, Sendable {
    public var label: String
    /// 0...1
    public var used: Double
    public var resetsAt: Date?

    public init(label: String, used: Double, resetsAt: Date?) {
        self.label = label
        self.used = used
        self.resetsAt = resetsAt
    }
}

public struct RateLimits: Hashable, Sendable {
    public var provider: AgentKind
    public var plan: String?
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(provider: AgentKind, plan: String?, windows: [UsageWindow], fetchedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var mostPressured: UsageWindow? { windows.max { $0.used < $1.used } }

    /// Codex writes `rate_limits` into every `token_count` event of its rollout logs.
    public static func codex(_ v: JSONValue, now: Date = Date()) -> RateLimits? {
        let windows = ["primary", "secondary"].compactMap { key -> UsageWindow? in
            guard let w = v[key], let pct = w["used_percent"]?.double else { return nil }
            let minutes = w["window_minutes"]?.int ?? 0
            let reset = w["resets_at"]?.double.map { Date(timeIntervalSince1970: $0) }
            return UsageWindow(label: windowLabel(minutes: minutes), used: pct / 100, resetsAt: reset)
        }
        guard !windows.isEmpty else { return nil }
        return RateLimits(provider: .codex, plan: v["plan_type"]?.string, windows: windows, fetchedAt: now)
    }

    /// Response of Anthropic's OAuth usage endpoint (`five_hour`, `seven_day`, ...; utilization is 0–100).
    public static func claude(_ v: JSONValue, now: Date = Date()) -> RateLimits? {
        let keys: [(String, String)] = [
            ("five_hour", "5h"), ("seven_day", "7d"), ("seven_day_opus", "7d Opus"), ("seven_day_sonnet", "7d Sonnet"),
        ]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let windows = keys.compactMap { key, label -> UsageWindow? in
            guard let w = v[key], let pct = w["utilization"]?.double else { return nil }
            let reset = w["resets_at"]?.string.flatMap {
                iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
            }
            return UsageWindow(label: label, used: pct / 100, resetsAt: reset)
        }
        guard !windows.isEmpty else { return nil }
        return RateLimits(provider: .claude, plan: nil, windows: windows, fetchedAt: now)
    }

    static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 300: "5h"
        case 10080: "7d"
        case let m where m % 1440 == 0 && m > 0: "\(m / 1440)d"
        case let m where m % 60 == 0 && m > 0: "\(m / 60)h"
        default: "\(minutes)m"
        }
    }
}

/// Tokens per local day per agent, computed from transcripts on disk (nothing leaves the Mac).
public struct TokenHistory: Equatable, Sendable {
    /// "yyyy-MM-dd" → agent → tokens
    public var days: [String: [AgentKind: Int]] = [:]

    public init() {}

    public func total(day: String) -> Int { days[day]?.values.reduce(0, +) ?? 0 }

    public mutating func add(day: String, agent: AgentKind, tokens: Int) {
        days[day, default: [:]][agent, default: 0] += tokens
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func lastDays(_ n: Int, now: Date = Date(), calendar: Calendar = .current) -> [(day: String, byAgent: [AgentKind: Int])] {
        (0..<n).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = Self.dayKey(d, calendar: calendar)
            return (key, days[key] ?? [:])
        }
    }
}

public enum UsageScanner {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? { isoFractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) }

    /// One Claude transcript line → (message id, timestamp, tokens). Claude repeats the same
    /// usage on every content block of a message, so callers dedupe by id.
    public static func claudeUsage<S: StringProtocol>(line: S) -> (id: String, date: Date, tokens: Int)? {
        guard line.contains("\"usage\""), let obj = try? JSONValue.decode(Data(line.utf8)),
            obj["type"]?.string == "assistant", let message = obj["message"], let usage = message["usage"],
            let ts = obj["timestamp"]?.string, let date = parseDate(ts)
        else { return nil }
        let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .compactMap { usage[$0]?.int }.reduce(0, +)
        let id = message["id"]?.string ?? obj["requestId"]?.string ?? obj["uuid"]?.string ?? ts
        return (id, date, tokens)
    }

    /// One Codex rollout line → per-turn tokens from `last_token_usage`.
    public static func codexUsage<S: StringProtocol>(line: S) -> (date: Date, tokens: Int, limits: RateLimits?)? {
        guard line.contains("\"token_count\""), let obj = try? JSONValue.decode(Data(line.utf8)),
            let payload = obj["payload"], payload["type"]?.string == "token_count",
            let ts = obj["timestamp"]?.string, let date = parseDate(ts)
        else { return nil }
        let tokens = payload["info"]?["last_token_usage"]?["total_tokens"]?.int ?? 0
        return (date, tokens, payload["rate_limits"].flatMap { RateLimits.codex($0, now: date) })
    }

    public struct Result: Sendable {
        public var history = TokenHistory()
        public var codexLimits: RateLimits?
    }

    /// Stateless full scan of transcripts modified in the last `days` days.
    public static func scan(home: URL, days: Int = 30, now: Date = Date()) -> Result {
        let index = UsageIndex()
        return index.refresh(home: home, days: days, now: now)
    }

    static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [(url: URL, mtime: Date, size: Int)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var files: [(URL, Date, Int)] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let v = try? url.resourceValues(forKeys: Set(keys))
            let mtime = v?.contentModificationDate ?? .distantPast
            if v?.isRegularFile == true, mtime >= cutoff { files.append((url, mtime, v?.fileSize ?? 0)) }
        }
        return files
    }

    static func forEachLine(_ url: URL, _ body: (Substring) -> Void) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let text = String(data: data, encoding: .utf8)
        else { return }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) { body(line) }
    }
}

/// Caches per-file usage so periodic refreshes only re-parse transcripts that changed.
/// Not thread-safe: own it from a single actor/queue.
public final class UsageIndex {
    struct Entry {
        var id: String?
        var date: Date
        var agent: AgentKind
        var tokens: Int
    }

    struct FileState {
        var mtime: Date
        var size: Int
        var entries: [Entry]
        var limits: RateLimits?
    }

    private var files: [String: FileState] = [:]

    public init() {}

    public func refresh(home: URL, days: Int = 30, now: Date = Date()) -> UsageScanner.Result {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        var live = Set<String>()
        let sources: [(String, AgentKind)] = [(".claude/projects", .claude), (".codex/sessions", .codex)]
        for (dir, agent) in sources {
            for f in UsageScanner.jsonlFiles(under: home.appendingPathComponent(dir), modifiedAfter: cutoff) {
                live.insert(f.url.path)
                if let cached = files[f.url.path], cached.mtime == f.mtime, cached.size == f.size { continue }
                files[f.url.path] = parse(f.url, agent: agent, mtime: f.mtime, size: f.size)
            }
        }
        files = files.filter { live.contains($0.key) }

        var result = UsageScanner.Result()
        var seen = Set<String>()
        for state in files.values {
            for e in state.entries where e.date >= cutoff {
                if let id = e.id, !seen.insert(id).inserted { continue }
                result.history.add(day: TokenHistory.dayKey(e.date), agent: e.agent, tokens: e.tokens)
            }
            if let l = state.limits, l.fetchedAt > (result.codexLimits?.fetchedAt ?? .distantPast) {
                result.codexLimits = l
            }
        }
        return result
    }

    private func parse(_ url: URL, agent: AgentKind, mtime: Date, size: Int) -> FileState {
        var state = FileState(mtime: mtime, size: size, entries: [])
        UsageScanner.forEachLine(url) { line in
            switch agent {
            case .codex:
                guard let u = UsageScanner.codexUsage(line: line) else { return }
                state.entries.append(Entry(id: nil, date: u.date, agent: .codex, tokens: u.tokens))
                if let l = u.limits { state.limits = l }
            default:
                guard let u = UsageScanner.claudeUsage(line: line) else { return }
                state.entries.append(Entry(id: u.id, date: u.date, agent: .claude, tokens: u.tokens))
            }
        }
        return state
    }
}
