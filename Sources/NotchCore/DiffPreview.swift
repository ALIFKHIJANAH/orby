import Foundation
import NotchShared

public struct DiffLine: Hashable, Sendable {
    public enum Kind: Sendable { case added, removed, context, file }
    public var kind: Kind
    public var text: String
}

/// What a file edit will change, as a few readable +/- lines.
public struct DiffPreview: Hashable, Sendable {
    public var lines: [DiffLine]
    /// Lines left out after the cap.
    public var hiddenCount: Int
    public var fileName: String?
    /// A whole-file write rather than an in-place edit.
    public var isWholeFile: Bool

    public static func make(tool: String, input: JSONValue, maxLines: Int = 40) -> DiffPreview? {
        var lines: [DiffLine] = []
        var wholeFile = false
        let path = input["file_path"]?.string ?? input["notebook_path"]?.string ?? input["TargetFile"]?.string
        switch tool {
        case "Edit":
            lines = edit(old: input["old_string"]?.string ?? "", new: input["new_string"]?.string ?? "")
        case "MultiEdit":
            for (i, e) in (input["edits"]?.array ?? []).enumerated() {
                if i > 0 { lines.append(DiffLine(kind: .context, text: "⋯")) }
                lines += edit(old: e["old_string"]?.string ?? "", new: e["new_string"]?.string ?? "")
            }
        case "Write", "write_to_file":
            wholeFile = true
            let content = input["content"]?.string ?? input["CodeContent"]?.string ?? ""
            lines = split(content).map { DiffLine(kind: .added, text: $0) }
        case "NotebookEdit":
            lines = split(input["new_source"]?.string ?? "").map { DiffLine(kind: .added, text: $0) }
        case "apply_patch":
            lines = patch(input)
        default:
            return nil
        }
        guard !lines.isEmpty else { return nil }
        let hidden = max(0, lines.count - maxLines)
        return DiffPreview(
            lines: Array(lines.prefix(maxLines)), hiddenCount: hidden,
            fileName: path.map { ($0 as NSString).lastPathComponent }, isWholeFile: wholeFile)
    }

    public var addedCount: Int { lines.filter { $0.kind == .added }.count }
    public var removedCount: Int { lines.filter { $0.kind == .removed }.count }

    private static func split(_ s: String) -> [String] {
        var parts = s.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// Shared leading/trailing lines become (at most two) context lines on each side.
    static func edit(old: String, new: String) -> [DiffLine] {
        let a = split(old), b = split(new)
        var head = 0
        while head < min(a.count, b.count), a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < min(a.count, b.count) - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        var out: [DiffLine] = a[max(0, head - 2)..<head].map { DiffLine(kind: .context, text: $0) }
        out += a[head..<(a.count - tail)].map { DiffLine(kind: .removed, text: $0) }
        out += b[head..<(b.count - tail)].map { DiffLine(kind: .added, text: $0) }
        out += a[(a.count - tail)..<min(a.count, a.count - tail + 2)].map { DiffLine(kind: .context, text: $0) }
        return out
    }

    private static func patch(_ input: JSONValue) -> [DiffLine] {
        var texts: [String] = []
        func collect(_ v: JSONValue) {
            switch v {
            case .string(let s) where s.contains("*** "): texts.append(s)
            case .array(let a): a.forEach(collect)
            case .object(let o): o.values.forEach(collect)
            default: break
            }
        }
        collect(input)
        var out: [DiffLine] = []
        for line in split(texts.joined(separator: "\n")) {
            for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                out.append(DiffLine(kind: .file, text: (String(line.dropFirst(prefix.count)) as NSString).lastPathComponent))
            }
            if line.hasPrefix("***") || line.hasPrefix("@@") || line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            if line.hasPrefix("+") { out.append(DiffLine(kind: .added, text: String(line.dropFirst()))) }
            else if line.hasPrefix("-") { out.append(DiffLine(kind: .removed, text: String(line.dropFirst()))) }
            else if line.hasPrefix(" ") { out.append(DiffLine(kind: .context, text: String(line.dropFirst()))) }
        }
        return out
    }
}
