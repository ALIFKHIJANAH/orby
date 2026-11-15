import Foundation

/// A plan-limit window that just went past an alert threshold.
public struct UsageAlert: Hashable, Sendable {
    public var agent: AgentKind
    public var window: UsageWindow
    public var threshold: Double

    public var title: String { "\(agent.displayName) \(window.label) limit at \(Int((window.used * 100).rounded()))%" }
}

/// Alerts once per threshold as usage climbs. The first reading of a window is only a baseline,
/// so relaunching Orby at 90% doesn't alert again; usage dropping (a reset) re-arms the thresholds.
public struct UsageAlertTracker: Sendable {
    public static let thresholds = [0.8, 0.95]

    /// Highest threshold reached per window id (0 = below all of them).
    private var levels: [String: Double] = [:]

    public init() {}

    public mutating func check(_ limits: [RateLimits], now: Date = Date()) -> [UsageAlert] {
        var alerts: [UsageAlert] = []
        for l in limits {
            for w in l.windows where !w.isStale(now: now) {
                let id = RateLimits.windowID(l.provider, w.label)
                let level = Self.thresholds.last { w.used >= $0 } ?? 0
                defer { levels[id] = level }
                guard let previous = levels[id], level > previous else { continue }
                alerts.append(UsageAlert(agent: l.provider, window: w, threshold: level))
            }
        }
        return alerts
    }
}
