# Desktop-app agents: Claude Desktop (Code tab) and Codex Desktop

## What I built
- `Sources/NotchCore/DesktopApps.swift`:
  - `DesktopApp.detect(env:chain:)` picks out a desktop-hosted session. It checks the bridge's process chain first, taking the outermost ancestor inside `Claude.app` or `Codex.app`, so the result is the app's main process and not a helper. If the chain has no match, it falls back to the env: `CLAUDE_CODE_ENTRYPOINT=claude-desktop|claude-desktop-3p`, then `__CFBundleIdentifier`.
  - `TerminalContext.hostIsGone`: desktop sessions follow the app's PID when it is known, and otherwise check whether the app is running. Terminal sessions still follow the agent PID.
  - `AgentSession.desktopJumpTarget`: Codex goes to `codex://threads/<session_id>`, opened with Codex itself. Claude activates Claude.app. A thread id that contains anything other than letters, digits, `-` or `_` falls back to activating the app.
- `TerminalContext.desktop` (new, additive). When it is set, `bundleID` and `appBundlePath` point at the desktop app. This also makes "quiet when terminal focused" and the session's app label work.
- `SessionEngine.prune` gains an `isAppRunning` closure that defaults to "running". IslandModel passes in `NSWorkspace.runningApplications`.
- The bridge now forwards `CLAUDE_CODE_ENTRYPOINT` (added to `terminalEnvKeys`).
- `TerminalJumper.jump` handles desktop sessions before any terminal logic runs.
- Approvals and questions are unchanged. They go through the same hook and socket path; a test confirms that a desktop PermissionRequest becomes a pending approval.

## Verified against the installed apps (read-only, nothing launched)
- `/Applications/Claude.app` is installed: bundle id `com.anthropic.claudefordesktop`, version 5.1231.2, URL scheme `claude`.
- The Code tab runs a bundled CLI at `~/Library/Application Support/Claude/claude-code/<ver>/<hash>/claude.app/Contents/MacOS/claude`. That bundle's id is `com.anthropic.claude-code` and its folder name is lowercase `claude.app`. The old rule "first `.app` in the chain" would have picked this bundle, so detection matches the exact name `Claude.app` (case-sensitive) and takes the outermost match.
- Claude.app's `app.asar` maps Code-tab sessions to `CLAUDE_CODE_ENTRYPOINT` = `claude-desktop` (or `claude-desktop-3p` for third-party deployments), and sets `CLAUDE_CODE_DESKTOP_APP_VERSION`.

## Assumptions (not verified)
- **Codex.app is not installed on this machine.** Its bundle id `com.openai.codex`, the `codex://threads/<id>` scheme, the `Codex.app/Contents/Resources/codex` layout, and "hook `session_id` == thread id" all come from the Open Vibe Island docs and source (docs/research/competitors.md). None of it was checked on a real install.
- I did not observe a live Code-tab process tree, because Claude Desktop wasn't running. Two things are assumed: the Electron helper hop between the CLI and the main `Claude` process, and that hooks inherit `CLAUDE_CODE_ENTRYPOINT` and `__CFBundleIdentifier`. Detection works if either the chain or the env is present.
- If only the env matched (no app PID), liveness relies on `NSWorkspace.runningApplications`. With several copies of the app installed, it would treat any running one as alive.
- Typing an answer into a terminal (TerminalController) is unavailable for desktop sessions. Those paths already fall back to "open it instead", which now activates the app.

## Tests
`swift build` passes. `swift test` runs 206 tests in 49 suites, all passing. 15 of them are new, in `Tests/NotchCoreTests/DesktopAppTests.swift`: detection, liveness, and jump target.
