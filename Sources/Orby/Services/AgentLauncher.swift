import AppKit
import NotchCore

/// Terminal apps a new agent can be started in.
enum LaunchTerminal: String, CaseIterable, Identifiable {
    case orca, terminal, iterm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orca: "Orca"
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        }
    }

    var bundleID: String {
        switch self {
        case .orca: "com.stablyai.orca"
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        }
    }

    var isInstalled: Bool {
        if self == .orca { return TerminalJumper.orcaCLI(appPath: nil) != nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var available: [LaunchTerminal] { allCases.filter(\.isInstalled) }

    /// The one picked in Settings, else Orca when it's installed, else Terminal.
    static var preferred: LaunchTerminal {
        if let saved = Prefs.defaults.string(forKey: PrefKey.launchTerminal).flatMap(LaunchTerminal.init), saved.isInstalled { return saved }
        return LaunchTerminal.orca.isInstalled ? .orca : .terminal
    }
}

/// Opens a terminal in a folder and starts an agent in it.
enum AgentLauncher {
    /// Blocks on the terminal app: call off the main thread. Returns why it failed, or nil.
    /// Orca needs the worktree holding `folder`; it opens its tab there.
    static func launch(_ agent: AgentKind, folder: String, prompt: String, in terminal: LaunchTerminal, orcaWorktree: OrcaWorktree?) -> String? {
        let command = AgentLaunch.command(agent, prompt: prompt)
        switch terminal {
        case .orca:
            guard let wt = orcaWorktree, let cli = TerminalJumper.orcaCLI(appPath: nil) else { return "Orca doesn't know this folder." }
            let line = folder == wt.path ? command : AgentLaunch.inFolder(folder, command)
            let args = ["terminal", "create", "--worktree", "path:\(wt.path)", "--command", line, "--title", agent.displayName, "--focus", "--json"]
            return TerminalJumper.run(cli, args) == nil ? "Orca couldn't open a terminal. Is it running?" : nil
        case .terminal:
            // `do script` without a target tab opens a new window.
            return osascript(
                """
                tell application id "\(terminal.bundleID)"
                  activate
                  do script "\(TerminalJumper.escape(AgentLaunch.inFolder(folder, command)))"
                end tell
                """)
        case .iterm:
            return osascript(
                """
                tell application id "\(terminal.bundleID)"
                  activate
                  set w to (create window with default profile)
                  tell current session of w to write text "\(TerminalJumper.escape(AgentLaunch.inFolder(folder, command)))"
                end tell
                """)
        }
    }

    private static func osascript(_ source: String) -> String? {
        TerminalJumper.run("/usr/bin/osascript", ["-e", source]) == nil ? "Couldn't open a window. Check Orby's Automation permission in System Settings → Privacy." : nil
    }
}

/// What the launcher has picked so far.
struct LaunchDraft: Equatable {
    var agent: AgentKind = .claude
    var folder = ""
    var terminal: LaunchTerminal = .terminal
    var prompt = ""
}
