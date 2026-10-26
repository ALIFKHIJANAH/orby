import Foundation
import NotchCore
import NotchShared

/// Reads and types into the exact pane an agent runs in. Used to answer prompts that only
/// the agent's own terminal can take (Antigravity). Exists only when the pane can be
/// addressed precisely; anything vaguer would risk typing into the wrong place.
/// Every method blocks on a subprocess: call off the main thread.
enum TerminalController {
    case orca(cli: String, handle: String)
    case terminalApp(tty: String)
    case iTerm(sessionID: String)
    case tmux(pane: String, socket: String?)

    static func `for`(_ t: TerminalContext) -> TerminalController? {
        if let pane = t.tmuxPane { return .tmux(pane: pane, socket: t.tmuxSocket) }
        if t.orcaTabID != nil || t.orcaPane != nil {
            return TerminalJumper.orcaTerminal(tab: t.orcaTabID, pane: t.orcaPane, appPath: t.appBundlePath)
                .map { .orca(cli: $0.cli, handle: $0.handle) }
        }
        switch t.bundleID {
        case "com.apple.Terminal": return t.tty.map { .terminalApp(tty: $0) }
        case "com.googlecode.iterm2":
            return t.itermSessionID?.split(separator: ":").last.map { .iTerm(sessionID: String($0)) }
        default: return nil
        }
    }

    /// What `for(_:)` can offer for this pane — typing text, and pressing Esc to interrupt — judged
    /// without spawning anything, so views can ask while they render.
    static func reach(_ t: TerminalContext) -> (type: Bool, interrupt: Bool) {
        if t.tmuxPane != nil || t.orcaTabID != nil || t.orcaPane != nil { return (true, true) }
        switch t.bundleID {
        case "com.apple.Terminal": return (t.tty != nil, false)
        case "com.googlecode.iterm2": return (t.itermSessionID != nil, t.itermSessionID != nil)
        default: return (false, false)
        }
    }

    /// `type` on Terminal.app always presses Return after the text (`do script` can't avoid it).
    var appendsReturn: Bool { if case .terminalApp = self { true } else { false } }

    /// What the pane shows right now.
    func readScreen() -> String? {
        switch self {
        case .orca(let cli, let handle):
            return TerminalJumper.run(cli, ["terminal", "read", "--terminal", handle, "--screen"])
        case .terminalApp(let tty):
            // Not `contents of t`: on a loop variable AppleScript dereferences the reference instead
            // of reading the tab. `history` is the scrollback plus the screen; the parser takes the
            // newest menu and rejects answered ones.
            return osascript(terminalTab(tty: tty, body: "return history of t"))
        case .iTerm(let id):
            return osascript(iTermSession(id: id, body: "return text of s"))
        case .tmux(let pane, let socket):
            return tmux(socket, ["capture-pane", "-p", "-t", pane])
        }
    }

    /// Type `text` as keystrokes (no Return, except on Terminal.app).
    @discardableResult
    func type(_ text: String) -> Bool {
        switch self {
        case .orca(let cli, let handle):
            return TerminalJumper.run(cli, ["terminal", "send", "--terminal", handle, "--text", text]) != nil
        case .terminalApp(let tty):
            return osascript(terminalTab(tty: tty, body: "do script \"\(TerminalJumper.escape(text))\" in t")) != nil
        case .iTerm(let id):
            return osascript(iTermSession(id: id, body: "tell s to write text \"\(TerminalJumper.escape(text))\" newline NO")) != nil
        case .tmux(let pane, let socket):
            return tmux(socket, ["send-keys", "-t", pane, "-l", text]) != nil
        }
    }

    @discardableResult
    func pressReturn() -> Bool {
        switch self {
        case .orca(let cli, let handle):
            return TerminalJumper.run(cli, ["terminal", "send", "--terminal", handle, "--text", "", "--enter"]) != nil
        case .terminalApp:
            return true  // `type` already pressed it
        case .iTerm(let id):
            return osascript(iTermSession(id: id, body: "tell s to write text \"\"")) != nil
        case .tmux(let pane, let socket):
            return tmux(socket, ["send-keys", "-t", pane, "Enter"]) != nil
        }
    }

    /// Press Esc, which stops the running turn in Claude Code and Codex without quitting them.
    @discardableResult
    func sendEscape() -> Bool {
        switch self {
        case .orca(let cli, let handle):
            return TerminalJumper.run(cli, ["terminal", "send", "--terminal", handle, "--text", "\u{1b}"]) != nil
        case .terminalApp:
            return false  // `do script` always adds Return, so a lone Esc can't be sent
        case .iTerm(let id):
            return osascript(iTermSession(id: id, body: "tell s to write text (character id 27) newline NO")) != nil
        case .tmux(let pane, let socket):
            return tmux(socket, ["send-keys", "-t", pane, "Escape"]) != nil
        }
    }

    private func osascript(_ source: String) -> String? {
        TerminalJumper.run("/usr/bin/osascript", ["-e", source])
    }

    private func tmux(_ socket: String?, _ args: [String]) -> String? {
        guard let bin = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first(where: FileManager.default.isExecutableFile)
        else { return nil }
        return TerminalJumper.run(bin, (socket.map { ["-S", $0] } ?? []) + args)
    }

    private func terminalTab(tty: String, body: String) -> String {
        """
        tell application id "com.apple.Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(TerminalJumper.escape(tty))" then
                \(body)
                return "ok"
              end if
            end repeat
          end repeat
        end tell
        error "tab not found"
        """
    }

    private func iTermSession(id: String, body: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if unique id of s is "\(TerminalJumper.escape(id))" then
                  \(body)
                  return "ok"
                end if
              end repeat
            end repeat
          end repeat
        end tell
        error "session not found"
        """
    }
}
