import Foundation

public enum NotchPaths {
    /// `ORBY_HOME` overrides the root, which keeps tests away from the real install.
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["ORBY_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".orby", isDirectory: true)
    }

    /// Data folder from before the NotchIsland → Orby rename; only read by the launch migration.
    public static var legacyRoot: URL { homeDirectory.appendingPathComponent(".notchisland", isDirectory: true) }
    public static var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var bin: URL { root.appendingPathComponent("bin", isDirectory: true) }
    public static var run: URL { root.appendingPathComponent("run", isDirectory: true) }
    public static var socket: URL { run.appendingPathComponent("app.sock") }
    public static var installedBridge: URL { bin.appendingPathComponent("orby-bridge") }
    public static var backups: URL { root.appendingPathComponent("backups", isDirectory: true) }
}
