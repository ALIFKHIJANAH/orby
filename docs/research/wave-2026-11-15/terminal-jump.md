# Worker report: precise jump for Ghostty, Warp, cmux and Zellij

## What changed
- `Sources/NotchCore/TerminalJump.swift` (new): pure builders for jump commands (`zellijArgs`, `cmuxRequests`, `cmuxSocketPath`, `cmuxReplyOK`, `ghosttyScript`), plus `sendLine`, a small Unix-socket client with a 1 s timeout used for cmux.
- `Sources/NotchShared/Protocol.swift`: the bridge now also forwards `ZELLIJ_PANE_ID`, `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID` and `CMUX_SOCKET_PATH`. `ZELLIJ_SESSION_NAME` was already forwarded.
- `Sources/NotchCore/Models.swift`: `TerminalContext` gains `zellijSession`, `zellijPane`, `cmuxWorkspace`, `cmuxSurface` and `cmuxSocket`. The new fields are read from the environment and kept by `merged(over:)`. The change only appends.
- `Sources/Orby/Services/TerminalJumper.swift`: this is thin glue that runs the commands, and the app is still activated afterwards.
  - cmux sets `TERM_PROGRAM=ghostty`, so in a cmux session `TERM_PROGRAM` is no longer mapped to Ghostty.
- `Tests/NotchCoreTests/TerminalJumpTests.swift`: 9 tests. They cover command building from the captured context and env forwarding. The merge test checks the jump ids are kept when a later event lacks them. A round trip through a real Unix socket tests `sendLine`.

## Per terminal

| Terminal | Result | Mechanism | How verified |
|---|---|---|---|
| **Zellij** | Precise (pane) | `zellij --session $ZELLIJ_SESSION_NAME action focus-pane-id terminal_$ZELLIJ_PANE_ID`, then activate the host terminal. The host is known from the `__CFBundleIdentifier`/`TERM_PROGRAM` that the zellij server inherits. | Syntax from the official docs: [CLI actions](https://zellij.dev/documentation/cli-actions) and [CLI recipes](https://zellij.dev/documentation/cli-recipes.html), which document `focus-pane-id` and `--session`. Unit tested. **Not run live**: zellij is not installed here. |
| **cmux** | Precise (surface), **only if the cmux socket accepts Orby** | JSON-RPC over `$CMUX_SOCKET_PATH` (default `/tmp/cmux.sock`): `workspace.select {workspace_id}` then `surface.focus {surface_id, workspace_id}`, then activate the cmux app. | Request format, methods and env vars come from the [cmux API docs](https://cmux.com/docs/api). Unit tested, including a real socket round trip against a fake server. **Not run live**: cmux is not installed here. |
| **Ghostty** | Precise when unambiguous (Ghostty ≥ 1.3), else app-only | AppleScript (`tell application id "com.mitchellh.ghostty"`): find `every terminal whose working directory is <session cwd>`. If exactly one matches, `focus` it, then `activate`. Skipped inside tmux, Zellij or cmux. | API from [Ghostty AppleScript docs](https://ghostty.org/docs/features/applescript) and the [1.3.0 release notes](https://ghostty.org/docs/install/release-notes/1-3-0). The script text is unit tested. **Not compiled or run against Ghostty's dictionary**: Ghostty is not installed here, so I could not run `sdef` or `osacompile`. |
| **Warp** | App-only | none | No API exists. The [URI scheme](https://docs.warp.dev/features/uri-scheme) only opens new windows, tabs and launch configs. Warp has no AppleScript dictionary. Feature request warpdotdev/Warp#8929 ("focus tab") is still open. Warp is not installed, so `sdef` could not be run. |

## Caveats and APIs that were not available
- **cmux socket access**: the default mode, "cmux processes only", rejects clients that were not spawned inside a cmux terminal, and Orby is one of those. The jump is precise only when cmux's socket mode allows external clients. In the docs that is `CMUX_SOCKET_MODE=allowAll` or the "Automation" setting in newer builds. Otherwise the request is refused, Orby stops after the first failed reply, and it activates cmux. The docs don't say whether `surface.focus` switches workspace on its own, so Orby selects the workspace first.
- **Ghostty**:
  - Ghostty exports no per-terminal id to child processes (no `GHOSTTY_SURFACE_ID`), so the only handle is the working directory. That directory comes from OSC 7 shell integration. With two tabs in the same folder, Orby activates the app instead of guessing.
  - AppleScript is a "preview" in 1.3 and the release notes warn of breaking changes in 1.4. On older Ghostty, osascript fails and Orby falls back to activation.
  - Ghostty 1.3 also adds an App Intent that focuses a terminal through Shortcuts. It isn't used because it needs a terminal id we can't learn.
  - The first jump triggers macOS Automation consent for Ghostty, as it already does for iTerm2 and Terminal.
- **Zellij**:
  - No release is named for `focus-pane-id`; on older Zellij the command fails silently and only the terminal is activated.
  - The docs don't say whether focusing a pane in another tab switches tab, so that is unverified.
- **Warp**: no tab enumeration or focus API exists.

## Verification
- `swift build`: passes.
- `swift test`: 200 tests in 47 suites pass, 9 of them new (`TerminalJumpTests`).
- No real agent config files were touched.
