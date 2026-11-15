import Foundation

/// Orby's `[[hooks]]` tables in a TOML config (Kimi Code's config.toml), kept between two
/// marker comments at the end of the file. Only the text between the markers is ever written
/// or removed, so the rest of the file stays byte-identical, comments and formatting included.
/// There is no TOML parser here on purpose: a malformed config stops Kimi from starting, and
/// re-serialising someone's file is the surest way to produce one.
public enum TOMLHookBlock {
    static let begin = "# >>> orby-bridge hooks: written by Orby (Settings → Integrations). Edits are overwritten. >>>"
    static let end = "# <<< orby-bridge hooks <<<"
    /// End marker used when the file had no final newline, so removal can take back the one Orby added.
    static let endAddedNewline = "# <<< orby-bridge hooks (added a final newline) <<<"

    public enum EditError: LocalizedError, Equatable {
        /// A begin marker without its end marker: the block was edited by hand.
        case brokenBlock
        /// The file already defines `hooks` some other way; a `[[hooks]]` table would clash with it.
        case conflictingHooksKey
        case notUTF8
        public var errorDescription: String? {
            switch self {
            case .notUTF8: "it isn’t plain UTF-8 text"
            case .brokenBlock: "Orby’s hook block is missing its end marker"
            case .conflictingHooksKey: "it already defines hooks in a way Orby can’t add to"
            }
        }
    }

    /// One `[[hooks]]` table per event. Literal strings need no escaping; commands never contain `'`.
    public static func block(events: [String], command: (String) -> String, timeout: (String) -> Int) -> String {
        var lines = [begin]
        for event in events {
            let cmd = command(event)
            precondition(!cmd.contains("'") && !cmd.contains("\n"), "command must fit a TOML literal string")
            lines += ["[[hooks]]", "event = \"\(event)\"", "command = '\(cmd)'", "timeout = \(timeout(event))", ""]
        }
        lines.append(end)
        return lines.joined(separator: "\n") + "\n"
    }

    public static func contains(_ text: String) -> Bool { text.contains(begin) }

    /// Events Orby's block registers, read back from the block itself.
    public static func events(in text: String) -> Set<String> {
        guard let range = try? blockRange(in: text) else { return [] }
        var found = Set<String>()
        for line in text[range.lines].split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "event" { found.insert(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))) }
        }
        return found
    }

    /// `text` with Orby's block replaced by `block` (appended at the end, where a new table can't
    /// capture any of the user's keys).
    public static func installing(_ block: String, into text: String) throws -> String {
        let base = try uninstalling(from: text)
        if definesHooksElsewhere(base) { throw EditError.conflictingHooksKey }
        if base.isEmpty || base.last?.isNewline == true { return base + block }
        return base + "\n" + block.replacingOccurrences(of: end + "\n", with: endAddedNewline + "\n")
    }

    /// `text` without Orby's block: exactly what it was before `installing`.
    public static func uninstalling(from text: String) throws -> String {
        var text = text
        while let range = try blockRange(in: text) {
            text.removeSubrange(range.removal)
        }
        return text
    }

    private struct BlockRange {
        /// From the start of the begin line to the end of the end line, newline included.
        var lines: Range<String.Index>
        /// `lines`, plus the newline Orby added before the block, if it added one.
        var removal: Range<String.Index>
    }

    private static func blockRange(in text: String) throws -> BlockRange? {
        guard let b = lineRange(of: begin, in: text) else { return nil }
        let rest = text[b.upperBound...]
        let plain = lineRange(of: end, in: text, from: rest.startIndex)
        let added = lineRange(of: endAddedNewline, in: text, from: rest.startIndex)
        guard let e = [plain, added].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { throw EditError.brokenBlock }
        let lines = b.lowerBound..<e.upperBound
        var start = b.lowerBound
        if e == added, start > text.startIndex, text[text.index(before: start)] == "\n" { start = text.index(before: start) }
        return BlockRange(lines: lines, removal: start..<e.upperBound)
    }

    /// Range of the whole line (newline included) whose content is exactly `marker`.
    private static func lineRange(of marker: String, in text: String, from: String.Index? = nil) -> Range<String.Index>? {
        var search = from ?? text.startIndex
        while let r = text.range(of: marker, range: search..<text.endIndex) {
            let atLineStart = r.lowerBound == text.startIndex || text[text.index(before: r.lowerBound)].isNewline
            var tail = r.upperBound
            if tail < text.endIndex, text[tail] == "\r" { tail = text.index(after: tail) }
            let atLineEnd = tail == text.endIndex || text[tail] == "\n"
            if atLineStart && atLineEnd { return r.lowerBound..<(tail == text.endIndex ? tail : text.index(after: tail)) }
            search = r.upperBound
        }
        return nil
    }

    /// A root-level `hooks = …` key or a `[hooks]` table, either of which makes `[[hooks]]` invalid.
    static func definesHooksElsewhere(_ text: String) -> Bool {
        var atRoot = true
        var inMultiline: String?
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let delimiter = inMultiline {
                if line.components(separatedBy: delimiter).count > 1 { inMultiline = nil }
                continue
            }
            for delimiter in ["\"\"\"", "'''"] where line.components(separatedBy: delimiter).count == 2 {
                inMultiline = delimiter
            }
            if line.hasPrefix("[") {
                let name = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).split(separator: "#").first?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[] \t")) ?? ""
                if !line.hasPrefix("[[") && (name == "hooks" || name.hasPrefix("hooks.")) { return true }
                atRoot = false
            } else if atRoot, line.hasPrefix("hooks") {
                let after = line.dropFirst(5).drop { $0 == " " || $0 == "\t" }
                if after.hasPrefix("=") || after.hasPrefix(".") { return true }
            }
        }
        return false
    }
}
