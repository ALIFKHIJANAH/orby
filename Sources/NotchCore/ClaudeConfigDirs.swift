import Foundation
import NotchShared

/// Claude Code config folders beyond the one `claude` uses by default (~/.claude or
/// $CLAUDE_CONFIG_DIR), e.g. a second account run with `CLAUDE_CONFIG_DIR=~/.claude-work claude`.
/// Each gets the same hooks as the default folder.
public enum ClaudeConfigDirs {
    public static func defaultDir(home: URL = NotchPaths.homeDirectory, environment: [String: String] = ProcessInfo.processInfo.environment)
        -> URL
    {
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir, isDirectory: true) }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// The user's extra folders, `~` expanded, without blanks, duplicates, or the folders Orby
    /// already handles as the default (which would otherwise be connected twice).
    public static func extras(
        _ paths: [String], home: URL = NotchPaths.homeDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var seen: Set<String> = [
            key(home.appendingPathComponent(".claude")), key(defaultDir(home: home, environment: environment)),
        ]
        return paths.compactMap { raw in
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            let expanded = path == "~" ? home.path : path.hasPrefix("~/") ? home.path + path.dropFirst(1) : path
            let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            return seen.insert(key(url)).inserted ? url : nil
        }
    }

    public static func settingsURL(_ dir: URL) -> URL { dir.appendingPathComponent("settings.json") }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    /// Backup name prefix: the folder's name, so two folders' settings.json backups don't collide.
    static func backupName(_ dir: URL) -> String {
        "claude-" + dir.lastPathComponent.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
    }
}

extension HookInstaller {
    /// Status of Orby's Claude hooks in one extra config folder; `.agentMissing` when the folder is gone.
    public static func status(claudeConfigDir dir: URL) -> Status {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return .agentMissing }
        return hookStatus(.claude, at: ClaudeConfigDirs.settingsURL(dir))
    }

    /// Connect or remove Orby's Claude hooks in one extra config folder. Returns the backup, if any.
    @discardableResult
    public static func apply(
        claudeConfigDir dir: URL, install: Bool, backupDir: URL = NotchPaths.backups, now: Date = Date()
    ) throws -> URL? {
        try applyHooks(
            .claude, install: install, at: ClaudeConfigDirs.settingsURL(dir), backupName: ClaudeConfigDirs.backupName(dir),
            backupDir: backupDir, now: now)
    }
}
