import Foundation
import NotchShared

/// JSON with comments and trailing commas, as Gemini CLI writes its settings.json.
/// Reading strips both; writing replaces a single top-level member and leaves every other
/// byte (comments, commas, key order, formatting) exactly as it was.
public enum JSONC {
    public enum EditError: Error, Equatable {
        /// Not an object at the top level, or unbalanced brackets.
        case malformed
        /// The member to rewrite contains comments, which a rewrite would drop.
        case commentsInside(String)
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        guard let text = String(data: data, encoding: .utf8) else { throw EditError.malformed }
        if text.allSatisfy(\.isWhitespace) { return .object([:]) }
        return try JSONValue.decode(Data(stripped(text).utf8))
    }

    /// The same text with comments blanked out and trailing commas removed; offsets are kept.
    static func stripped(_ text: String) -> String {
        var bytes = Array(text.utf8)
        let tokens = scan(bytes)
        for (i, t) in tokens.enumerated() {
            switch t.kind {
            case .comment:
                for j in t.start..<t.end where bytes[j] != UInt8(ascii: "\n") { bytes[j] = UInt8(ascii: " ") }
            case .comma:
                let next = tokens[(i + 1)...].first { $0.kind != .comment }
                if next == nil || next!.kind == .close { bytes[t.start] = UInt8(ascii: " ") }
            default:
                break
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Set (or, with nil, remove) the top-level member `key`, touching nothing else.
    public static func setting(_ key: String, to value: JSONValue?, in text: String) throws -> String {
        var bytes = Array(text.utf8)
        let tokens = scan(bytes).filter { $0.kind != .comment }
        let comments = scan(bytes).filter { $0.kind == .comment }
        if tokens.isEmpty {
            guard let value else { return text }
            return "{\n  \(try member(key, value, indent: "  "))\n}\n"
        }
        guard tokens.first?.kind == .open, bytes[tokens[0].start] == UInt8(ascii: "{") else { throw EditError.malformed }
        let members = try topLevelMembers(tokens, bytes)
        guard let close = members.close else { throw EditError.malformed }
        let indent = members.list.first.map { lineIndent(bytes, before: $0.keyStart) } ?? "  "

        if let m = members.list.first(where: { $0.key == key }) {
            let valueStart = tokens[m.valueFirst].start, valueEnd = tokens[m.valueLast].end
            guard let value else {
                remove(m, tokens: tokens, from: &bytes)
                return String(decoding: bytes, as: UTF8.self)
            }
            if comments.contains(where: { $0.start >= valueStart && $0.end <= valueEnd }) { throw EditError.commentsInside(key) }
            let rendered = try render(value, indent: lineIndent(bytes, before: m.keyStart))
            bytes.replaceSubrange(valueStart..<valueEnd, with: Array(rendered.utf8))
            return String(decoding: bytes, as: UTF8.self)
        }

        guard let value else { return text }
        // After the last thing before the closing brace (a value, a trailing comma or a comment).
        var at = tokens[close].start
        while at > 0, isSpace(bytes[at - 1]) { at -= 1 }
        let prev = tokens[close - 1]
        var insertion = "\n\(indent)\(try member(key, value, indent: indent))"
        // Keep a trailing-comma style going.
        if prev.kind == .comma { insertion += "," }
        bytes.insert(contentsOf: Array(insertion.utf8), at: at)
        if prev.kind != .comma && prev.kind != .open { bytes.insert(UInt8(ascii: ","), at: prev.end) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Editing

    private static func member(_ key: String, _ value: JSONValue, indent: String) throws -> String {
        let name = String(decoding: try JSONValue.string(key).encoded(), as: UTF8.self)
        return "\(name): \(try render(value, indent: indent))"
    }

    private static func render(_ value: JSONValue, indent: String) throws -> String {
        let pretty = String(decoding: try value.encoded(pretty: true), as: UTF8.self)
        return pretty.components(separatedBy: "\n").enumerated().map { $0.offset == 0 ? $0.element : indent + $0.element }
            .joined(separator: "\n")
    }

    /// Removes a member and the comma that separated it, so an insert followed by a remove
    /// gives back the original text.
    private static func remove(_ m: Member, tokens: [Token], from bytes: inout [UInt8]) {
        var start = m.keyStart
        while start > 0, isSpace(bytes[start - 1]) { start -= 1 }
        let before = tokens[tokens.firstIndex { $0.start == m.keyStart }! - 1]
        let after = tokens[m.valueLast + 1]
        if after.kind == .comma {
            bytes.removeSubrange(start..<after.end)
        } else {
            bytes.removeSubrange(start..<tokens[m.valueLast].end)
            // It was the last member: the comma before it would now dangle.
            if before.kind == .comma { bytes.remove(at: before.start) }
        }
    }

    private static func lineIndent(_ bytes: [UInt8], before index: Int) -> String {
        var i = index
        while i > 0, bytes[i - 1] == UInt8(ascii: " ") || bytes[i - 1] == UInt8(ascii: "\t") { i -= 1 }
        guard i == 0 || bytes[i - 1] == UInt8(ascii: "\n") else { return "  " }
        return String(decoding: bytes[i..<index], as: UTF8.self)
    }

    private static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }

    // MARK: Scanning

    struct Token: Equatable {
        enum Kind { case open, close, colon, comma, string, literal, comment }
        var kind: Kind
        var start: Int
        var end: Int
    }

    private struct Member {
        var key: String
        var keyStart: Int
        /// Token indices of the value's first and last token.
        var valueFirst: Int
        var valueLast: Int
    }

    private static func topLevelMembers(_ tokens: [Token], _ bytes: [UInt8]) throws -> (list: [Member], close: Int?) {
        var list: [Member] = []
        var depth = 0
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            switch t.kind {
            case .open: depth += 1
            case .close:
                depth -= 1
                if depth == 0 { return (list, i) }
                if depth < 0 { throw EditError.malformed }
            case .string where depth == 1 && i + 2 < tokens.count && tokens[i + 1].kind == .colon:
                let raw = Data(bytes[t.start..<t.end])
                guard let key = try? JSONValue.decode(raw).string else { throw EditError.malformed }
                // The value runs until the bracket depth comes back to the root's.
                var j = i + 2
                var d = 0
                repeat {
                    if tokens[j].kind == .open { d += 1 }
                    if tokens[j].kind == .close { d -= 1 }
                    j += 1
                } while d > 0 && j < tokens.count
                guard d == 0 else { throw EditError.malformed }
                list.append(Member(key: key, keyStart: t.start, valueFirst: i + 2, valueLast: j - 1))
                i = j
                continue
            default:
                break
            }
            i += 1
        }
        return (list, nil)
    }

    static func scan(_ b: [UInt8]) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        while i < b.count {
            let c = b[i]
            let start = i
            switch c {
            case UInt8(ascii: "{"), UInt8(ascii: "["): tokens.append(Token(kind: .open, start: i, end: i + 1)); i += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"): tokens.append(Token(kind: .close, start: i, end: i + 1)); i += 1
            case UInt8(ascii: ":"): tokens.append(Token(kind: .colon, start: i, end: i + 1)); i += 1
            case UInt8(ascii: ","): tokens.append(Token(kind: .comma, start: i, end: i + 1)); i += 1
            case UInt8(ascii: "\""):
                i += 1
                while i < b.count, b[i] != UInt8(ascii: "\"") { i += b[i] == UInt8(ascii: "\\") ? 2 : 1 }
                i = min(i + 1, b.count)
                tokens.append(Token(kind: .string, start: start, end: i))
            case UInt8(ascii: "/") where i + 1 < b.count && b[i + 1] == UInt8(ascii: "/"):
                while i < b.count, b[i] != UInt8(ascii: "\n") { i += 1 }
                tokens.append(Token(kind: .comment, start: start, end: i))
            case UInt8(ascii: "/") where i + 1 < b.count && b[i + 1] == UInt8(ascii: "*"):
                i += 2
                while i < b.count, !(b[i] == UInt8(ascii: "*") && i + 1 < b.count && b[i + 1] == UInt8(ascii: "/")) { i += 1 }
                i = min(i + 2, b.count)
                tokens.append(Token(kind: .comment, start: start, end: i))
            case _ where isSpace(c):
                i += 1
            default:
                while i < b.count, !isSpace(b[i]), !"{}[]:,\"/".utf8.contains(b[i]) { i += 1 }
                if i == start { i += 1 }
                tokens.append(Token(kind: .literal, start: start, end: i))
            }
        }
        return tokens
    }
}
