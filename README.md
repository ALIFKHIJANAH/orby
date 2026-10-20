# Orby

A Dynamic Island for your AI coding agents. Orby lives in the MacBook notch (or a
floating bar on Macs without one) and shows what Claude Code, Codex and Antigravity are doing. You can
approve tool calls, answer questions, review plans and jump back to the right terminal tab
without leaving what you're doing.

Native Swift (AppKit + SwiftUI), ~2 MB, no accounts, nothing leaves your Mac except the
optional Claude plan-limit request.

![sessions](docs/screenshots/expanded-sessions.png)

| Permission | Edit | Question | Plan | Usage |
|---|---|---|---|---|
| ![](docs/screenshots/expanded-permission.png) | ![](docs/screenshots/expanded-edit.png) | ![](docs/screenshots/expanded-question-multi.png) | ![](docs/screenshots/expanded-plan.png) | ![](docs/screenshots/expanded-usage.png) |

## Features

- **Live sessions**: thinking / working / needs you / finished (thinking shows the latest reasoning line when the transcript has it, and the notch orb ponders with a thought bubble), current tool, last reply, context-window %, subagents,
  grouped by project with git branch and worktree.
- **Approvals from the notch**: Allow (⌘Y), Deny (⌘N), Always allow (Claude's own suggested rule),
  or hand it back to the terminal.
- **Questions**: answer `AskUserQuestion` prompts: single or multi-select, several questions, free text.
- **Plan review**: Markdown-rendered plan with Approve, Approve + auto-accept edits, or send feedback.
- **Jump back**: click a session to focus its iTerm2 session, Terminal.app tab (by tty), tmux pane,
  Kitty/WezTerm pane, or the VS Code / Cursor / Windsurf / Zed window holding the project.
- **Sounds**: synthesized 8-bit cues, macOS sounds, or your own folder of sounds; per-event toggles.
- **Usage**: Codex 5h/weekly limits (from local logs), Claude 5h/weekly limits (opt-in), 7-day token
  chart per agent from local transcripts.
- **Polite**: never steals focus, stays quiet when you're already looking at that terminal,
  removes sessions whose process exited.

See [docs/FEATURES.md](docs/FEATURES.md) for a full comparison with Vibe Island and AgentNotch.

## Build & run

Requires macOS 14+ and Xcode 16+ (Swift 6 toolchain).

```bash
scripts/build-app.sh --open     # builds build/Orby.app and launches it
swift test                      # unit + bridge↔socket end-to-end tests
```

Then open **Settings → Integrations** and click **Connect** for Claude Code, Codex and/or Antigravity.
Restart running agent sessions so they load the new hooks.

- Codex asks you to trust new hooks once: run `/hooks` inside Codex and trust Orby.
- Antigravity (app, IDE and CLI) gets an `orby` entry in `~/.gemini/config/hooks.json`.
  It shows live status only; Antigravity keeps its own approval prompts.
- Upgrading from NotchIsland: the first launch moves `~/.notchisland` to `~/.orby`, keeps your
  settings and rewrites the old hooks (backups in `~/.orby/backups/`). Restart running agent sessions.
- If another notch app (e.g. Vibe Island) is also hooked into the same agent, both get every
  permission request. Disable one of them to avoid double prompts.

Render the UI states to PNG without Screen Recording permission:

```bash
.build/debug/Orby --render-previews docs/screenshots
```

## How it works

```
claude / codex / antigravity
  └─ hook (settings.json / hooks.json)
       └─ ~/.orby/bin/orby-bridge --source claude     stdin: hook JSON
            ├─ adds terminal identity: TERM_PROGRAM, ITERM_SESSION_ID, TMUX_PANE, tty, process tree
            └─ newline JSON over ~/.orby/run/app.sock ──► Orby.app
                 PermissionRequest only: the bridge blocks until you decide, then prints
                 {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{…}}}
```

The bridge never breaks the agent: if the app isn't running, or anything fails, it exits 0 with
no output and the agent falls back to its normal terminal prompt. Hook commands are guarded
(`[ -x … ] && exec … || true`), so deleting the app leaves harmless no-ops.

| Path | What |
|---|---|
| `Sources/NotchShared` | wire protocol (`BridgeEnvelope`), `JSONValue`, process-tree helpers |
| `Sources/orby-bridge` | the hook binary |
| `Sources/NotchCore` | session engine, hook installer, socket server, transcript + usage parsing, git info |
| `Sources/Orby` | the app: panel, SwiftUI views, terminal jumper, sounds, hot keys, settings |
| `Tests/NotchCoreTests` | engine, installer, decisions, parsers, real bridge ↔ socket round trips |

Hook config changes are additive: other tools' hooks are preserved, symlinked configs are written
through, invalid JSON is refused, and a timestamped backup goes to `~/.orby/backups/` first.
