import Foundation

/// Rules that hide sessions from the list: folders (a path and everything under it) and text
/// in the first prompt. Hidden sessions stay tracked so their blocking requests still reach the
/// user; the app only keeps them out of the list and stops them popping the island or chiming.
public struct SessionFilter: Equatable, Sendable {
    public var folders: [String]
    public var promptSubstrings: [String]

    public init(folders: [String] = [], promptSubstrings: [String] = [], home: String = NSHomeDirectory()) {
        self.folders = folders.compactMap { Self.normalizedFolder($0, home: home) }
        self.promptSubstrings = promptSubstrings.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Settings store each rule list as one rule per line.
    public init(folderLines: String, promptLines: String, home: String = NSHomeDirectory()) {
        func lines(_ s: String) -> [String] { s.split(whereSeparator: \.isNewline).map(String.init) }
        self.init(folders: lines(folderLines), promptSubstrings: lines(promptLines), home: home)
    }

    public var isEmpty: Bool { folders.isEmpty && promptSubstrings.isEmpty }

    public func hides(_ session: AgentSession) -> Bool {
        hides(cwd: session.cwd, firstPrompt: session.firstPrompt ?? session.title)
    }

    /// Folders compare whole path components ("/work/app" doesn't hide "/work/app2"), ignoring
    /// case like the default macOS file system does; prompts match case-insensitively.
    public func hides(cwd: String, firstPrompt: String?) -> Bool {
        if !cwd.isEmpty, let path = Self.normalizedFolder(cwd, home: "") {
            for folder in folders {
                if folder == "/" { return true }
                if path.compare(folder, options: .caseInsensitive) == .orderedSame { return true }
                if path.lowercased().hasPrefix(folder.lowercased() + "/") { return true }
            }
        }
        guard let prompt = firstPrompt, !prompt.isEmpty else { return false }
        return promptSubstrings.contains { prompt.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Expands "~", drops trailing slashes; nil for blank or relative entries, which can't match a cwd.
    static func normalizedFolder(_ raw: String, home: String) -> String? {
        var path = raw.trimmingCharacters(in: .whitespaces)
        if path == "~" || path.hasPrefix("~/"), !home.isEmpty { path = home + path.dropFirst() }
        guard path.hasPrefix("/") else { return nil }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
