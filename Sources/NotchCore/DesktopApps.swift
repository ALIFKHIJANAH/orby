import Foundation
import NotchShared

/// A GUI app that runs an agent with no terminal behind it: Claude Desktop's Code tab or the Codex app.
public enum DesktopApp: String, Codable, Hashable, Sendable {
    case claude
    case codex

    public var bundleID: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        }
    }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The bundle's folder name. Case matters: Claude Desktop runs its bundled CLI from a
    /// lowercase `claude.app` (bundle `com.anthropic.claude-code`) under Application Support.
    var bundleName: String { displayName + ".app" }

    /// `CLAUDE_CODE_ENTRYPOINT` values Claude Desktop sets for Code-tab sessions.
    static let claudeEntrypoints: Set<String> = ["claude-desktop", "claude-desktop-3p"]

    /// The desktop app hosting a hook's agent, from the bridge's forwarded env and process chain.
    public static func detect(env: [String: String], chain: [ProcessEntry]) -> DesktopHost? {
        if let host = chainMatch(chain) { return host }
        if let entry = env["CLAUDE_CODE_ENTRYPOINT"], claudeEntrypoints.contains(entry) { return DesktopHost(app: .claude) }
        switch env["__CFBundleIdentifier"]?.lowercased() {
        case DesktopApp.claude.bundleID: return DesktopHost(app: .claude)
        case DesktopApp.codex.bundleID: return DesktopHost(app: .codex)
        default: return nil
        }
    }

    /// The outermost ancestor inside Claude.app / Codex.app: helpers and the bundled CLI sit
    /// nearer the bridge, the app's main process last, and that one outlives a single turn.
    private static func chainMatch(_ chain: [ProcessEntry]) -> DesktopHost? {
        for entry in chain.reversed() {
            guard let path = entry.path, let bundle = ProcessTree.outermostAppBundle(in: path) else { continue }
            let name = (bundle as NSString).lastPathComponent
            if let app = [DesktopApp.claude, .codex].first(where: { $0.bundleName == name }) {
                return DesktopHost(app: app, pid: entry.pid, bundlePath: bundle)
            }
        }
        return nil
    }
}

public struct DesktopHost: Codable, Hashable, Sendable {
    public var app: DesktopApp
    /// The app's own process, when it showed up in the bridge's ancestry.
    public var pid: Int32?
    public var bundlePath: String?

    public init(app: DesktopApp, pid: Int32? = nil, bundlePath: String? = nil) {
        self.app = app
        self.pid = pid
        self.bundlePath = bundlePath
    }
}

extension TerminalContext {
    /// Whether the session's host is gone. Desktop sessions follow the app, not the agent
    /// process: the CLI Claude Desktop or Codex spawns may exit between turns.
    public func hostIsGone(isAlive: (Int32) -> Bool, isAppRunning: (String) -> Bool) -> Bool {
        if let desktop {
            if let pid = desktop.pid { return !isAlive(pid) }
            return !isAppRunning(desktop.app.bundleID)
        }
        return agentPID.map { !isAlive($0) } ?? false
    }
}

/// Where a click on a session goes.
public enum JumpTarget: Equatable, Sendable {
    /// Open this URL (the app handling its scheme comes forward on the right conversation).
    case url(URL)
    /// Just bring the app forward.
    case activate(bundleID: String)
}

extension AgentSession {
    /// The jump for a desktop-app session; nil for terminal sessions.
    public var desktopJumpTarget: JumpTarget? {
        guard let app = terminal.desktop?.app else { return nil }
        if app == .codex, let url = Self.codexThreadURL(sessionID) { return .url(url) }
        return .activate(bundleID: app.bundleID)
    }

    /// `codex://threads/<id>`. Codex's hook `session_id` is the thread id.
    static func codexThreadURL(_ threadID: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !threadID.isEmpty, threadID.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return URL(string: "codex://threads/\(threadID)")
    }
}
