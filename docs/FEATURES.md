# Feature analysis: Vibe Island vs AgentNotch vs Orby

Sources: vibeisland.app, agentnotch.app (home, /features, /changelog), and the local
`Vibe Island.app` 1.0.53 bundle (Info.plist, bundled resources, localized UI strings,
the hook config it writes). No code was copied from either product.

## How Vibe Island works (from the bundle)

```
agent (claude, codex, …)
  └─ hook in ~/.claude/settings.json / ~/.codex/hooks.json
       └─ ~/.vibe-island/bin/vibe-island-bridge --source claude      (stdin = hook JSON)
            ├─ collects terminal identity: TERM_PROGRAM, ITERM_SESSION_ID, TMUX_PANE,
            │  KITTY_WINDOW_ID, WEZTERM_PANE, process tree, tty, …
            └─ Unix socket ~/.vibe-island/run/vibe-island.sock ──► Vibe Island.app (notch UI)
                 PermissionRequest: bridge blocks (hook timeout 86400s) until the user
                 clicks Allow/Deny, then prints the decision JSON for the agent.
```

* Pure Swift, `LSUIElement` (no Dock icon), Sparkle updates, Sentry crash reports, 11 languages.
* Per-agent plugins/extensions for agents without shell hooks (Pi, OpenClaw, Hermes, Gemini/Antigravity plugins).
* Claude plan limits come from Claude Code's Status Line input (a removable "statusline bridge")
  or from the Claude Code OAuth sign-in; Codex limits from Codex's own data.
* SSH remote: uploads a remote agent binary, reverse-tunnels the socket.

## Feature matrix

✅ built in Orby · ◐ partial · — not yet (roadmap)

| Feature | Vibe Island | AgentNotch | Orby |
|---|---|---|---|
| **Agents** | 30 (Claude Code, Codex, Gemini CLI, Cursor, OpenCode, Droid, Copilot, Kiro, Amp, Qwen, Kimi, DeepSeek, …) | ~12 (Claude Code, Codex, Cursor, Kimi, OpenCode, Cowork, Antigravity, Pi, LM Studio, Hermes, herdr) | ✅ Claude Code, ✅ Codex, ✅ Qwen Code (hooks), ✅ OpenCode 1.x (plugin), ✅ Command Code (hooks + mod), ✅ Pi (extension; status only), ✅ Antigravity (hooks; prompts answered by typing into its terminal), ✅ Cursor (via Claude hooks; status only) |
| Notch panel; floating bar on non-notch / external displays | ✅ | ✅ | ✅ |
| Non-activating overlay (never steals focus) | ✅ | ✅ | ✅ |
| Hover / click to expand, auto-collapse on leave | ✅ | ✅ | ✅ |
| Live status: working / needs you / finished | ✅ | ✅ | ✅ |
| Separate "thinking" state with live reasoning snippet | ✅ ("Thinking: …") | — | ✅ (Claude thinking blocks, Codex reasoning summaries) |
| Antigravity CLI permission prompts | ◐ (status only) | — | ✅ alert, Approve / Always (this chat) / Deny by typing into its terminal (Orca, Terminal, iTerm2, tmux), else jump |
| Animated mascot with per-state expressions | — | ✅ (mascot beside the notch) | ✅ AgentOrb |
| Current tool line (`$ npm test`, `Edit App.swift`) | ✅ | ✅ | ✅ |
| Group by project, branches + git worktrees | ◐ | ✅ | ✅ (reads `.git`, worktrees grouped under main repo) |
| Context-window % per session | ✅ | ✅ | ✅ |
| Subagents | ✅ (count) | — | ✅ each subagent on its parent's row: type, task, current tool, time running (Claude `agent_id` hooks + `subagents/*.meta.json`); Orca orchestration workers nested under the session that dispatched them, titled by task |
| Task checklist / goal progress | ✅ | ✅ | ✅ (Claude `TodoWrite`, Codex `update_plan`; bar + `3/7 · current item` on the session row) |
| **Approve / deny from the notch** | ✅ | ✅ | ✅ (Allow, Deny, Always allow from suggestions, hand back to terminal) |
| Trust a session: auto-allow its safe requests for N min | ? | ? | ✅ ("Allow, and trust this session" on the card, or the row's menu; anything flagged risky, questions and plans still ask; shield badge while trusted) |
| Reply to / stop an agent from the notch | ? | ✅ (Reply) | ✅ reply to a finished or waiting session; Stop sends Esc to a working one (tmux, iTerm2, Orca; Terminal.app reply only) |
| Start a new agent from the notch | — | — | ✅ compose button or ⌥⌘N: agent (Claude, Codex, Antigravity, OpenCode), folder (default, recent, Orca worktrees, any), terminal (Orca tab, Terminal.app or iTerm2 window), optional first message; the new row is highlighted when it arrives |
| Keyboard shortcuts for approvals | ✅ ⌘Y/⌘N + configurable | — | ✅ ⌘Y / ⌘N while a request is open |
| Answer AskUserQuestion (single, multi-select, multiple questions, free text) | ✅ | ✅ (Reply) | ✅ |
| Plan review with Markdown + feedback | ✅ | ✅ (plan ready alert) | ✅ (Approve, Approve + auto-edit, send feedback) |
| Detect "answered in terminal" and clear the card | ✅ | ? | ✅ (bridge EOF + PostToolUse matching) |
| Click to jump to exact tab/pane | ✅ iTerm2, Terminal, Ghostty, Warp, WezTerm, Kitty, tmux, Zellij, IDEs | ✅ Ghostty, iTerm2, Warp, VS Code, Conductor | ✅ iTerm2 (session), Terminal (tty), tmux (pane), Kitty, WezTerm, VS Code/Cursor/Windsurf/Zed (folder window); others: app activation |
| Don't pop up when the agent's terminal is already focused | ✅ | — | ✅ |
| Sounds per event | ✅ 8-bit + sound packs, quiet hours | ✅ 5 sounds, per-event | ✅ synthesized 8-bit, macOS sounds, custom folder; per-event toggles + preview |
| Quiet rules, reminders, context alert | ◐ quiet hours | — | ✅ quiet hours, mute while locked, replay the cue for unanswered requests after 2/5/10 min, cue at 85% context, long-quiet working sessions tint their time |
| Plan usage limits | ✅ Claude, Codex, Kimi, GLM, DeepSeek | ✅ Claude, Codex, Cursor, Kimi, OpenCode Go | ✅ Codex (local logs), ✅ Claude (opt-in, Claude Code sign-in), ✅ Antigravity (opt-in: agy status line relay, or `agy -p /usage`) |
| Usage alerts / pace / early-empty countdown | ✅ threshold alerts | ✅ pace tick, 85% line | ◐ 85% danger line, reset countdown |
| Token history (day/7d/30d, per provider) | ✅ | ✅ | ✅ 7-day chart stacked per agent (Claude, Codex, OpenCode, Antigravity, Qwen, Pi, Command Code); tail-only scan of JSONL, read-only SQLite |
| Menu bar list of agents | — | ✅ | ✅ |
| Zero-config setup | ✅ auto on first launch | ✅ | ◐ one-click Connect per agent (+ optional auto-configure); backups before every change |
| Clean uninstall of hooks | ✅ | ? | ✅ |
| Idle / dead session cleanup | ✅ | ✅ (1/2/5 min) | ✅ dead-PID detection + configurable TTL |
| Launch at login | ✅ | ✅ | ✅ |
| Notch size fine-tuning, panel width | ✅ | — | ✅ |
| Appearance themes (glass, colors, gauges) | ✅ | ✅ | — |
| Multi-display at once | ✅ | ✅ | — (choose built-in or main display) |
| SSH remote servers / Docker | ✅ | — | — |
| iPhone push (Bark), Apple Watch | ✅ | — | — |
| Session switcher shortcut (Alfred-style) | ✅ | — | — |
| Hide sessions by directory / prompt filters | ✅ | — | — |
| AI session naming | ✅ (experimental) | — | — |
| Cloud agents (Cursor) | — | ✅ | — |
| Localization | 11 languages | English | English |
| Auto-update | Sparkle, Homebrew | in-app | — |
| Price | $19.99 one-time | $9.99 one-time | free (yours) |

## Roadmap (ordered by value)

1. More agents (see [research/agent-integrations.md](research/agent-integrations.md)): Factory Droid, GitHub Copilot CLI, Gemini CLI (needs a JSONC-safe writer), Kimi Code CLI (TOML), OpenCode 2.x plugin API, Cursor's own `hooks.json`, Antigravity approvals via `PreToolUse` `auto_approve`.
2. Session filters (hide by directory / first prompt) and a global switcher shortcut.
3. Multi-display, appearance themes, reduce motion.
4. Focus-aware muting; usage threshold alerts.
   Future opt-in plan limits (see [research/agent-usage.md](research/agent-usage.md)), each off by default behind its own toggle:
   OpenCode Go (`opencode.ai/zen/go/v1/usage`, API key from OpenCode's `auth.json`), Command Code
   (`api.commandcode.ai/alpha/...`, API key), Cursor (unofficial dashboard API, full session token).
   Claude limits could also stay local through the same status line relay Antigravity uses
   (`orby-bridge --statusline`, which wraps the user's own `statusLine` command).
   Cursor keeps no token counts on disk and Gemini CLI has no Orby integration yet, so neither
   has a token history.
5. SSH remote: run the bridge on a server and forward the socket with `ssh -R`.
6. Sparkle updates + Developer ID signing / notarization.
