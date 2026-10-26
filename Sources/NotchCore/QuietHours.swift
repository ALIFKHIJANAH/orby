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
