import Foundation

/// The session switcher's list: what's waiting on you first, then what's working, then the rest,
/// newest first in each group. Typing narrows it by project, title or branch.
public enum SessionSwitcher {
    public static func entries(_ sessions: [AgentSession], query: String) -> [AgentSession] {
        let ordered = sessions.sorted { ($0.phase.group, $1.updatedAt, $0.id) < ($1.phase.group, $0.updatedAt, $1.id) }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return ordered }
        // Stable: within a rank the status order above still holds.
        return ordered.enumerated()
            .compactMap { i, s in rank(s, words).map { (rank: $0, index: i, session: s) } }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.session)
    }

    /// Every word must appear somewhere. Lower is better: the project name starting with the
    /// first word beats a word start elsewhere, which beats a match mid-word. nil: no match.
    static func rank(_ session: AgentSession, _ words: [String]) -> Int? {
        let fields = [session.projectName, session.title ?? "", session.git?.branch ?? ""]
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for word in words where !fields.contains(where: { $0.range(of: word, options: options) != nil }) { return nil }
        let first = words[0]
        if session.projectName.range(of: first, options: options.union(.anchored)) != nil { return 0 }
        let startsWord = fields.contains { field in
            field.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains { $0.range(of: first, options: options.union(.anchored)) != nil }
        }
        return startsWord ? 1 : 2
    }

    /// Arrow keys move the selection and wrap around the ends.
    public static func move(_ selection: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selection + step) % count + count) % count
    }
}
