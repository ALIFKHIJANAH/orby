import Foundation

/// Branch + worktree info read straight from `.git` files (no `git` process per event).
public struct GitInfo: Hashable, Sendable {
    public var branch: String?
    /// Root of the main checkout; for a linked worktree this differs from `worktreeRoot`.
    public var repoRoot: String
    public var worktreeRoot: String
    public var isWorktree: Bool { repoRoot != worktreeRoot }
    public var projectName: String { (repoRoot as NSString).lastPathComponent }

    public static func resolve(cwd: String, fileManager: FileManager = .default) -> GitInfo? {
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                return isDir.boolValue
                    ? GitInfo(branch: branch(gitDir: dotGit), repoRoot: dir.path, worktreeRoot: dir.path)
                    : linkedWorktree(root: dir, pointer: dotGit)
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    /// `.git` file containing "gitdir: <main>/.git/worktrees/<name>".
    private static func linkedWorktree(root: URL, pointer: URL) -> GitInfo? {
        guard let text = try? String(contentsOf: pointer, encoding: .utf8),
            let line = text.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:")
        else { return nil }
        var gitDirPath = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitDirPath.hasPrefix("/") { gitDirPath = root.appendingPathComponent(gitDirPath).standardized.path }
        let gitDir = URL(fileURLWithPath: gitDirPath)

        var commonDir = gitDir
        if let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) {
            let c = common.trimmingCharacters(in: .whitespacesAndNewlines)
            commonDir = c.hasPrefix("/") ? URL(fileURLWithPath: c) : gitDir.appendingPathComponent(c).standardized
        }
        let repoRoot = commonDir.lastPathComponent == ".git" ? commonDir.deletingLastPathComponent().path : root.path
        return GitInfo(branch: branch(gitDir: gitDir), repoRoot: repoRoot, worktreeRoot: root.path)
    }

    private static func branch(gitDir: URL) -> String? {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let h = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("ref: refs/heads/") { return String(h.dropFirst("ref: refs/heads/".count)) }
        return h.isEmpty ? nil : String(h.prefix(7))  // detached HEAD → short SHA
    }
}
