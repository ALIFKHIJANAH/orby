import SwiftUI

/// Block-level Markdown for plans: headings, lists, quotes, code fences, rules; inline via AttributedString.
struct MarkdownView: View {
    let markdown: String

    enum Block: Hashable {
        case heading(Int, String)
        case bullet(String, indent: Int)
        case numbered(String, String, indent: Int)
        case quote(String)
        case code(String)
        case rule
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Self.parse(markdown).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text, font: .system(size: level == 1 ? 16 : level == 2 ? 14 : 13, weight: .bold))
                .padding(.top, level <= 2 ? 4 : 2)
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(Theme.tertiaryText)
                inline(text)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let n, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n + ".").foregroundStyle(Theme.tertiaryText).monospacedDigit()
                inline(text)
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .quote(let text):
            inline(text)
                .foregroundStyle(Theme.secondaryText)
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.stroke).frame(width: 2) }
        case .code(let code):
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider().overlay(Theme.stroke)
        case .paragraph(let text):
            inline(text)
        }
    }

    private func inline(_ s: String, font: Font = .system(size: 12.5)) -> some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
        return Text(attributed)
            .font(font)
            .foregroundStyle(Theme.primaryText.opacity(0.92))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in md.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(line); continue }
            let indent = (line.count - line.drop(while: { $0 == " " }).count) / 2

            if trimmed.isEmpty { flush(); continue }
            if let hashes = trimmed.prefix(while: { $0 == "#" }).count as Int?, hashes > 0, hashes <= 6,
                trimmed.dropFirst(hashes).hasPrefix(" ")
            {
                flush()
                blocks.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1))))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush()
                blocks.append(.rule)
            } else if let rest = ["- [ ] ", "- [x] ", "- ", "* ", "+ "].lazy.compactMap({ p in trimmed.hasPrefix(p) ? (p, trimmed.dropFirst(p.count)) : nil }).first {
                flush()
                let box = rest.0 == "- [ ] " ? "☐ " : rest.0 == "- [x] " ? "☑ " : ""
                blocks.append(.bullet(box + rest.1, indent: indent))
            } else if let dot = trimmed.firstIndex(of: "."), trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty,
                trimmed[trimmed.index(after: dot)...].hasPrefix(" ")
            {
                flush()
                blocks.append(.numbered(String(trimmed[..<dot]), String(trimmed[trimmed.index(dot, offsetBy: 2)...]), indent: indent))
            } else if trimmed.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
