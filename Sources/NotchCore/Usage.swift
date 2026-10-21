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

    /// Past its reset time: the usage it shows has been cleared since it was read.
    public func isStale(now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

/// One limit shown as a chip in the panel header.
public struct HeaderWindow: Hashable, Sendable {
    public var agent: AgentKind
    public var window: UsageWindow
    public var id: String { RateLimits.windowID(agent, window.label) }
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

    public var mostPressured: UsageWindow? { windows.filter { !$0.isStale() }.max { $0.used < $1.used } }

    /// The `count` providers nearest to a limit, most pressured first (what fits in the panel header).
    public static func closestToLimit(_ all: [RateLimits], count: Int = 2) -> [RateLimits] {
        Array(all.filter { $0.mostPressured != nil }.sorted { $0.mostPressured!.used > $1.mostPressured!.used }.prefix(count))
    }

    /// Stable id of one window for the user's header pick, e.g. "antigravity|Gemini 7d".
    public static func windowID(_ agent: AgentKind, _ label: String) -> String { "\(agent.rawValue)|\(label)" }

    /// What the panel header shows: the picked windows in pick order (skipping ones with no data
    /// yet), or the most pressured window of the providers closest to a limit when nothing is picked.
    public static func headerWindows(_ all: [RateLimits], picked: [String] = []) -> [HeaderWindow] {
        guard !picked.isEmpty else {
            return closestToLimit(all).compactMap { l in l.mostPressured.map { HeaderWindow(agent: l.provider, window: $0) } }
        }
        let byID = Dictionary(
            all.flatMap { l in l.windows.map { (windowID(l.provider, $0.label), HeaderWindow(agent: l.provider, window: $0)) } },
            uniquingKeysWith: { a, _ in a })
        return picked.compactMap { byID[$0] }
    }

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

    /// Per-agent totals over the last `n` days, only agents with usage, most first (ties by name).
    public func agentTotals(lastDays n: Int, now: Date = Date(), calendar: Calendar = .current) -> [(agent: AgentKind, tokens: Int)] {
        var totals: [AgentKind: Int] = [:]
        for day in lastDays(n, now: now, calendar: calendar) {
            for (agent, tokens) in day.byAgent { totals[agent, default: 0] += tokens }
        }
        return totals.filter { $0.value > 0 }.map { (agent: $0.key, tokens: $0.value) }
            .sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.agent.displayName < $1.agent.displayName }
    }
}

/// One model call's token count, normalised to "everything the model processed"
/// (input + output + reasoning + cache reads/writes, without double counting).
public struct UsageRecord: Sendable, Equatable {
    /// Records sharing a key are one call seen several times (streamed lines, forked files);
    /// only the highest `rank` counts. nil: always counted.
    public var key: String?
    public var date: Date
    public var agent: AgentKind
    public var tokens: Int
    public var rank: Int

    public init(key: String?, date: Date, agent: AgentKind, tokens: Int, rank: Int = 0) {
        self.key = key
        self.date = date
        self.agent = agent
        self.tokens = tokens
        self.rank = rank
    }
}

public enum UsageScanner {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ s: String) -> Date? { isoFractional.date(from: s) ?? ISO8601DateFormatter().date(from: s) }

    /// ISO string, or epoch seconds/milliseconds.
    static func date(_ v: JSONValue?) -> Date? {
        if let s = v?.string { return parseDate(s) }
        if let n = v?.double, n > 0 { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        return nil
    }

    private static func sum(_ v: JSONValue?, _ keys: [String]) -> Int { keys.compactMap { v?[$0]?.int }.reduce(0, +) }

    /// One Claude transcript line. Claude repeats `usage` on every content block of a message and
    /// `output_tokens` grows while streaming, so the line with the most output wins.
    public static func claudeUsage<S: StringProtocol>(line: S) -> UsageRecord? {
        guard line.contains("\"usage\""), let obj = try? JSONValue.decode(Data(line.utf8)),
            obj["type"]?.string == "assistant", let message = obj["message"], let usage = message["usage"],
            let ts = obj["timestamp"]?.string, let date = parseDate(ts)
        else { return nil }
        let tokens = sum(usage, ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"])
        let requestID = obj["requestId"]?.string
        let id = message["id"]?.string.map { "\($0):\(requestID ?? "")" } ?? requestID ?? obj["uuid"]?.string ?? ts
        return UsageRecord(key: "claude:" + id, date: date, agent: .claude, tokens: tokens, rank: usage["output_tokens"]?.int ?? 0)
    }

    /// One Codex rollout line → per-turn tokens from `last_token_usage`, plus the running
    /// `total_token_usage` so callers can drop repeated events.
    public static func codexUsage<S: StringProtocol>(line: S) -> (date: Date, tokens: Int, total: Int?, limits: RateLimits?)? {
        guard line.contains("\"token_count\""), let obj = try? JSONValue.decode(Data(line.utf8)),
            let payload = obj["payload"], payload["type"]?.string == "token_count",
            let ts = obj["timestamp"]?.string, let date = parseDate(ts)
        else { return nil }
        let info = payload["info"]
        let tokens = info?["last_token_usage"]?["total_tokens"]?.int ?? 0
        let total = info?["total_token_usage"]?["total_tokens"]?.int
        return (date, tokens, total, payload["rate_limits"].flatMap { RateLimits.codex($0, now: date) })
    }

    /// Qwen Code chat record: genai `usageMetadata` on assistant records (prompt count includes cache).
    public static func qwenUsage<S: StringProtocol>(line: S) -> UsageRecord? {
        guard line.contains("\"usageMetadata\""), let obj = try? JSONValue.decode(Data(line.utf8)),
            obj["type"]?.string == "assistant", let usage = obj["usageMetadata"], let date = date(obj["timestamp"])
        else { return nil }
        let tokens = usage["totalTokenCount"]?.int ?? sum(usage, ["promptTokenCount", "candidatesTokenCount", "thoughtsTokenCount"])
        guard tokens > 0 else { return nil }
        return UsageRecord(key: obj["uuid"]?.string.map { "qwen:" + $0 }, date: date, agent: .qwen, tokens: tokens)
    }

    /// Pi session entry: `message.usage` on assistant messages, or entry-level `usage` (cache warming,
    /// compaction). Forks copy entries with their ids, so the id dedupes across files.
    public static func piUsage<S: StringProtocol>(line: S) -> UsageRecord? {
        guard line.contains("\"usage\""), let obj = try? JSONValue.decode(Data(line.utf8)), obj["type"]?.string != "session",
            let usage = obj["message"]?["usage"] ?? obj["usage"],
            let date = date(obj["timestamp"]) ?? date(obj["message"]?["timestamp"])
        else { return nil }
        let tokens = usage["totalTokens"]?.int ?? sum(usage, ["input", "output", "cacheRead", "cacheWrite"])
        guard tokens > 0 else { return nil }
        return UsageRecord(key: obj["id"]?.string.map { "pi:" + $0 }, date: date, agent: .pi, tokens: tokens)
    }

    /// Command Code session entry: entry-level `usage` on assistant messages, disjoint buckets.
    public static func commandCodeUsage<S: StringProtocol>(line: S) -> UsageRecord? {
        guard line.contains("\"usage\""), let obj = try? JSONValue.decode(Data(line.utf8)),
            obj["type"]?.string == "message", let usage = obj["usage"], let date = date(obj["timestamp"])
        else { return nil }
        let tokens = sum(usage, ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"])
        guard tokens > 0 else { return nil }
        let key = obj["id"]?.string.map { "commandcode:\($0):\(obj["timestamp"]?.string ?? "")" }
        return UsageRecord(key: key, date: date, agent: .commandcode, tokens: tokens)
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

    /// Keeps the highest-ranked record per key and buckets everything by local day.
    static func history(_ records: [UsageRecord], since cutoff: Date) -> TokenHistory {
        var history = TokenHistory()
        var best: [String: UsageRecord] = [:]
        for r in records where r.date >= cutoff {
            guard let key = r.key else {
                history.add(day: TokenHistory.dayKey(r.date), agent: r.agent, tokens: r.tokens)
                continue
            }
            if let cur = best[key], (cur.rank, cur.tokens) >= (r.rank, r.tokens) { continue }
            best[key] = r
        }
        for r in best.values { history.add(day: TokenHistory.dayKey(r.date), agent: r.agent, tokens: r.tokens) }
        return history
    }

    struct FileInfo {
        var url: URL
        var mtime: Date
        var size: Int
        var inode: Int
    }

    static func fileInfo(_ url: URL) -> FileInfo? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return FileInfo(
            url: url, mtime: a[.modificationDate] as? Date ?? .distantPast, size: (a[.size] as? NSNumber)?.intValue ?? 0,
            inode: (a[.systemFileNumber] as? NSNumber)?.intValue ?? 0)
    }

    static func files(under root: URL, ext: String, modifiedAfter cutoff: Date) -> [FileInfo] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var files: [FileInfo] = []
        for case let url as URL in e where url.pathExtension == ext {
            let v = try? url.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true, (v?.contentModificationDate ?? .distantPast) >= cutoff, let info = fileInfo(url)
            else { continue }
            files.append(info)
        }
        return files
    }

    /// Complete lines from `offset` on, and the offset just past the last one. A trailing line
    /// without a newline is still being written and is left for the next read.
    static func lines(_ url: URL, from offset: Int) -> (lines: [Substring], end: Int) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return ([], offset) }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: UInt64(offset))) != nil, let data = try? h.readToEnd(),
            let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
        else { return ([], offset) }
        let complete = data[data.startIndex...lastNewline]
        let text = String(decoding: complete, as: UTF8.self)
        return (text.split(separator: "\n", omittingEmptySubsequences: true), offset + complete.count)
    }
}

/// Caches per-file usage so periodic refreshes only read what changed: JSONL transcripts are
/// append-only, so a grown file is parsed from where the last read stopped.
/// Not thread-safe: own it from a single actor/queue.
public final class UsageIndex {
    struct FileState {
        var mtime: Date
        var size: Int
        var inode: Int
        /// Bytes consumed so far: just past the last complete line.
        var offset = 0
        var records: [UsageRecord] = []
        var limits: RateLimits?
        /// Codex: last `total_token_usage`, to skip repeated `token_count` events.
        var codexTotal: Int?
    }

    /// Append-only JSONL transcript folders under the home directory.
    static let transcriptSources: [(dir: String, agent: AgentKind)] = [
        (".claude/projects", .claude), (".codex/sessions", .codex), (".qwen/projects", .qwen),
        (".pi/agent/sessions", .pi), (".commandcode/projects", .commandcode),
    ]

    private var files: [String: FileState] = [:]
    private let databases = UsageDatabases()

    public init() {}

    public func refresh(home: URL, days: Int = 30, now: Date = Date()) -> UsageScanner.Result {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        var live = Set<String>()
        for (dir, agent) in Self.transcriptSources {
            for f in UsageScanner.files(under: home.appendingPathComponent(dir), ext: "jsonl", modifiedAfter: cutoff)
            where Self.isTranscript(f.url, agent: agent) {
                live.insert(f.url.path)
                var state = files[f.url.path]
                if let s = state, s.inode == f.inode, s.mtime == f.mtime, s.size == f.size { continue }
                // Shrunk, replaced or rewritten in place: start over.
                if let s = state, s.inode != f.inode || f.size <= s.size { state = nil }
                var next = state ?? FileState(mtime: f.mtime, size: f.size, inode: f.inode)
                next.mtime = f.mtime
                next.size = f.size
                Self.read(f.url, agent: agent, into: &next)
                next.records.removeAll { $0.date < cutoff }
                files[f.url.path] = next
            }
        }
        files = files.filter { live.contains($0.key) }

        var records = files.values.flatMap(\.records)
        records += databases.refresh(home: home, cutoff: cutoff)
        var result = UsageScanner.Result()
        result.history = UsageScanner.history(records, since: cutoff)
        for state in files.values {
            if let l = state.limits, l.fetchedAt > (result.codexLimits?.fetchedAt ?? .distantPast) { result.codexLimits = l }
        }
        return result
    }

    /// Command Code keeps sidecars (`<id>.checkpoints.jsonl`, `<id>.prompts.jsonl`) next to sessions.
    static func isTranscript(_ url: URL, agent: AgentKind) -> Bool {
        switch agent {
        case .commandcode: !url.deletingPathExtension().lastPathComponent.contains(".")
        case .qwen: url.pathComponents.contains("chats")
        default: true
        }
    }

    private static func read(_ url: URL, agent: AgentKind, into state: inout FileState) {
        let (lines, end) = UsageScanner.lines(url, from: state.offset)
        state.offset = end
        for line in lines {
            switch agent {
            case .codex:
                guard let u = UsageScanner.codexUsage(line: line) else { continue }
                if let l = u.limits { state.limits = l }
                var tokens = u.tokens
                if let total = u.total {
                    // Codex sometimes re-emits the same totals; only count turns that moved them.
                    if total == state.codexTotal { continue }
                    if tokens == 0, let prev = state.codexTotal { tokens = total - prev }
                    state.codexTotal = total
                }
                state.records.append(UsageRecord(key: nil, date: u.date, agent: .codex, tokens: tokens))
            case .qwen: if let r = UsageScanner.qwenUsage(line: line) { state.records.append(r) }
            case .pi: if let r = UsageScanner.piUsage(line: line) { state.records.append(r) }
            case .commandcode: if let r = UsageScanner.commandCodeUsage(line: line) { state.records.append(r) }
            default: if let r = UsageScanner.claudeUsage(line: line) { state.records.append(r) }
            }
        }
    }
}
