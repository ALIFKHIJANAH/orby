import Foundation

/// A daily window, in whole hours, when Orby keeps its sounds to itself.
public enum QuietHours {
    /// True when `date` falls in [start, end). A window past midnight (22 → 8) wraps;
    /// start == end means no quiet hours.
    public static func contains(_ date: Date, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if start == end { return false }
        return start < end ? (start..<end).contains(hour) : hour >= start || hour < end
    }
}

/// Whether a sound cue should stay silent right now. Pure, so the app passes in what it observed.
public struct QuietRules: Sendable {
    public var muteWhenLocked: Bool
    /// Quiet-hours window (start, end), or nil when quiet hours are off.
    public var quietHours: (start: Int, end: Int)?
    /// Treat an active macOS Focus like quiet hours.
    public var followFocus: Bool

    public init(muteWhenLocked: Bool, quietHours: (start: Int, end: Int)?, followFocus: Bool) {
        self.muteWhenLocked = muteWhenLocked
        self.quietHours = quietHours
        self.followFocus = followFocus
    }

    /// `focusOn` is nil when Orby may not read Focus status; that counts as no Focus.
    public func silencesSounds(at date: Date, screenLocked: Bool, focusOn: Bool?, calendar: Calendar = .current) -> Bool {
        if screenLocked && muteWhenLocked { return true }
        if followFocus && focusOn == true { return true }
        guard let window = quietHours else { return false }
        return QuietHours.contains(date, start: window.start, end: window.end, calendar: calendar)
    }
}
