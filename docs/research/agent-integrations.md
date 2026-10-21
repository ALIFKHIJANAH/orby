# Agent integrations: how Orby can observe and approve other coding agents

Researched 2026-10-21 for Orby task `task_3c34bc550a87`. Sources are official docs, the agents' own source code (GitHub, pinned to a tag or commit where possible), official changelogs, and a string scan of the locally installed OpenCode 1.18.35 binary. A claim not backed by one of those is marked **UNVERIFIED**. Nothing here has been tested end-to-end against a running agent.

## What Orby expects (current contract)

- Each hook runs `~/.orby/bin/orby-bridge --source <agent>` with the hook JSON on stdin (`Sources/NotchCore/HookInstaller.swift`). The bridge wraps it in a `BridgeEnvelope` (payload, terminal env vars, agent PID, tty, process chain) and writes one JSON line to the app's Unix socket (`Sources/orby-bridge/main.swift`, `Sources/NotchShared/Protocol.swift`).
- Only `PermissionRequest` blocks (`blockingEvents`). For that event the bridge waits for a `BridgeReply` and prints `reply.stdout` verbatim. The reply is always Claude's PermissionRequest shape, `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny",...}}}` (`Sources/NotchCore/Decisions.swift`). No output means "no opinion", and the agent shows its own prompt.
- `SessionEngine` speaks Claude's vocabulary: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse[Failure]`, `PermissionRequest`, `Notification` (`permission_prompt`, `idle_prompt`), `Stop`/`Interrupt`/`StopFailure`, `SessionEnd`, `Subagent*`, `Pre/PostCompact`. It reads `session_id` (also `sessionId` or `conversationId`), `cwd`, `transcript_path`, `model`, `tool_name`, `tool_input`, `permission_suggestions` and `agent_id`.
- **Antigravity precedent.** It is status-only. Its camelCase payload is rewritten into the Claude shape by `AntigravityPayload.normalized`. Its prompts are discovered from its log and shown as `RequestKind.external`, so the notch alerts and jumps to the terminal instead of answering. `antigravityPassthrough` covers an agent that *requires* stdout.
- `ProcessTree.agentProcess` takes the first non-shell ancestor. For the in-process JS/TS plugins proposed below, the bridge's parent *is* the agent (bun/node), so agent PID and tty detection keep working.

The pattern for every new agent is the one Antigravity set: (1) a payload normalizer into the Claude shape, (2) a reply dialect for the agent's decision format, and (3) a config writer (JSON hooks, TOML, or a plugin file dropped into a directory).

## Summary

| Agent | Mechanism | Can Orby approve? | Claude-compatible? | Effort | Recommended |
|---|---|---|---|---|---|
| **Qwen Code** | Hooks in `~/.qwen/settings.json` | **Yes**: `PermissionRequest` with Claude's exact output | **Yes**: events, fields and output all match | **S** | **Yes, first** |
| **OpenCode** (v1 1.19.x / v2 2.x) | JS/TS plugin (two incompatible APIs) | **Yes**: v1 via `permission.asked` + reply API; v2 via `permission` hook/reply | No (plugin translates) | **M** (v1), +M (v2) | **Yes** (installed locally) |
| **Factory Droid** | Hooks in `~/.factory/hooks.json` | Partly: only `PreToolUse` `permissionDecision`, which fires for every tool | **Yes** (no `PermissionRequest`; different tool names) | **S** | **Yes**, status plus `Notification`-based alert |
| **GitHub Copilot CLI** | Hooks in `~/.copilot/hooks/*.json` | **Yes**: `permissionRequest` → flat `{behavior}` | Mostly: PascalCase keys give Claude snake_case fields; output is flat | **M** | **Yes** |
| **Cursor** (IDE + `agent` CLI) | Hooks in `~/.cursor/hooks.json`; **also runs `~/.claude/settings.json` hooks** | No: no "needs approval" event; `preToolUse` would gate every tool | Yes, via its third-party loader | **S** (fix) / M (full) | **Fix double-firing now**; status later |
| **Gemini CLI** | Hooks in `~/.gemini/settings.json` | No: deny/ask only; `allow` doesn't skip its prompt | Partly (`hooks migrate --from-claude`; different event names and output) | **M** | Yes, status-only |
| **Command Code** | Hooks in `~/.commandcode/settings.json` + TS "mods" | **Yes**, via the experimental mod `onPermissionRequest` | Hooks are Claude-shaped (4 events, `PreToolUse` output) | **M** | Yes, after the above |
| **Kimi Code CLI** | `[[hooks]]` in `~/.kimi-code/config.toml` | No: `PermissionRequest` is observe-only; hooks can only deny | Partly (Claude event and field names) | **S–M** (TOML) | Yes, status plus external prompt |
| **Pi** | TS extensions in `~/.pi/agent/extensions/` | N/A: Pi has no permission prompts; Orby could *add* a gate via `tool_call` `{block}` | No | **M** | Later, status-only |
| **Auggie** (Augment) | Hooks in `~/.augment/settings.json` + `toolPermissions` script-policy | Maybe: script-policy allow/deny (**UNVERIFIED** for blocking UX) | Mostly (`conversation_id`, no `cwd`; only `deny` honoured) | **M** | Later |
| **Kiro CLI** | Agent-profile hooks (2.x) / `~/.kiro/hooks/*.json` (V3) | No: deny only (exit 2) | Partly | **M** | Later, V3 only |
| **Cline CLI** (3.x) | Executable files in `~/.cline/hooks/<Event>` | No: `cancel` only; approvals go through its hub/ACP | No | **M** | Later |
| **Amp** | TS plugins in `~/.config/amp/plugins/` | Yes, via `tool.call` → `{action}`, but Amp asks for nothing by default | No | **M–L** | Later |
| **Crush** | Hooks (`PreToolUse` only, "preliminary") | Yes for `PreToolUse` (`allow` skips its prompt), but no lifecycle events | Partly (`event` not `hook_event_name`; parses Claude output) | **S–M** | Wait for PR #3146 |

**No agent was skipped.** Every agent on the list now has some extension mechanism. Kimi CLI (Python, `MoonshotAI/kimi-cli`) is **archived**; this doc covers its replacement, Kimi Code CLI (`MoonshotAI/kimi-code`).

## Cross-cutting findings (read first)

1. **Cursor already runs Orby's Claude hooks.** This is a live bug, not a future feature. The Cursor IDE and `agent` CLI read `~/.claude/settings.json` hooks by default ("Include Third-Party Plugins, Skills, and Other Configs"). Orby therefore receives Cursor sessions labelled `--source claude`, keyed on `conversation_id`, with Cursor tool names (`Shell`, `Write`). Cursor maps neither `PermissionRequest` nor `Notification` from Claude configs, so no approvals are affected, but sessions show up as "Claude Code". Fix: in the bridge or engine, treat a `source == "claude"` payload that carries `cursor_version` as `cursor`. If Orby later installs `~/.cursor/hooks.json` too, drop the duplicate. Sources: https://cursor.com/docs/reference/third-party-hooks.md, https://cursor.com/docs/cli/changelog.md (Jan 2026 entry). Not reproduced locally (**UNVERIFIED** in practice).
2. **Copilot CLI reads repo-level `.claude/settings.json`**, but not `~/.claude`. This matters only if Orby ever writes project-level Claude hooks. https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference
3. **Reply dialects.** `PermissionDecision.hookOutput()` emits only Claude's PermissionRequest shape. The agents above need five shapes:
   - Claude `PermissionRequest` (`decision.behavior`): Claude, Qwen.
   - Claude `PreToolUse` (`permissionDecision`): Droid, Crush, Command Code hooks, Kimi (deny only), Auggie (deny only).
   - Copilot flat: `{"behavior":...}` for `permissionRequest`, `{"permissionDecision":...}` for `preToolUse`.
   - Cursor: `{"permission":"allow"|"deny"}`.
   - Gemini: top-level `{"decision":...}`.

   Plugin-based agents (OpenCode, Pi, Amp, Command Code mods) can keep the Claude shape and translate inside the plugin.
4. **Blocking on `PreToolUse` is a trap.** For Droid, Crush, Cursor, Kimi and Auggie the only gate fires on *every* tool call, including ones the agent would auto-allow. If Orby blocks there, every read waits on the notch. Recommended default: no blocking; status, plus an `external` prompt (the Antigravity pattern) when a `Notification`/`permission_prompt` or `PermissionRequest` observation arrives.
5. **Fail-closed agents.** Copilot denies the tool if a `preToolUse` command hook exits non-zero. Cursor blocks on invalid JSON from a permission hook. Gemini, Qwen and Kiro add stray stdout to model context on some events. The bridge must print exactly nothing or valid JSON for these sources. Today it prints nothing for non-blocking events, which is correct.
6. **Session id field names vary.** `BridgeEnvelope.sessionID` covers `session_id`, `sessionId` and `conversationId`. It also needs `conversation_id` (Cursor, Auggie) and `taskId` (Cline), or per-source normalizers.
7. **JSONC configs.** `~/.gemini/settings.json` and possibly `~/.qwen/settings.json` allow comments. `HookInstaller.apply` already refuses invalid JSON (`InstallError.invalidJSON`), so it fails safe, but it will refuse commented files. Writing them needs a JSONC-preserving editor.
8. **Antigravity may be able to approve.** Its `PreToolUse` accepts `decision: "auto_approve" | "force_ask"` per https://antigravity.google/docs/hooks. That could turn the current status-only integration into an approving one. **UNVERIFIED** in practice.
9. **Prior art on this Mac.** `~/.config/opencode/plugins/` already contains OpenCode plugins from Vibe Island, VibeNotch and Orca. All three use the event-bus pattern recommended below (`permission.asked` → external UI → `POST /permission/{id}/reply`), and Orca's also maps `permission.v2.*` / `session.next.*` events. This confirms the approach works on OpenCode 1.18.x. Their code is proprietary; Orby should write its own.

---

## 1. Qwen Code (`QwenLM/qwen-code`, npm 0.25.3)

- **Mechanism:** command hooks, on by default. They can be disabled with `disableAllHooks`, `--safe-mode` or `--bare`. Types: `command`, `http`, `function`, `prompt`.
- **Config:** the `hooks` key in `~/.qwen/settings.json` (user) and `.qwen/settings.json` (project, trusted folders only); system files also exist. The structure is the same as Claude's (`{"hooks":{"Event":[{"matcher","hooks":[{type,command,timeout,name}]}]}}`). `timeout` is in seconds, default 60; any value ≥1000 is read as ms.
- **Events:** 1:1 with Orby: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SessionEnd`, `Notification` (`permission_prompt`, `idle_prompt`, `auth_success`). Extras: `PostToolUseFailure`, `StopFailure`, `SubagentStart/Stop`, `Pre/PostCompact`, `PermissionDenied`, and others.
- **Approve:** **yes**. `PermissionRequest` output is Claude's: `{"hookSpecificOutput":{"decision":{"behavior":"allow"|"deny","message","updatedInput","updatedPermissions","interrupt"}}}`. Source confirms it fires before the dialog, and only for calls that reach the prompt stage (`coreToolScheduler.ts` ~L4414-4460). Deny always applies. Allow is ignored when interaction is mandatory: interactive tools, a `PreToolUse` `ask`, or the destructive-command guard. Exit 2 blocks.
- **Identity:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`, `agent_id`, `tool_use_id`, `permission_suggestions`. No tty (the bridge's process walk covers it).
- **Claude-compatible:** **yes**. Matchers accept Claude tool names, but payload `tool_name` is Qwen's (`run_shell_command`, `write_file`, …), so `ToolDescriber` needs aliases. Qwen does not read `~/.claude/settings.json`, and needs no migrate command.
- **Orby install:** add `case qwen` to `HookTarget` with `configURL = ~/.qwen/settings.json`, Claude's event list, and the existing Claude writer. Use a blocking timeout around 600 s (the 60 s default would cut off a pending approval; never ≥1000).
  ```json
  {"hooks":{
   "PermissionRequest":[{"hooks":[{"type":"command","name":"orby","timeout":600,"command":"[ -x \"$HOME/.orby/bin/orby-bridge\" ] && exec \"$HOME/.orby/bin/orby-bridge\" --source qwen || true"}]}],
   "SessionStart":[{"hooks":[{"type":"command","name":"orby","timeout":10,"command":"…same… --source qwen …"}]}]
  }}
  ```
  The other events take the same entry.
- **Risks:** ms/seconds timeout ambiguity; non-JSON stdout on `SessionStart`/`UserPromptSubmit` is injected into context (the bridge already prints nothing); in ACP/IDE sessions `ask` becomes deny.
- **Sources:** https://github.com/QwenLM/qwen-code/blob/main/docs/users/features/hooks.md · https://github.com/QwenLM/qwen-code/blob/main/docs/users/configuration/settings.md · https://github.com/QwenLM/qwen-code/blob/82bd240ad0d31fd1d3a83dd803625118019ba35d/packages/core/src/core/coreToolScheduler.ts

## 2. OpenCode (`anomalyco/opencode`, formerly `sst/opencode`)

Two plugin generations are live and **mutually incompatible**:
- **v1** is npm `opencode-ai` 1.19.3. This Mac has 1.18.35 at `~/.opencode/bin/opencode`.
- **v2** is npm `@opencode/cli` 2.1.1, and Homebrew stable is 2.1.0.

"V1 plugin implementations do not run in V2" (https://github.com/anomalyco/opencode/blob/v2.1.1/services/www/src/docs/content/build/plugins/migrate-v1.mdx), and v2 rejects v1 plugins (https://github.com/anomalyco/opencode/issues/56630). The public docs at https://opencode.ai/docs/plugins describe v1 only.

- **Mechanism:** a JS/TS plugin file loaded in-process (Bun). No external hook commands exist.
- **Config:**
  - **v1:** files in `~/.config/opencode/{plugin,plugins}/*.{ts,js}` or `.opencode/{plugin,plugins}/`, walked up from cwd. Both directory names are globbed (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/opencode/src/config/plugin.ts). npm plugins go in `"plugin": [...]` in `opencode.json[c]`. Entry: `export const X: Plugin = async ({client, project, directory, worktree, serverUrl, $}) => hooks`.
  - **v2:** `~/.config/opencode/plugins/`. Config key `"plugins"`. Entry: `export default Plugin.define({ id, setup(ctx) })` from `@opencode/plugin` (https://github.com/anomalyco/opencode/blob/v2.1.1/services/www/src/docs/content/plugins.mdx).
  - **Recommendation:** drop a file into `~/.config/opencode/plugins/`. Don't edit `opencode.jsonc`; on this Mac it holds the user's MCP config and is mode 600.
- **Events → Orby:**

  | Orby | v1 | v2 |
  |---|---|---|
  | SessionStart | event `session.created` | `session.created` |
  | UserPromptSubmit | hook `chat.message` | `ctx.session.hook("prompt")` |
  | PreToolUse / PostToolUse | hooks `tool.execute.before/after` (`{tool, sessionID, callID}`, `args`) | `ctx.tool.hook("execute.before/after")` |
  | PermissionRequest | event `permission.asked` (+ `permission.v2.asked` on 1.18.x, see below) | `ctx.permission.hook("evaluate")` or event `permission.asked` |
  | Stop | `session.status` with `status.type == "idle"` (`session.idle` deprecated but emitted) | `session.idle` / `session.execution.succeeded` |
  | SessionEnd | `session.deleted` (no process-exit event) | `session.deleted` / `setup` cleanup |
  | Notification | none (`session.error`, `question.asked` closest) | `session.error`, `form.created` |

- **Approve:** **yes, but not via the documented hook.**
  - `permission.ask` is still in the plugin types and docs, but is **never invoked**. Upstream says so (https://github.com/anomalyco/opencode/issues/47654, "never invoked since v1.3.0"; https://github.com/anomalyco/opencode/blob/v1.19.3/packages/opencode/src/permission/index.ts). The local 1.18.35 binary agrees: it has `trigger("…")` call sites for `tool.execute.before/after`, `chat.message`, `shell.env` etc., but none for `permission.ask`. That string appears only inside an embedded doc.
  - **Working v1 route:** listen for event `permission.asked` (`{id:"per_…", sessionID, permission, patterns[], metadata, always[], tool?:{messageID, callID}}`). Forward it to the bridge as `PermissionRequest`. Then `POST {serverUrl}/permission/{requestID}/reply` with `{"reply":"once"|"always"|"reject","message"?}`. The SDK equivalent is `client.permission.reply({requestID, reply, message})`. The local binary contains both that route and its SDK method; the `"once","always","reject"` enum is confirmed. The deprecated `POST /session/{id}/permissions/{permissionID}` with `{response}` still exists.
  - **v2 route:** the `ctx.permission.hook("evaluate", e => { e.effect = "allow"|"ask"|"deny" })` is awaited before the prompt is published (https://github.com/anomalyco/opencode/blob/v2.1.1/packages/core/src/permission.ts). Alternatively, use event `permission.asked` + `ctx.permission.reply({sessionID, requestID, reply})`.
  - **Questions:** `question.asked` / `POST /question/{id}/reply` with `{answers}` maps to Orby's AskUserQuestion UI.
- **Identity:** `sessionID` on every event and hook; `cwd` = plugin `directory`/`worktree` or session `info.directory`. No transcript file: messages live in SQLite `~/.local/share/opencode/opencode.db`, and the API is `client.session.messages` (v1) or `ctx.session.context` (v2). No tty API; the bridge's process walk from the plugin's child process finds the opencode process.
- **Claude-compatible:** no. OpenCode reads `CLAUDE.md` and `.claude` skills, not Claude hooks.
- **Minimal v1 plugin (`~/.config/opencode/plugins/orby.js`):**
  ```js
  // orby-bridge marker: lets Orby recognise and update its own file.
  import { spawn } from "node:child_process"
  const BIN = `${process.env.HOME}/.orby/bin/orby-bridge`
  const bridge = (p) => new Promise((res) => {
    const c = spawn(BIN, ["--source", "opencode"], { stdio: ["pipe", "pipe", "ignore"] })
    let out = ""
    c.stdout.on("data", (d) => (out += d)); c.on("close", () => res(out)); c.on("error", () => res(""))
    c.stdin.end(JSON.stringify(p))
  })
  export const Orby = async ({ client, directory }) => {
    const base = (sid, ev, extra = {}) => ({ hook_event_name: ev, session_id: sid, cwd: directory, ...extra })
    return {
      event: async ({ event: e }) => {
        const p = e.properties ?? {}
        if (e.type === "session.created") bridge(base(p.info?.id ?? p.sessionID, "SessionStart"))
        if (e.type === "session.status" && p.status?.type === "idle") bridge(base(p.sessionID, "Stop"))
        if (e.type === "session.deleted") bridge(base(p.info?.id ?? p.sessionID, "SessionEnd"))
        if (e.type === "permission.asked") {
          const out = await bridge(base(p.sessionID, "PermissionRequest",
            { tool_name: p.permission, tool_input: { patterns: p.patterns, ...p.metadata }, agent_id: p.id }))
          const b = JSON.parse(out || "{}")?.hookSpecificOutput?.decision?.behavior
          if (b) await client.permission.reply({ requestID: p.id, reply: b === "allow" ? "once" : "reject" }).catch(() => {})
        }
      },
      "chat.message": async (i) => { bridge(base(i.sessionID, "UserPromptSubmit")) },
      "tool.execute.before": async (i, o) => { bridge(base(i.sessionID, "PreToolUse", { tool_name: i.tool, tool_input: o.args })) },
      "tool.execute.after": async (i) => { bridge(base(i.sessionID, "PostToolUse", { tool_name: i.tool })) },
    }
  }
  ```
  - The `event` hook is dispatched without awaiting, so blocking inside it is fine.
  - Whether the v1 plugin's `client` exposes `permission.reply` or only `postSessionIdPermissionsPermissionId` depends on the bundled SDK version. The 1.18.35 binary contains both; fall back to raw `fetch(serverUrl + "/permission/" + id + "/reply")` (**UNVERIFIED** which one the plugin `client` binds).
  - Fire-and-forget calls must not reject unhandled.
- **Risks:**
  - Two APIs: ship `orby.js` (v1) and an `orby` v2 package, and detect the version with `opencode --version`.
  - First reply wins between the TUI and Orby; a late reply gets `PermissionNotFoundError`, which Orby should treat as "answered elsewhere".
  - A `reject` also rejects every other pending request in that session.
  - Permission names (`bash`, `edit`, `external_directory`, `doom_loop`) differ from tool names (https://opencode.ai/docs/permissions).
  - The `event` hook only receives events for the plugin instance's directory.
  - The 1.18.x binary also emits `permission.v2.asked` (`action`, `resources`) and `session.next.*` events. Handle both v1 and v2 names, as the Orca plugin does.
  - Plugins in both `~/.config/opencode` and a project `.opencode` run twice.
- **Sources:** https://opencode.ai/docs/plugins · https://opencode.ai/docs/server · https://github.com/anomalyco/opencode/blob/v1.19.3/packages/plugin/src/index.ts · https://github.com/anomalyco/opencode/blob/v1.19.3/packages/schema/src/v1/permission.ts · https://github.com/anomalyco/opencode/blob/v1.19.3/packages/opencode/src/server/routes/instance/httpapi/groups/permission.ts · https://github.com/anomalyco/opencode/issues/41325 · local binary scan of `~/.opencode/bin/opencode` 1.18.35.

## 3. Factory Droid (docs moved to docs.factory.com)

- **Mechanism:** command hooks, a near-clone of Claude Code. The changelog notes "Claude hooks format compatibility".
- **Config:** `~/.factory/hooks.json` (user) and `.factory/hooks.json` (project). Without `hooks.json`, Droid reads the `hooks` key in `~/.factory/settings.json`. **`hooks.json` is keyed directly by event name (no `"hooks"` wrapper)**: `{"PreToolUse":[{"matcher","hooks":[{type,command,timeout}]}]}`. Default timeout 60 s; the maximum is undocumented.
- **Events:** `SessionStart` (`startup|resume|clear|compact`), `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification` (`permission_prompt`, `idle_prompt`, …), `Stop`, `SubagentStop`, `PreCompact`, `SessionEnd`. **No `PermissionRequest`.** A user cancel sends `Notification` instead of `Stop`.
- **Approve:** only through `PreToolUse` → `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"|"deny"|"ask",...}}`. `allow` "can bypass the normal permission prompt". Since that fires for every tool, don't block by default. Instead, map `Notification`/`permission_prompt` to a `.needsApproval` phase (`SessionEngine` already does this for Claude) and jump to the terminal.
- **Identity:** `session_id`, `transcript_path` (`~/.factory/projects/…/session.jsonl`), `cwd`, `permission_mode` (`off|spec|auto-low|auto-medium|auto-high`), `hook_event_name`; env `FACTORY_PROJECT_DIR`.
- **Claude-compatible:** **yes** for input and output. Tool names differ (`Execute`, `Read`, `Edit`, `Create`, `ApplyPatch`, `Task`, `FetchUrl`, …), and the transcript format is **UNVERIFIED** for `TranscriptReader`.
- **Orby install:** the Claude writer with the root as the hooks map (no `"hooks"` key) and `--source droid`.
  ```json
  {"SessionStart":[{"hooks":[{"type":"command","command":"… exec \"$HOME/.orby/bin/orby-bridge\" --source droid || true","timeout":10}]}],
   "Notification":[{"hooks":[{"type":"command","command":"… --source droid …","timeout":10}]}]}
  ```
  Add `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop` and `SessionEnd` the same way.
- **Risks:** `droid --no-hooks` disables everything; org-managed settings can override user hooks; `~` expansion in `command` is **UNVERIFIED** (Orby's `$HOME` form is fine because hooks run through a shell, also **UNVERIFIED**).
- **Sources:** https://docs.factory.com/reference/hooks-reference · https://docs.factory.com/harness/hooks.md · https://docs.factory.com/changelog/release-notes.md

## 4. GitHub Copilot CLI (`@github/copilot` 1.0.100)

- **Mechanism:** command hooks (`bash`/`powershell`/`command`/`exec`), plus `http` and `prompt` hooks. `timeoutSec` defaults to 30, and **timeouts fail open**.
- **Config:** `~/.copilot/hooks/*.json` (or `$COPILOT_HOME/hooks/`), or the `hooks` key in `~/.copilot/settings.json`. Repo-level: `.github/hooks/*.json`, `.github/copilot/settings.json`, `.claude/settings.json`. Format: `{"version":1,"hooks":{...}}`; Claude's nested `matcher`/`hooks` groups are accepted since 1.0.66. **Orby should own a separate file, `~/.copilot/hooks/orby.json`**, so no merge is needed.
- **Events:** `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse` (+`postToolUseFailure`), `PermissionRequest` (since 1.0.16), `Stop` (`agentStop`), `SessionEnd`, and `notification` (async; `permission_prompt`, `agent_idle`, `agent_completed`, …). Use **PascalCase keys**: they give snake_case Claude fields (`hook_event_name`, `session_id`, `cwd`, `tool_name`, `tool_input`) and Claude tool names (`Bash`, `Read`, `Edit`). camelCase keys give `sessionId`, `toolName`, `toolArgs`.
- **Approve:** **yes**. `permissionRequest` output is **flat**: `{"behavior":"allow"|"deny","message","interrupt"}`; `{}` falls through. `preToolUse` takes `{"permissionDecision":"allow"|"deny"|"ask"}`, and `allow` suppresses the prompt since 1.0.18. Whether Claude's nested `hookSpecificOutput` is accepted is **UNVERIFIED**, so emit the flat form for `--source copilot`. `allow` cannot approve a sandbox bypass.
- **Caveat:** `permissionRequest` fires **before** Copilot's rules engine and session approvals, i.e. even for calls Copilot would auto-allow. Orby would then prompt for things the user never sees prompts for today. Recommendation: block only when the user turns on an "approve Copilot from the notch" setting; otherwise use `notification`/`permission_prompt` for status.
- **Identity:** `session_id`, `cwd`; `transcriptPath` only on Stop, SubagentStop and PreCompact. The full `permissionRequest` input schema is undocumented (**UNVERIFIED** field names).
- **Minimal config (`~/.copilot/hooks/orby.json`):**
  ```json
  {"version":1,"hooks":{
   "SessionStart":[{"type":"command","bash":"$HOME/.orby/bin/orby-bridge --source copilot","timeoutSec":5}],
   "PermissionRequest":[{"type":"command","bash":"$HOME/.orby/bin/orby-bridge --source copilot","timeoutSec":600}],
   "notification":[{"type":"command","bash":"$HOME/.orby/bin/orby-bridge --source copilot","timeoutSec":5}]}}
  ```
  `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop` and `SessionEnd` follow the same pattern.
- **Risks:** a `preToolUse` hook that exits non-zero **denies the tool**. Keep Orby's `[ -x … ] && exec … || true` guard and always exit 0. The session sandbox may block the Unix socket (**UNVERIFIED**). Config is read at startup.
- **Sources:** https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference · https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks · https://github.com/github/copilot-cli/blob/main/changelog.md (1.0.6, 1.0.16, 1.0.18, 1.0.21, 1.0.66)

## 5. Cursor (IDE and the `agent` CLI, formerly `cursor-agent`)

- **Mechanism:** command/prompt hooks. They run in the CLI too: session/stop hooks since Jan 2026, reliable firing and Claude-format responses since Apr 2026, stdin payloads since May 2026.
- **Config:** `~/.cursor/hooks.json` (commands run from `~/.cursor/`) and `<project>/.cursor/hooks.json`. Format: `{"version":1,"hooks":{"<camelCaseEvent>":[{"command","timeout","matcher","failClosed"}]}}`.
- **Events:** `sessionStart`→SessionStart, `beforeSubmitPrompt`→UserPromptSubmit, `preToolUse`/`postToolUse(Failure)`→Pre/PostToolUse, `stop`→Stop, `sessionEnd`→SessionEnd. Also `afterAgentResponse`, `afterAgentThought`, `beforeShellExecution`, `beforeMCPExecution`, `afterFileEdit`, `subagentStart/Stop`, `preCompact`. **No Notification, no PermissionRequest**, so Orby cannot tell when Cursor waits for approval.
- **Approve:** `preToolUse` returns `{"permission":"allow"|"deny","user_message","agent_message","updated_input"}`; `ask` is "not enforced for preToolUse today". `beforeShellExecution`/`beforeMCPExecution` support `allow|deny|ask`. Exit 2 = deny; invalid JSON blocks. Whether `allow` skips Cursor's own approval UI is **UNVERIFIED**. Since there's no "needs approval" signal, gating would apply to every call. **Not recommended.**
- **Identity:** `conversation_id` (use it as the session id; `session_id` only appears on sessionStart/End), `generation_id`, `model`, `cursor_version`, `workspace_roots[]`, `transcript_path` (may be null), `cwd` on tool events; env `CURSOR_PROJECT_DIR`, `CURSOR_TRANSCRIPT_PATH`. IDE vs CLI is not marked in the payload (**UNVERIFIED**); the process chain (`Cursor.app` vs a terminal) tells them apart.
- **Claude-compatible:** yes, via the third-party loader, which is **already active against Orby's Claude hooks** (see cross-cutting finding 1).
- **Recommendation:** first, relabel `cursor_version` payloads to `cursor` (S). Later, optionally install `~/.cursor/hooks.json` for status, drop the Claude-loader duplicates, and print `{"continue":true}` for `beforeSubmitPrompt` (or nothing, if that is accepted; **UNVERIFIED**).
- **Sources:** https://cursor.com/docs/hooks.md · https://cursor.com/docs/reference/third-party-hooks.md · https://cursor.com/docs/cli/changelog.md

## 6. Gemini CLI (`google-gemini/gemini-cli`, npm 0.64.0)

- **Mechanism:** synchronous command hooks, on by default (`hooksConfig.enabled`). stdout must be only JSON; `timeout` is in **ms** (default 60000).
- **Config:** the `hooks` key in `~/.gemini/settings.json` (JSON with comments), `.gemini/settings.json`, `/etc/gemini-cli/settings.json`. It is **separate from Antigravity's** `~/.gemini/config/hooks.json`; Gemini's source never reads that file, so the two don't collide.
- **Events:** `SessionStart`→SessionStart, `BeforeAgent`→UserPromptSubmit, `BeforeTool`→PreToolUse, `AfterTool`→PostToolUse, `AfterAgent`→Stop, `Notification` (`notification_type:"ToolPermission"`)→Notification/permission_prompt, `SessionEnd`→SessionEnd (best-effort). Ignore `BeforeModel`/`AfterModel` (per chunk). **No PermissionRequest.**
- **Approve:** **no**. `BeforeTool` `deny`/`block` blocks and `ask` forces the TUI prompt, but `allow` does not skip Gemini's policy prompt (`hook-utils.ts`, `scheduler.ts` L683-736). The `Notification` hook "cannot … grant permissions" and is **awaited before the dialog renders** (`confirmation.ts` L153-168). The bridge must return immediately, which it does for non-blocking events. Integrate as status plus an `external` prompt on `ToolPermission`.
- **Identity:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`; env `GEMINI_SESSION_ID`, `GEMINI_PROJECT_DIR`, `GEMINI_CWD`, `CLAUDE_PROJECT_DIR`. Tool names: `run_shell_command`, `write_file`, `replace`, `read_file`, `mcp_<server>_<tool>`.
- **Claude-compatible:** partly. `gemini hooks migrate --from-claude` maps events from `./.claude/settings*.json`, but copies `timeout` unchanged (seconds become ms: a bug). Output is a top-level `decision`, not `hookSpecificOutput`. Payload fields match Claude's, so a normalizer only renames events.
- **Minimal config:** `{"hooks":{"BeforeTool":[{"matcher":"*","hooks":[{"name":"orby","type":"command","command":"$HOME/.orby/bin/orby-bridge --source gemini","timeout":5000}]}], …}}`, with the same entry for each event above and 2000 ms for `Notification`/`SessionEnd`.
- **Risks:**
  - **Folder trust:** in an untrusted folder Gemini skips *all* settings hooks, user-level included (`hookRegistry.ts` L171-186). Sessions in untrusted folders will be invisible.
  - Comment-preserving edits are needed.
  - Printing `decision:"deny"` on `AfterAgent` forces a retry.
- **Sources:** https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/index.md · https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/reference.md · https://github.com/google-gemini/gemini-cli/blob/5534eeac330570eb2d0e71846eb42a8bef346a41/packages/core/src/scheduler/confirmation.ts · …/packages/core/src/hooks/hookRegistry.ts · …/packages/cli/src/commands/hooks/migrate.ts

## 7. Command Code (`commandcode.ai`, npm `command-code` 1.85.0, binary `cmd`)

The maker appears to be Langbase (**UNVERIFIED**; the docs don't say).

- **Mechanism A, hooks:** `~/.commandcode/settings.json` (and `.commandcode/settings[.local].json`), Claude-style `{"hooks":{"PreToolUse":[{"matcher":"shell|write","hooks":[{type,command,timeout}]}]}}`. Timeout default 30 s, max 600 s. Read at startup.
  - **Events:** only `SessionStart`, `PreToolUse`, `PostToolUse` and `Stop`. They are skipped in plan mode.
  - **Input:** Claude field names (`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`, `tool_name`, `tool_input`, `tool_use_id`), with tools named `shell_command`, `read_file`, `write_file`, `edit_file`.
  - **Output:** Claude's **PreToolUse** shape. `allow` does not skip the built-in prompt (shipped bundle: `deriveBlockFromOutput` only acts on `deny`).
- **Mechanism B, Mods (experimental):** TS files in `~/.commandcode/mods/*.ts`, `export default (cmd) => …`, hot-reloaded.
  - `cmd.hooks({ onPermissionRequest({toolName, input, description, isSafetyPrompt}) })` returns `'allow' | 'deny' | undefined`. It fires only where a human would be asked, it is awaited with no timeout (bundle, **UNVERIFIED** in docs), and it holds back the TUI prompt meanwhile. On safety prompts `allow` is ignored.
  - Other mod hooks: `transformInput` (UserPromptSubmit), `onSessionStart/End`, `cmd.on('notice')` (Notification), `cmd.on('run_start'|'run_end', {sessionId})`.
- **Approve:** **yes, via the mod.**
- **Identity:** `session_id`/`COMMANDCODE_SESSION_ID`, `cwd`, `transcript_path` (`~/.commandcode/projects/<cwd-slug>/<session-id>.jsonl`, own format). The session id inside a mod comes from `run_start` (**UNVERIFIED** env availability).
- **Claude-compatible:** the hooks are, minus `PermissionRequest`/`UserPromptSubmit`/`SessionEnd`. `/import claude` does not import hooks.
- **Orby install:** hooks for status (`--source commandcode`, print nothing) plus one mod file for `PermissionRequest`, `UserPromptSubmit` and `SessionEnd`. The mod uses the same spawn-the-bridge helper as the OpenCode plugin and returns `behavior` as `'allow'|'deny'`, or `undefined` for passthrough.
- **Risks:** the Mods API is experimental; project mods need workspace trust; a Claude PermissionRequest reply printed from a hook fails schema validation (it is only logged).
- **Sources:** https://commandcode.ai/docs/hooks · https://commandcode.ai/docs/settings · https://commandcode.ai/docs/mods · https://commandcode.ai/docs/sessions · https://commandcode.ai/docs/import

## 8. Kimi Code CLI (`MoonshotAI/kimi-code`; replaces the archived `MoonshotAI/kimi-cli`)

- **Mechanism:** command hooks, `[[hooks]]` tables in `~/.kimi-code/config.toml` (or `$KIMI_CODE_HOME`), user-level only. Each table has **exactly** `event`, `matcher`, `command`, `timeout` (1–600 s, default 30). **Any extra key makes the whole config fail to load.** Changes apply to new sessions.
- **Events:** `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionResult`, `Stop`, `Interrupt`, `StopFailure`, `Notification`, `SubagentStart/Stop`, `Pre/PostCompact`, `SessionHeartbeat` (60 s), and others. These map almost 1:1, and `Interrupt` is already handled by `SessionEngine`.
- **Approve:** **no**. Only `PreToolUse`, `Stop` and `UserPromptSubmit` can block, and only with `deny`. Any other value is a no-op (`runHook.ts`). `PermissionRequest` is observe-only, so the bridge **must not block on it for `--source kimi`**. Show it as `RequestKind.external` and clear it on `PermissionResult`. Alternatives: `kimi web` exposes `POST /api/v1/sessions/{id}/approvals/{approval_id}` on 127.0.0.1:58627 with a bearer token, but only for sessions it hosts (experimental; TUI reachability **UNVERIFIED**). ACP (`kimi acp`) only works if Orby launches the agent.
- **Identity:** `hook_event_name`, `session_id`, `session_title`, `cwd`, `tool_name`, `tool_input`, `tool_call_id`. Transcript: `~/.kimi-code/sessions/<wd-hash>/<id>/agents/main/wire.jsonl` (not in the payload).
- **Claude-compatible:** event and field names, yes; approval, no.
- **Minimal config:**
  ```toml
  [[hooks]]
  event = "PermissionRequest"
  matcher = ".*"
  command = "$HOME/.orby/bin/orby-bridge --source kimi"
  timeout = 10
  ```
  Repeat for each event. Whether `matcher` may be omitted (and whether `$HOME` expands) is **UNVERIFIED**.
- **Risks:** Orby has no TOML writer, and a malformed table breaks Kimi startup. Write a clearly delimited block with marker comments, and back up the file first, as `HookInstaller.apply` already does. The legacy `~/.kimi` CLI has a different schema.
- **Sources:** https://moonshotai.github.io/kimi-code/en/customization/hooks.md · https://moonshotai.github.io/kimi-code/en/configuration/config-files.md · https://moonshotai.github.io/kimi-code/en/reference/server-api.md · https://github.com/MoonshotAI/kimi-code/blob/main/packages/agent-core-v2/src/features/externalHooks/internal/runHook.ts

## 9. Pi (`earendil-works/pi`, npm `@earendil-works/pi-coding-agent` 1.3.0; formerly `badlogic/pi-mono` / `@mariozechner/pi-coding-agent` ≤0.73.1)

- **Mechanism:** TypeScript extensions loaded with jiti, `export default function (pi: ExtensionAPI)`, from `~/.pi/agent/extensions/` (override with `PI_CODING_AGENT_DIR`) or `.pi/extensions/` (needs project trust).
- **Events:** `session_start`→SessionStart, `input`→UserPromptSubmit, `tool_call`→PreToolUse, `tool_result`/`tool_execution_end`→PostToolUse, `agent_settled`→Stop (`agent_end` can be followed by a retry), `session_shutdown`→SessionEnd. No Notification (closest: `ui_prompt_start`).
- **Approve:** Pi has **no permission prompts by design** ("does not ask for approval before every tool call", `docs/security.md`). `tool_call` can return `{block: true, reason}`, and handlers are awaited without a timeout, so Orby *could* add a gate (see `examples/extensions/permission-gate.ts`). Doing so is new behaviour, so make it opt-in and limit it to `bash`/`edit`/`write`.
- **Identity:** `ctx.sessionManager.getSessionId()`, `.getSessionFile()` (written lazily, may be undefined at start), `ctx.cwd`. Transcript: `~/.pi/agent/sessions/--<cwd>--/<ts>_<uuid>.jsonl`, in Pi's own tree format.
- **Claude-compatible:** no.
- **Minimal extension:** the same spawn-the-bridge helper as OpenCode (`pi.exec` has no stdin option, so use `node:child_process`), with `pi.on("session_start" | "input" | "tool_call" | "tool_result" | "agent_settled" | "session_shutdown", …)`. Each handler builds `{hook_event_name, session_id, cwd, transcript_path}`.
- **Risks:** the package rename means imports differ between 0.x and 1.x (a type-only import, or none, avoids this); parallel tool calls produce several approvals at once; reload rebuilds extension state.
- **Sources:** https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/extensions.md · https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/src/core/extensions/types.ts · https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/security.md · https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/session-format.md

## 10. Auggie (Augment Code CLI, `@augmentcode/auggie` 0.36.0)

- **Mechanism:** Claude-style hooks in `~/.augment/settings.json` (also `.augment/settings[.local].json`, `/etc/augment/settings.json`); `timeout` in **ms**, default 60000. **`command` must be a script path ending in `.sh`** (or `.ps1`/`.cmd`/`.bat`) with a shebang and the executable bit. Orby would install a wrapper `~/.orby/bin/orby-auggie.sh` that execs the bridge with `--source auggie`.
- **Events:** `SessionStart`, `PreToolUse`, `PostToolUse`, `Stop` (`agent_stop_cause`), `SessionEnd`; `PromptSubmit` per the 0.27.0 changelog (name **UNVERIFIED**); `Notification` is in the enum but undocumented.
- **Approve:** hooks can only `deny` (`allow`/`ask` are "future"). Separately, `toolPermissions` with `{"type":"script-policy","script":…}` runs a script per tool call (stdin `{"tool-name","event-type","details":{cwd,command|path|url}}`; exit 0 allow, non-zero deny). Orby *could* block there, but its timeout, and whether it replaces the interactive prompt, are **UNVERIFIED**. If Orby isn't running, the script must exit 0, or every terminal call is denied.
- **Identity:** `conversation_id` (`AUGMENT_CONVERSATION_ID`), `workspace_roots[]` (`AUGMENT_PROJECT_DIR`); no `cwd`, no transcript path.
- **Claude-compatible:** mostly (config shape, `hookSpecificOutput`, exit 2); session id and cwd need normalizing; tool names are `launch-process`, `str-replace-editor`, etc.
- **Sources:** https://docs.augmentcode.com/cli/hooks.md · https://docs.augmentcode.com/cli/permissions.md · https://docs.augmentcode.com/cli/plugins.md · https://www.augmentcode.com/changelog/auggie-cli-0-27-0-release-notes

## 11. Kiro CLI (formerly Amazon Q Developer CLI)

- **Mechanism:** command hooks, with two engines and two layouts.
  - **2.x "Classic":** a `"hooks"` object inside an agent profile `~/.kiro/agents/*.json` (`agentSpawn`, `userPromptSubmit`, `preToolUse`, `postToolUse`, `stop`). It only applies to that agent, so Orby would need its own profile set via `kiro-cli settings chat.defaultAgent`, which is invasive.
  - **V3 (early access, `kiro-cli --v3`):** global `~/.kiro/hooks/*.json` (since 2.13.0), `{"version":"v1","hooks":[{name, trigger, matcher, action:{type:"command",command}, timeout}]}` with PascalCase triggers `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SessionEnd`.
- **Approve:** **no**. Exit 2 on `PreToolUse` blocks (with stderr to the model); there is no allow output. Approvals live in `permissions.yaml` and the interactive prompt. ACP (`kiro-cli acp`) is the only interactive route (**UNVERIFIED**).
- **Identity:** `session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input`, `tool_response`; no transcript or tty. A stdout of `{}` on exit 0 is added to context, so print nothing.
- **Claude-compatible:** partly (field names, exit 2); config layout and casing differ.
- **Recommendation:** V3 only, as one file `~/.kiro/hooks/orby.json` that Orby fully owns. Note that Kiro IDE 1.0 reads the same workspace `.kiro/hooks` schema; global hooks are CLI-only per the docs (**UNVERIFIED** for the IDE).
- **Sources:** https://kiro.dev/docs/hooks/ · https://kiro.dev/docs/hooks/types/ · https://kiro.dev/docs/cli/v3/hooks-migration/ · https://kiro.dev/changelog/cli/2-13/ · https://kiro.dev/docs/reference/exit-codes/ · https://kiro.dev/docs/cli/2x-reference/

## 12. Cline CLI (`cline` 3.0.73, SDK-based)

- **Mechanism:** executable files named after the event in `~/.cline/hooks/` (also `~/Documents/Cline/Hooks/`, `.clinerules/hooks/`, `.cline/hooks/`). JSON in on stdin, JSON out on stdout. The CLI flag `--hooks-dir` / env `CLINE_HOOKS_DIR` sets the directory. Orby would install small shell scripts such as `~/.cline/hooks/PreToolUse`, each execing `orby-bridge --source cline`.
- **Events:** `TaskStart`/`TaskResume`→SessionStart (fired **per turn**), `UserPromptSubmit`, `PreToolUse` (blocking, 120 s), `PostToolUse`, `TaskComplete`/`TaskError`→Stop, `TaskCancel`/`SessionShutdown`→SessionEnd. No PermissionRequest or Notification.
- **Approve:** **no**. Output `{"cancel":true,"errorMessage"}` blocks; `review` is parsed but ignored in current source. Real approvals go through the SDK's `requestToolApproval`, via the hub (WebSocket 127.0.0.1:25463) or `--acp`. The CLI's `--auto-approve` defaults to **true**, so there is often nothing to approve. The old gRPC instance API is gone.
- **Identity:** `taskId`, `sessionContext.rootSessionId`, `workspaceRoots[0]` (no `cwd`), `tool_call:{id,name,input}`; sessions at `~/.cline/data/sessions/<id>/<id>.messages.json`.
- **Claude-compatible:** no (own schema).
- **Sources:** https://docs.cline.bot/customization/hooks.md · https://docs.cline.bot/cli/cli-reference.md · https://docs.cline.bot/sdk/architecture/hub-spoke.md · https://github.com/cline/cline/blob/main/sdk/examples/hooks/README.md · https://github.com/cline/cline/blob/main/sdk/packages/core/src/hooks/hook-file-config.ts

## 13. Amp (Sourcegraph / ampcode.com)

- **Mechanism:** TS/JS plugins, long-lived Bun processes, in `~/.config/amp/plugins/` (and `.amp/plugins/`). The old `amp.permissions` / `"action":"delegate"` setting is **gone** from the current settings reference; "Use a custom plugin to control tool use". The old delegate protocol is **UNVERIFIED and appears removed**. There is no `amp.hooks`.
- **Events:** `session.start`→SessionStart (also fires on switching threads), `agent.start`→UserPromptSubmit, `tool.call`→PreToolUse/PermissionRequest, `tool.result`→PostToolUse, `agent.end`→Stop. No SessionEnd or Notification.
- **Approve:** `tool.call` handler returns `{action:'allow'|'reject-and-continue'|'modify'|'synthesize'|'error'}` and can await Orby. Amp asks for nothing by default, so like Pi this is a gate Orby adds, not one it answers.
- **Identity:** `event.thread.id` (`T-<uuid>`), workspace via `ctx.system.workspaceRoot` (URI); threads are server-side (no transcript file).
- **Risks:** plugins may run on remote executors ("orbs"), where the local socket is unreachable (`ctx.system.executor.kind`); the API changes often; one plugin process serves many threads.
- **Sources:** https://ampcode.com/docs/markdown/customize/plugins · https://ampcode.com/docs/markdown/plugin-api · https://ampcode.com/docs/markdown/tools · https://ampcode.com/docs/markdown/cli/settings

## 14. Crush (`charmbracelet/crush`)

- **Mechanism:** "preliminary" hooks, **`PreToolUse` only** (not in sub-agents). Configured in `~/.config/crush/crush.json` (`"hooks":{"PreToolUse":[{name, matcher, command, timeout}]}`; JSON config now deprecated) or the new `~/.config/crush/crushrc` (`hook add PreToolUse --command … --name orby`).
- **Input:** `{event, session_id, cwd, tool_name, tool_input}`. The field is `event`, **not `hook_event_name`**; env `CRUSH_EVENT`, `CRUSH_SESSION_ID`.
- **Approve:** yes. Native `{"decision":"allow"|"deny"}`, or Claude's `hookSpecificOutput.permissionDecision`; `allow` skips Crush's prompt. But it fires on every tool, **fails open on timeout**, and with no lifecycle events Orby can't show sessions.
- **Recommendation:** wait for PR #3146 (adds `SessionStart`/`SessionEnd`/`PostToolUse`/turn and permission events) and PR #3482 (`hook_event_name`).
- **Sources:** https://github.com/charmbracelet/crush/blob/main/docs/hooks/README.md · https://github.com/charmbracelet/crush/blob/main/internal/hooks/input.go · https://github.com/charmbracelet/crush/pull/3146 · https://github.com/charmbracelet/crush/pull/3482

---

## Recommended implementation order

0. **Cursor relabel (S, bug fix).** Treat `--source claude` payloads containing `cursor_version` as `cursor` (new `AgentKind.cursor`), keyed by `conversation_id`. This stops Cursor sessions from showing as Claude Code today. Confirm first by running `agent` in a terminal with Orby's Claude hooks installed.
1. **Groundwork (S–M).**
   - Turn `HookTarget` into a table of {config path, writer kind (Claude-nested JSON / root-keyed JSON / versioned flat JSON / owned file / TOML block / plugin file), event list, reply dialect, normalizer}.
   - Add `ReplyDialect` to `PermissionDecision.hookOutput()`, and make `blockingEvents` per-source (e.g. `PermissionRequest` blocks for qwen/copilot but never for kimi).
   - Extend `BridgeEnvelope.sessionID` (`conversation_id`, `taskId`).
   - Add `ToolDescriber` aliases for non-Claude tool names (`run_shell_command`, `Execute`, `shell_command`, `Shell`, `bash`, …).
2. **Qwen Code (S).** Full parity with Claude, including approvals, questions and "always allow".
3. **OpenCode v1 plugin (M).** Status + approvals + questions through `permission.asked` / `question.asked` and the reply API. Highest-value non-hook agent, and installed on this Mac. Then **OpenCode v2** (M) once 2.x is the common install.
4. **Factory Droid (S).** Status plus a `Notification`/`permission_prompt` alert; optional opt-in `PreToolUse` gating.
5. **GitHub Copilot CLI (M).** Status by default; approvals behind a setting because `permissionRequest` fires before Copilot's own rules.
6. **Gemini CLI (M).** Status plus a `ToolPermission` alert (`external` request); needs a JSONC-safe writer; document the folder-trust blind spot.
7. **Command Code (M).** Hooks for status plus a mod for approvals (experimental API).
8. **Kimi Code CLI (S–M).** Status plus observe-only `PermissionRequest` → `external`; needs a careful TOML block writer.
9. **Later / opt-in:**
   - Auggie (script-policy approval, once its UX is verified).
   - Kiro V3 (status).
   - Pi and Amp (status; approval gates would be new behaviour).
   - Cline (status; auto-approve default).
   - Crush (after PR #3146 lands).
10. **Side quest.** Test whether Antigravity's `PreToolUse` `decision:"auto_approve"` lets Orby approve Antigravity tools instead of jumping to the terminal.

Before shipping each one, verify against a running agent: the exact payload of the permission event, that "no output" falls through to the agent's own prompt, and the agent's behaviour when the bridge is missing (Orby deleted).
