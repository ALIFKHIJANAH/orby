# Worker report: Factory Droid and Kimi Code CLI

Task `task_da579707ec6a`, branch `ALIFKHIJANAH/orby-agents-droid-kimi`.

## What was built

- **`AgentKind.droid` ("Factory Droid") and `AgentKind.kimi` ("Kimi Code")**, plus matching `HookTarget` cases. Both show up in Settings → Integrations automatically, because that list iterates `HookTarget.allCases`. Each also has a setup note in `Integrations.swift`.
- **Droid** (`~/.factory/hooks.json`):
  - The file is the event map itself, with no `"hooks"` wrapper. `HookInstaller` wraps it in memory, so install, uninstall, status and legacy detection all reuse the existing JSON code.
  - If `hooks.json` doesn't exist and `~/.factory/settings.json` already has a `hooks` key, Orby writes into `settings.json` instead. Droid ignores `settings.json` hooks once `hooks.json` exists, so creating `hooks.json` would have silently disabled the user's hooks.
  - Events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SubagentStop`, `PreCompact`. All have a 10 s timeout, and none blocks; there is no `PreToolUse` gating.
  - A `Notification`/`permission_prompt` uses the existing engine path: phase `needsApproval`, approval cue, reveal. `idle_prompt` (which Droid also sends on cancel) moves the session to `waitingInput`.
- **Kimi** (`~/.kimi-code/config.toml`, or `$KIMI_CODE_HOME/config.toml` for the real home only):
  - New `TOMLHookBlock` (NotchCore) writes one `[[hooks]]` table per event between two marker comments, appended at the end of the file. It never parses or re-serialises the user's TOML.
    - Uninstall removes exactly what install added. If the file had no final newline, the end marker records that Orby added one, so removal takes it back. Result: the rest of the file stays byte-identical, including comments, CRLF line endings and other `[[hooks]]` tables.
    - It refuses, leaving the file untouched, when: the file defines `hooks` some other way (`hooks = …`, `hooks.x = …` or `[hooks]`); the block's end marker is missing; or the file doesn't round-trip as UTF-8.
  - Events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionResult`, `Notification`, `Stop`, `Interrupt`, `StopFailure`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`. Tables use only `event`, `command` (TOML literal string) and `timeout = 10`. No `matcher`, which the docs say is optional.
  - **Never blocks:**
    - `NotchShared.observeOnlySources = ["kimi"]` and `expectsReply(source:event:)` make the bridge send the `PermissionRequest` and exit at once. They also set the hook timeout to 10.
    - The engine turns the observed `PermissionRequest` into a `RequestKind.external` pending request (id `observed:<session>:<tool_call_id>`, falling back to the envelope id).
    - `PermissionResult` clears it. It matches by `tool_call_id` when both events carry one, and otherwise clears all of the session's external requests.
  - `IslandModel.loadExternalMenu` now only runs for Antigravity sessions, so a Kimi prompt card offers "Go to terminal" and never types into Kimi's screen using Antigravity's menu parser.
- **Tool names** (`ToolAliases`, `ToolDescriber`, `TaskProgress`):
  - Droid: `Execute`→Bash, `Create`→Write, `ApplyPatch`→apply_patch, `FetchUrl`→WebFetch, `AskUser`→AskUserQuestion, `old_str`/`new_str`→`old_string`/`new_string`, and a new `LS` description.
  - Kimi: `FetchURL`→WebFetch, `TodoList`→TodoWrite (its items use `title`), and `path`→`file_path` for Read/Write/Edit. `ToolAliases.normalized` now renames arguments even when the tool name is already Claude's.
- App glue: Theme colour and SF Symbol for each agent. There are no brand logo paths; `AgentLogos` returns nil, so the symbol is shown.

## Verified

- `swift build` passes and `swift test` passes: **207 tests (191 existing + 16 new in `Tests/NotchCoreTests/DroidKimiTests.swift`)**.
- Install/uninstall round trips, all in temp homes:
  - Kimi TOML stays byte-identical after uninstall. The fixtures cover no final newline, CRLF, comments, another tool's `[[hooks]]`, an empty or missing file, and a file ending inside a table.
  - Install is idempotent, the backup equals the original bytes, and a partial block reads as `.partial`.
  - Conflicting, broken or non-UTF-8 files are refused and left untouched.
  - Droid `hooks.json` has no wrapper, other hooks are kept, and the `settings.json` fallback works.
- Payload → phase mapping for both agents, and tool descriptions for both agents' tool names.

## Not verified live (from docs only)

Neither `droid` nor `kimi` is installed on this Mac (`~/.factory` and `~/.kimi-code` don't exist), so nothing was tested against a running agent. Everything below comes from https://docs.factory.com/reference/hooks-reference, https://moonshotai.github.io/kimi-code/en/customization/hooks.md, …/configuration/config-files.md, …/reference/tools.md and `runHook.ts`:

- **Kimi:**
  - The payload fields of `PermissionRequest`/`PermissionResult` are undocumented. That includes whether they carry `tool_call_id`, `tool_name` and `tool_input`, and how approve/deny is expressed. The engine therefore doesn't depend on any of them.
  - `Notification`'s type field name is undocumented, so Kimi notifications are ignored for now.
  - The docs and source suggest `$HOME` expands in `command` (it is spawned with `shell: true`) and that omitting `matcher` matches everything. Neither was run.
- **Droid:**
  - The argument names for Edit (`old_str`/`new_str`), ApplyPatch, LS, FetchUrl and AskUser are guesses; only `Create {file_path, content}` and `Execute {command}` are documented. Unknown names fall back to generic descriptions.
  - Whether Droid's transcript works with `TranscriptReader` is unknown.
  - Hooks running through a shell is implied by the docs, not stated.
- Bridge behaviour for `--source kimi` was covered by unit tests of `expectsReply`, not by running the binary. Running it against the user's live Orby socket would have injected a fake session.
- No graphify update: this worktree has no `docs/graphify-out`.
