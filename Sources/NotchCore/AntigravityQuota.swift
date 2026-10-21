import Foundation
import NotchShared

/// Antigravity plan quota, per bucket ("gemini-weekly", "gemini-5h", "3p-weekly", ...).
/// Two sources feed it: the status line agy pipes to Orby's relay (local), and, opt-in,
/// `agy -p "/usage" --output-format json`. The newest reading wins per bucket.
public struct AntigravityQuota: Equatable, Sendable {
    public struct Bucket: Equatable, Sendable {
        public var id: String
        /// 0...1
        public var remaining: Double
        public var resetsAt: Date?
        public var observedAt: Date

        public init(id: String, remaining: Double, resetsAt: Date?, observedAt: Date) {
            self.id = id
            self.remaining = remaining
            self.resetsAt = resetsAt
            self.observedAt = observedAt
        }
    }

    public var buckets: [String: Bucket] = [:]
    /// `plan_tier` from the status line ("Pro", "Ultra"); `/usage` doesn't report it.
    public var plan: String?

    public init(buckets: [String: Bucket] = [:], plan: String? = nil) {
        self.buckets = buckets
        self.plan = plan
    }

    public var isEmpty: Bool { buckets.isEmpty && plan == nil }

    public mutating func merge(_ other: AntigravityQuota) {
        for (id, b) in other.buckets where b.observedAt >= (buckets[id]?.observedAt ?? .distantPast) { buckets[id] = b }
        if let p = other.plan { plan = p }
    }

    public var rateLimits: RateLimits? {
        guard !buckets.isEmpty else { return nil }
        let windows = buckets.values.sorted { Self.sortKey($0.id) < Self.sortKey($1.id) }.map {
            UsageWindow(label: AntigravityStatusLine.label(bucket: $0.id), used: 1 - $0.remaining, resetsAt: $0.resetsAt)
        }
        let fetched = buckets.values.map(\.observedAt).max() ?? .distantPast
        return RateLimits(provider: .antigravity, plan: plan, windows: windows, fetchedAt: fetched)
    }

    /// Gemini first, then the other groups; shorter windows first within a group.
    private static func sortKey(_ id: String) -> (Int, String, Int, String) {
        let lower = id.lowercased()
        let window = lower.contains("5h") ? 1 : lower.contains("day") || lower.contains("1d") ? 2 : lower.contains("week") || lower.contains("7d") ? 3 : 4
        let group = lower.split(separator: "-").first.map(String.init) ?? lower
        return (group == "gemini" ? 0 : 1, group, window, lower)
    }

    /// The status line payload: `quota: {"<bucket-id>": {remaining_fraction, reset_time, reset_in_seconds?}}`.
    public static func statusLine(_ v: JSONValue, now: Date = Date()) -> AntigravityQuota? {
        var q = AntigravityQuota(plan: v["plan_tier"]?.string.flatMap { $0.isEmpty ? nil : $0 })
        for (id, b) in v["quota"]?.object ?? [:] {
            if let bucket = bucket(id: id, b, now: now) { q.buckets[id] = bucket }
        }
        return q.isEmpty ? nil : q
    }

    /// `agy -p "/usage" --output-format json`. Its shape is undocumented, so this looks for
    /// anything bucket-like (`command.data.groups[].buckets[]` today) and skips whatever it
    /// can't read for sure: no numbers beats wrong numbers.
    public static func usageCommand(_ v: JSONValue, now: Date = Date()) -> AntigravityQuota? {
        // A real turn means agy treated "/usage" as a prompt: don't trust anything in it.
        if let turns = v["num_turns"]?.int, turns > 0 { return nil }
        var q = AntigravityQuota()
        collect(v, now: now, into: &q, depth: 0)
        return q.isEmpty ? nil : q
    }

    private static func collect(_ v: JSONValue, now: Date, into q: inout AntigravityQuota, depth: Int) {
        guard depth < 8 else { return }
        if let obj = v.object {
            let id = (obj["id"] ?? obj["bucket_id"] ?? obj["bucketId"])?.string
            if let id, !id.isEmpty, let b = bucket(id: id, v, now: now) {
                q.buckets[id] = b
                return
            }
            for child in obj.values { collect(child, now: now, into: &q, depth: depth + 1) }
        } else if let arr = v.array {
            for child in arr { collect(child, now: now, into: &q, depth: depth + 1) }
        }
    }

    private static func bucket(id: String, _ b: JSONValue, now: Date) -> Bucket? {
        let remaining: Double
        if let f = (b["remaining_fraction"] ?? b["remainingFraction"])?.double {
            remaining = f
        } else if let p = (b["remaining_percent"] ?? b["remainingPercent"])?.double {
            remaining = p / 100
        } else {
            return nil
        }
        guard remaining.isFinite, remaining >= -0.001, remaining <= 1.001 else { return nil }
        var reset = UsageScanner.date(b["reset_time"] ?? b["resetTime"])
        if reset == nil, let s = (b["reset_in_seconds"] ?? b["resetInSeconds"])?.double, s >= 0 {
            reset = now.addingTimeInterval(s)
        }
        return Bucket(id: id, remaining: min(1, max(0, remaining)), resetsAt: reset, observedAt: now)
    }
}

extension AntigravityQuota {
    /// agy 1.1.11 made `-p "/usage"` answer without an agent turn. Older builds may send it to
    /// the model as a prompt, which spends quota, so they're never run.
    public static let minimumHeadlessVersion = [1, 1, 11]

    public static func supportsHeadlessUsage(version output: String) -> Bool {
        guard let r = output.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else { return false }
        let v = output[r].split(separator: ".").compactMap { Int($0) }
        return v.lexicographicallyPrecedes(minimumHeadlessVersion) == false
    }
}
