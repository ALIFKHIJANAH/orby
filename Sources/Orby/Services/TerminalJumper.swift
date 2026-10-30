import AppKit
import NotchCore
import NotchShared

/// Brings a session's terminal tab/pane (or IDE window) to the front.
enum TerminalJumper {
    private static let termProgramBundles: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
        "Hyper": "co.zeit.hyper",
        "vscode": "com.microsoft.VSCode",
        "zed": "dev.zed.Zed",
    ]

    /// IDEs focus the window holding a folder when asked to open it.
    private static let folderFocusedApps: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf", "com.vscodium", "dev.zed.Zed", "com.google.antigravity",
    ]

    static func jump(to session: AgentSession) {
        let t = session.terminal
        let cwd = session.cwd
        DispatchQueue.global(qos: .userInitiated).async {
            var bundleID = t.bundleID ?? t.termProgram.flatMap { termProgramBundles[$0] }
            if t.kittyWindowID != nil, bundleID == nil { bundleID = "net.kovidgoyal.kitty" }

            if let pane = t.tmuxPane {
                let clientApp = selectTmuxPane(pane, socket: t.tmuxSocket)
                // Inside tmux the process chain ends at the tmux server; the client knows the terminal.
                if let clientApp { bundleID = clientApp }
            }
            if t.orcaTabID != nil || t.orcaPane != nil {
                switchOrcaTab(tab: t.orcaTabID, pane: t.orcaPane, appPath: t.appBundlePath)
            }

            switch bundleID {
            case "com.googlecode.iterm2":
                if let id = t.itermSessionID?.split(separator: ":").last {
                    runAppleScript(iTermScript(sessionID: String(id)))
                    return
                }
            case "com.apple.Terminal":
                if let tty = t.tty {
                    runAppleScript(terminalScript(tty: tty))
                    return
                }
            case "net.kovidgoyal.kitty":
                if let id = t.kittyWindowID, let listen = t.kittyListenOn {
                    run("/usr/bin/env", ["kitty", "@", "--to", listen, "focus-window", "--match", "id:\(id)"])
                }
            case "com.github.wez.wezterm":
                if let pane = t.weztermPane { run("/usr/bin/env", ["wezterm", "cli", "activate-pane", "--pane-id", pane]) }
            case let id? where folderFocusedApps.contains(id) && !cwd.isEmpty:
                DispatchQueue.main.async { openFolder(cwd, bundleID: id) }
                return
            default:
                break
            }
            if let bundleID { DispatchQueue.main.async { activate(bundleID: bundleID) } }
        }
    }

    @MainActor
    static func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    @MainActor
    private static func openFolder(_ path: String, bundleID: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: config)
    }

    /// Selects the pane's window + pane; returns the bundle ID of the terminal hosting a tmux client.
    private static func selectTmuxPane(_ pane: String, socket: String?) -> String? {
        guard let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first(where: FileManager.default.isExecutableFile)
        else { return nil }
        let base = socket.map { ["-S", $0] } ?? []
        run(tmux, base + ["select-window", "-t", pane])
        run(tmux, base + ["select-pane", "-t", pane])
        run(tmux, base + ["switch-client", "-t", pane])

        let clients = run(tmux, base + ["list-clients", "-F", "#{client_pid}"]) ?? ""
        for line in clients.split(separator: "\n") {
            guard let pid = Int32(line) else { continue }
            for entry in ProcessTree.chain(from: pid) {
                if let app = entry.path.flatMap(ProcessTree.outermostAppBundle), let id = Bundle(path: app)?.bundleIdentifier {
                    return id
                }
            }
        }
        return nil
    }

    /// Orca hosts many agents in tabs; its CLI can bring one to the front. The terminal list's
    /// JSON shape isn't documented, so look for the entry that mentions this tab/pane and use
    /// its `term_…` handle. On any miss, the caller still activates Orca itself.
    private static func switchOrcaTab(tab: String?, pane: String?, appPath: String?) {
        guard let target = orcaTerminal(tab: tab, pane: pane, appPath: appPath) else { return }
        run(target.cli, ["terminal", "switch", "--terminal", target.handle])
    }

    /// The CLI bundled with the Orca app hosting the agent, else the one in /Applications.
    static func orcaCLI(appPath: String?) -> String? {
        let candidates = [appPath.map { $0 + "/Contents/Resources/bin/orca" }, "/Applications/Orca.app/Contents/Resources/bin/orca"]
        return candidates.compactMap({ $0 }).first(where: FileManager.default.isExecutableFile)
    }

    /// The Orca CLI and the `term_…` handle of the terminal hosting this tab/pane.
    static func orcaTerminal(tab: String?, pane: String?, appPath: String?) -> (cli: String, handle: String)? {
        guard let cli = orcaCLI(appPath: appPath),
            let out = run(cli, ["terminal", "list", "--json"]), let json = try? JSONValue.decode(Data(out.utf8))
        else { return nil }
        let paneID = pane?.split(separator: ":").last.map(String.init)
        let needles = [paneID, tab].compactMap { $0 }.filter { !$0.isEmpty }

        func strings(_ v: JSONValue) -> [String] {
            switch v {
            case .string(let s): [s]
            case .array(let a): a.flatMap(strings)
            case .object(let o): o.values.flatMap(strings)
            default: []
            }
        }
        func handle(in v: JSONValue) -> String? {
            switch v {
            case .object(let o):
                let own = strings(v)
                if needles.contains(where: { n in own.contains { $0.contains(n) } }),
                    let h = ["handle", "terminalHandle", "terminal", "id"].lazy.compactMap({ o[$0]?.string }).first(where: { $0.hasPrefix("term_") })
                {
                    // Prefer the most specific match: a nested object that also matches wins.
                    return o.values.lazy.compactMap(handle).first ?? h
                }
                return o.values.lazy.compactMap(handle).first
            case .array(let a):
                return a.lazy.compactMap(handle).first
            default:
                return nil
            }
        }
        guard !needles.isEmpty, let h = handle(in: json) else { return nil }
        return (cli, h)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func iTermScript(sessionID: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if unique id of s is "\(escape(sessionID))" then
                  select w
                  tell t to select
                  tell s to select
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
          activate
        end tell
        """
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(escape(tty))" then
                set selected tab of w to t
                set index of w to 1
                activate
                return
              end if
            end repeat
          end repeat
          activate
        end tell
        """
    }

    /// osascript keeps AppleScript off the main thread; TCC attributes Automation to this app.
    private static func runAppleScript(_ source: String) {
        run("/usr/bin/osascript", ["-e", source])
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
}
