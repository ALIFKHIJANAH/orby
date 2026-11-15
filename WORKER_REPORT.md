# Worker report: Gemini CLI and GitHub Copilot CLI

Task `task_e14148a0b17d`, branch `ALIFKHIJANAH/orby-agents-gemini-copilot`.

## What was built

**New agents.** `AgentKind.gemini` ("Gemini CLI") and `AgentKind.copilot` ("Copilot CLI"). Both are also new `HookTarget`s, so they show up in Settings → Integrations automatically. Neither has a bundled logo: `AgentLogos` returns nil and the mascot uses `Theme.symbol` (`sparkles` for Gemini, `eyeglasses` for Copilot) with its own colour.

**Gemini CLI** (`HookTarget.gemini`, `~/.gemini/settings.json`)
- Hooks: `SessionStart`, `SessionEnd`, `BeforeAgent`, `BeforeTool`, `AfterTool`, `AfterAgent`, `Notification`. Each entry is `{"name":"orby","type":"command","command":…,"timeout":5000}`; the timeout is in ms. Tool events get `"matcher":"*"`.
- `GeminiPayload.normalized` maps events as follows: `BeforeAgent`→`UserPromptSubmit`, `BeforeTool`→`PreToolUse`, `AfterTool`→`PostToolUse` (`PostToolUseFailure` when `tool_response.error` is set), `AfterAgent`→`Stop`. A `Notification` with `ToolPermission` becomes `permission_prompt`. MCP tools named through `mcp_context` become `mcp__server__tool`. Tool names go through `ToolAliases`.
- Status only. A `ToolPermission` notification raises an **`external`** request ("Go to terminal"), because Gemini can't be approved from outside.
- The request is built from the last `BeforeTool` call, or from the notification's `details` (`exec` / `edit` / `info` / `mcp`) when those name a different call. A later `AfterTool` for the same tool clears it.
- **JSONC-safe writes.** The new `JSONC` (in `NotchCore/JSONC.swift`) parses comments and trailing commas. It rewrites only the top-level `"hooks"` member and leaves every other byte alone: comments, trailing commas, key order and layout.
- Install followed by uninstall gives back the original file byte for byte. When the file had no `hooks` key, uninstall removes the key again.
- If comments sit *inside* the `"hooks"` value, the install refuses with `InstallError.commentedHooks`. Its message is "…has comments inside "hooks" that Orby would lose, so it was left untouched…", and the file is not modified.
- `status`, `hasLegacy` and `foreignBlockingHooks` read the file through the JSONC parser.
- Detection uses `~/.gemini/tmp`, or `gemini` in `/opt/homebrew/bin` or `/usr/local/bin` (real home only). `~/.gemini` alone isn't enough, because Antigravity creates it too.
- Settings note: Gemini skips all hooks in untrusted folders, so those sessions stay invisible.

**Copilot CLI** (`HookTarget.copilot`, Orby-owned `~/.copilot/hooks/orby.json`, or `$COPILOT_HOME/hooks/orby.json` for the real home)
- `{"version":1,"hooks":{…}}` with PascalCase keys: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `ErrorOccurred`.
- The command passes `--event <Event>`, because Copilot's permission hook input has no `hook_event_name`. The bridge already fills that field in from `--event`. The `|| true` guard keeps every exit at 0; that matters because a non-zero exit from `preToolUse` denies the tool.
- Uninstall deletes the file once no hooks remain in it. A backup is taken before every change, and other files in `hooks/` are left alone.
- `CopilotPayload.normalized` handles both payload shapes: camelCase (`sessionId`, `toolName`, `toolInput` / `toolArgs`, including a JSON-string `toolArgs`) and the snake_case that PascalCase keys produce.
  - `agent_idle` → `idle_prompt`.
  - An `ErrorOccurred` that is not recoverable → `StopFailure`.
  - `server/tool` → `mcp__server__tool`.
- **Approvals are behind a setting that defaults to off.** The setting is `PrefKey.copilotApprovals` ("Answer Copilot CLI prompts from the notch", shown in a Copilot CLI section once the agent is connected). The app copies it into `SessionEngine.copilotApprovals` before every event.
  - **Off:** `PermissionRequest` is renamed `PermissionObserved` and ignored, so the app replies "no opinion" at once and Copilot's own rules and prompt take over. A `permission_prompt` notification then raises an `external` request built from the last `PreToolUse`.
  - **On:** a normal blocking request. The reply uses Copilot's flat format through the new `PermissionDecision.hookOutput(for: .copilot)`: `{"behavior":"allow"}` or `{"behavior":"deny","message","interrupt"}`.

**Shared changes (kept small and additive)**
- `ToolAliases`: added `search_file_content`→Grep, `view`→Read and `create`→Write; arguments `old_str`/`new_str`→`old_string`/`new_string` and `file_text`→`content`.
- `ToolDescriber`: added `list_directory`, `read_many_files`, `write_todos`, `save_memory` (Gemini) and `report_intent`, `store_memory` (Copilot).
- `SessionEngine`:
  - The `permission_prompt` notification adds an external request for `promptsInTerminalOnly` agents (Gemini and Copilot).
  - For those requests only, `PostToolUse` matches on tool name, because the notification may describe the call more loosely than the real input.
- `IslandModel`:
  - `decide` replies in the agent's own format.
  - Reading the terminal menu (`loadExternalMenu`) is now limited to Antigravity sessions, because its menu parser is Antigravity-specific. Gemini and Copilot prompts get "Go to terminal".

## Verification

- `swift build`: passes.
- `swift test`: **211 tests in 52 suites, all pass.** 20 of them are new, in `Tests/NotchCoreTests/GeminiCopilotTests.swift`:
  - JSONC parsing, plus insert-then-remove round trips on 5 fixtures (comments, trailing commas, compact, empty), plus replacement and refusal cases.
  - Gemini install/uninstall against temp homes, using a JSONC fixture whose comments survive both steps; a byte-exact round trip; refusal when `hooks` contains comments; detection when only Antigravity's folders exist.
  - Copilot owned-file install/uninstall against a temp home that also holds a foreign hooks file.
  - Payload → session phase for both agents: start, prompt, tool, terminal prompt, tool finished, stop/error/idle, session end, MCP names, and approvals on/off.
  - The flat Copilot reply format.
  - Tool descriptions for both agents' tool names.

## Payload shapes: verified vs from docs

- **Copilot CLI: checked against the installed 1.0.29 source, not live.** I read the bundled `~/Library/Caches/copilot/pkg/darwin-arm64/1.0.29/app.js` (read-only). It confirms:
  - The config schema: `type` / `command` / `bash` / `timeout` / `timeoutSec`, nested `{matcher, hooks}` groups flattened, and PascalCase keys mapped to camelCase events.
  - PascalCase keys produce snake_case input with `hook_event_name`.
  - The `permissionRequest` input is camelCase with **no event name**: `hookName`, `sessionId`, `cwd`, `toolName`, `toolInput`, `permissionSuggestions`. Its tool names are `bash`, `edit` (`file_path`, `diff`), `server/tool`, `web_fetch` and `store_memory`.
  - The `Notification` input carries `notification_type` (`permission_prompt`, `agent_idle`, …).
  - The permission output is flat `behavior` / `message` / `interrupt`; empty output falls through; exit code 2 means deny.
  - Tool arguments: `view(path)`, `create(path, file_text)`, `edit(path, old_str, new_str)`.
- **Copilot could not be run live.** I tried with a temp `COPILOT_HOME` and a logging hook. The local `GITHUB_TOKEN` is a classic PAT that Copilot rejects, and the `gh` login reports no Copilot access, so no hook fired. The research doc says 1.0.100 sends Claude tool names under PascalCase keys; both cases are handled through the aliases, but that part is from the docs.
- **Gemini CLI: from the docs and research only.** It isn't installed on this Mac (`gemini` is not on PATH). These shapes come from `docs/research/agent-integrations.md` §6 and Gemini's hooks docs, and are **not verified**: event names, `notification_type: "ToolPermission"`, the `details` shape (`type`, `command`, `filePath`, `urls`, `serverName` / `toolName`), `mcp_context`, `tool_response.error`, and the hook entry format with its timeouts in ms.

## Not done / open questions

- Untested against running agents:
  - Does Gemini's `BeforeTool` fire before or after its confirmation prompt? The engine handles both orders.
  - What happens when Copilot's sandbox blocks the Unix socket?
  - Does Copilot's 7200 s `timeoutSec` on `PermissionRequest` fail open to its own prompt? The 1.0.29 code logs and falls through.
- No brand logos were added. LobeHub path data wasn't available offline, so both agents use the SF Symbol fallback.
- Gemini and Copilot transcripts are not parsed. `transcript_path` is passed through, and the Claude reader just finds nothing in it.
- Gemini `PreCompress` and Copilot `PreCompact` are left out, because neither agent has a post-compact event to end the "Compacting" phase.
