import Foundation

/// Turns agent Markdown (replies, thoughts, errors) into short plain sentences for the notch.
public enum PlainText {
    /// Headings that carry no information on their own ("## Summary").
    private static let filler: Set<String> = [
        "summary", "done", "changes", "overview", "result", "results", "update", "updates", "status", "notes",
        "tl;dr", "tldr", "next steps", "details", "context", "plan",
    ]

    /// Leading sentences that fit in `max` characters; a single long sentence is cut at a word.
    public static func summary(_ markdown: String, max: Int) -> String {
        let sentences = split(join(lines(markdown, enough: max)))
        guard let first = sentences.first else { return "" }
        var out = first
        for s in sentences.dropFirst() {
            guard out.count + 1 + s.count <= max else { break }
            out += " " + s
        }
        return truncate(out, max: max)
    }

    /// The most recent sentence, for streaming thoughts. A very short one keeps its predecessor.
    public static func latest(_ markdown: String, max: Int) -> String {
        let sentences = split(join(lines(markdown)))
        guard var out = sentences.last else { return "" }
        if out.count < 25, sentences.count > 1 {
            let prev = sentences[sentences.count - 2]
            if prev.count + 1 + out.count <= max { out = prev + " " + out }
        }
        return truncate(out, max: max)
    }

    /// First meaningful line without added punctuation, e.g. a plan's title.
    public static func title(_ markdown: String, max: Int) -> String {
        truncate(lines(markdown, enough: 0).first ?? "", max: max)
    }

    /// Cut at a word boundary and add "…" when longer than `max`.
    public static func truncate(_ s: String, max: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max, max > 1 else { return trimmed }
        var cut = String(trimmed.prefix(max - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > max / 2 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—")) + "…"
    }

    /// Strips bold/italic/code/link syntax, keeping the visible text.
    public static func inline(_ s: String) -> String {
        // The Markdown parser is costly and most lines carry no inline syntax at all.
        guard s.contains(where: { "*_`[]<>\\~&!".contains($0) }) else { return s }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: s, options: options) {
            return String(attributed.characters)
        }
        return s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }

    /// Readable lines: no fences, tables, rules, block markers or filler headings. With `enough`,
    /// stops one line after the text passes that many characters: callers that keep only the
    /// leading `enough` characters never reach further, and the extra line keeps the punctuation
    /// `join` gives the last line the same as with the full text.
    static func lines(_ markdown: String, enough: Int = .max) -> [String] {
        var result: [String] = []
        var inFence = false
        var length = 0
        for raw in markdown.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || line.isEmpty || line.hasPrefix("|") { continue }
            if line.allSatisfy({ "-*_=".contains($0) || $0 == " " }) { continue }  // horizontal rule

            var isHeading = false
            if line.hasPrefix("#") {
                isHeading = true
                line = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            }
            line = stripBlockMarker(line)
            line = inline(line).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let bare = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":. "))
            if (isHeading || line.hasSuffix(":")) && filler.contains(bare) { continue }
            result.append(line)
            if length > enough { break }
            length += line.count + 1
        }
        return result
    }

    private static func stripBlockMarker(_ line: String) -> String {
        var s = Substring(line)
        while s.hasPrefix(">") { s = s.dropFirst().drop(while: { $0 == " " }) }
        for marker in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ ", "• "] where s.hasPrefix(marker) {
            return String(s.dropFirst(marker.count))
        }
        // "1. " / "1) "
        let digits = s.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let rest = s.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return String(rest.dropFirst(2)) }
        }
        return String(s)
    }

    /// One paragraph; headings and list items become their own sentences. The final line
    /// keeps its own punctuation, so a one-line message comes back unchanged.
    private static func join(_ lines: [String]) -> String {
        lines.enumerated().map { i, line in
            guard i < lines.count - 1, let last = line.last, !".!?:;…".contains(last) else { return line }
            return line + "."
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Sentences split after ., ! or ? followed by a space (keeps "e.g." mostly intact).
    private static func split(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            let afterNext = i + 2 < chars.count ? chars[i + 2] : "A"
            if ".!?…".contains(c), next == " ", afterNext.isUppercase || afterNext.isNumber || !afterNext.isLetter {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}
