import Foundation

/// Antigravity CLI's permission prompt as rendered in its terminal:
///
///     Run this command?
///     > 1. Yes, run command
///       2. Yes, and always allow in this conversation for commands that start with 'echo'
///       4. No, cancel
///       ↑/↓ Navigate · tab Amend · …   esc to cancel
///
/// Reading it back from the pane is both how the notch learns the options and the safety
/// check before typing: no menu on screen, nothing typed.
public struct AntigravityMenu: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case approve, approveAlways, deny, other }

    public struct Option: Equatable, Sendable {
        public var number: Int
        public var label: String
        public var kind: Kind
    }

    public var question: String
    public var options: [Option]

    public var approve: Option? { options.first { $0.kind == .approve } }
    public var approveAlways: Option? { options.first { $0.kind == .approveAlways } }
    public var deny: Option? { options.first { $0.kind == .deny } }

    private static let optionLine = try! NSRegularExpression(pattern: #"^\s*(?:[>❯›▸»]\s*)?(\d)\.\s+(.+?)\s*$"#)
    private static let ansi = try! NSRegularExpression(pattern: #"\x1B\[[0-9;?]*[ -/]*[@-~]|\x1B\][^\x07]*\x07"#)

    public static func parse(_ screen: String) -> AntigravityMenu? {
        let clean = ansi.stringByReplacingMatches(in: screen, range: NSRange(screen.startIndex..., in: screen), withTemplate: "")
        let lines = clean.components(separatedBy: .newlines)
        // The newest menu is the one that can still be answered.
        guard let first = lines.indices.last(where: { optionNumber(lines[$0]) == 1 }) else { return nil }

        var options: [Option] = []
        var end = first
        for i in first..<lines.count {
            let line = lines[i]
            if let (n, label) = option(line) {
                guard n == options.count + 1 else { break }
                options.append(Option(number: n, label: label, kind: .other))
            } else if isHint(line) || line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            } else if !options.isEmpty {
                // A long label wrapped onto the next row.
                options[options.count - 1].label += " " + line.trimmingCharacters(in: .whitespaces)
            }
            end = i
        }

        // Anything but hints after the menu means it was already answered.
        let after = lines[(end + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard after.allSatisfy(isHint) else { return nil }

        guard let question = lines[..<first].last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces), question.hasSuffix("?")
        else { return nil }

        options = options.map { o in
            var o = o
            o.kind = kind(of: o.label)
            return o
        }
        let menu = AntigravityMenu(question: question, options: options)
        guard menu.deny != nil, menu.approve != nil || menu.approveAlways != nil else { return nil }
        return menu
    }

    private static func option(_ line: String) -> (Int, String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = optionLine.firstMatch(in: line, range: range),
            let n = Range(m.range(at: 1), in: line).flatMap({ Int(line[$0]) }),
            let label = Range(m.range(at: 2), in: line).map({ String(line[$0]) })
        else { return nil }
        return (n, label)
    }

    private static func optionNumber(_ line: String) -> Int? { option(line)?.0 }

    /// Footer rows Antigravity draws under the menu (key hints, model name).
    private static func isHint(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.contains("navigate") || l.contains("esc to cancel") || l.contains("enter confirm") || l.contains("tab amend")
    }

    static func kind(of label: String) -> Kind {
        let l = label.lowercased()
        if l.hasPrefix("yes") || l.hasPrefix("allow") || l.hasPrefix("approve") {
            return l.contains("always") ? .approveAlways : .approve
        }
        if l.hasPrefix("no") || l.contains("cancel") || l.hasPrefix("deny") || l.hasPrefix("reject") { return .deny }
        return .other
    }
}
