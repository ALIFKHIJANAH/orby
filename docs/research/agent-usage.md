# Agent usage data: tokens and plan limits for Orby's Usage pane

Researched on 2026-10-21 for Orca task `task_662ac10242de`. It covers the Usage pane's two sections, **PLAN LIMITS** and **TOKENS LAST 7 DAYS**.

- **Sources:** official docs, each agent's own source pinned to a tag, strings in the binaries installed on this Mac, and community parsers (ccusage, tokscale, CodexBar) as supporting evidence.
- **Local inspection:** OpenCode 1.18.35, Antigravity CLI (`agy`), Gemini CLI 0.63.0, Claude Code and Codex 0.159.3. All of it was read-only: SQLite files were APFS-cloned (`cp -c`) into a scratch directory before being opened, and nothing was written to agent directories. No local data was sent anywhere.
- **Not installed here:** Qwen Code, Command Code, Pi and Cursor. Their findings come from source and docs only.
- **Markers:** **UNVERIFIED** means no official source or local check backs the claim. **UNVERIFIED-official** means community sources agree but the vendor doesn't document it.

## How Orby works today (baseline)

- `UsageIndex.refresh` (`Sources/NotchCore/Usage.swift`) walks `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/**/*.jsonl` modified in the last 30 days.
- It re-parses a file only when its `(mtime, size)` changes (`FileState`). A changed file is re-parsed **in full**.
- Claude limits are an opt-in `GET https://api.anthropic.com/api/oauth/usage` using the Claude Code OAuth token from the Keychain (`UsageService.fetchClaudeLimits`). Codex limits come from `rate_limits` in the rollout's `token_count` events.

## Summary

| Agent | Token source (local) | Limits source | Local? | Effort | Recommendation |
|---|---|---|---|---|---|
| **Claude Code** | `~/.claude/projects/**/*.jsonl`, `message.usage` | (a) **statusline stdin `rate_limits`** (official, local); (b) OAuth `/api/oauth/usage` (opt-in network) | Tokens yes; limits yes via statusline | S | Keep. **Fix dedupe** (keep max usage per `message.id`). Later, read `rate_limits` from a statusline relay so limits work without network |
| **Codex** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, `token_count` events | `rate_limits` in the same events (local) | Yes / yes | S | Keep. **Fix dedupe** (skip events whose `total_token_usage` didn't change) |
| **OpenCode** | SQLite `~/.local/share/opencode/opencode.db`, `message.data.tokens` | OpenCode Go `GET opencode.ai/zen/go/v1/usage` (opt-in network, API key). Provider headers are stored only on failed requests | Tokens yes; limits no | M | **Add tokens** (read-only SQLite, watermark on `time_updated`). Skip limits for now |
| **Antigravity CLI** (`agy`) | `~/.gemini/antigravity-cli/conversations/<id>.db` (SQLite plus protobuf blobs) | (a) **statusline stdin `quota` map** (official, local); (b) `agy -p /usage --output-format json`; (c) localhost language-server RPC (community) | Tokens yes (undocumented proto); limits yes via statusline | M | **Add tokens** (small protobuf varint reader). Limits via a statusline relay (same plumbing as Claude) |
| **Antigravity app/IDE** | `~/.gemini/antigravity{,-ide}/conversations/` holds new `.db` files (readable, same schema) and old `.pb` files (**encrypted**) | Same quota as the CLI (shared Google account) | Partial | M (shared with CLI) | Read the `.db` files with the CLI parser; ignore `.pb` |
| **Gemini CLI** | `~/.gemini/tmp/<project>/chats/session-*.jsonl`, `tokens` on `type:"gemini"` | `cloudcode-pa…/v1internal:retrieveUserQuota` (network; consumer Google login is dead since 2026-06-18) | Tokens yes; limits no | S | Tokens only, if Orby adds a Gemini `AgentKind` (it has none today). No limits |
| **Qwen Code** | `~/.qwen/projects/<slug>/chats/<sessionId>.jsonl`, `usageMetadata` | None (free OAuth tier ended 2026-04-15; paid plan only in a web console) | Tokens yes; limits no | S | **Add tokens**. No limits |
| **Command Code** | `~/.commandcode/projects/<slug>/<sessionId>.jsonl`, entry-level `usage` | `api.commandcode.ai/alpha/...` (opt-in network, API key) | Tokens yes; limits no | S | **Add tokens**. Limits later, as opt-in |
| **Pi** | `~/.pi/agent/sessions/--<cwd>--/<ts>_<id>.jsonl`, `message.usage` | None stored | Tokens yes; limits no | S | **Add tokens** (dedupe by entry `id` across forked files) |
| **Cursor** (IDE + `agent`) | **None.** `state.vscdb` bubbles carry `tokenCount {0,0}`; CLI transcripts have no usage | Unofficial cursor.com dashboard APIs (network, session JWT from `state.vscdb` or Keychain) | No / no | L | **Skip tokens** (estimates only). Limits only as a later opt-in, with a strong privacy warning |

Effort: **S** is a new line parser behind the existing `UsageIndex`. **M** needs a new reader (SQLite or protobuf). **L** is network plus credential handling.

### Bugs found in Orby's current counting

1. **Claude: first-seen dedupe undercounts output.** Claude writes one line per content block and repeats `usage` on each, and `output_tokens` grows during streaming. `UsageIndex` keeps the **first** line per `message.id`.
   - On this Mac: 11,475 usage lines collapse to 5,224 message ids. 307 of those ids have differing usage across their lines, for example `output_tokens` of 8 on one line and 4,966 on another.
   - Keeping the max instead of the first raises output tokens by **4.4%**. The all-token total, which is dominated by cache reads, changes by only 0.025%.
   - ccusage keeps the non-sidechain entry, then the largest total, keyed on `message.id + requestId` (https://github.com/ryoppippi/ccusage/blob/main/rust/adapters/claude/src/lib.rs).
   - Fix: store per-id entries, then keep the one with the max `output_tokens`. Cross-file duplicates also happen (3 locally), so it is the global `seen` set that must keep the max, not each file.
2. **Codex: duplicate `token_count` events are double-counted.** Codex sometimes emits a `token_count` whose `info.total_token_usage` equals the previous event's (2 of 130 events on this Mac). Orby adds `last_token_usage.total_tokens` both times.
   - ccusage uses `last_token_usage` only when `total_token_usage` changed, and falls back to `total − previousTotal` (https://github.com/ryoppippi/ccusage/blob/main/rust/adapters/codex/src/parser.rs).
   - Newer rollouts also have `token_usage_record` items with a `response_id`, which give a natural dedupe key (https://github.com/openai/codex/blob/main/codex-rs/history/src/rollout_payload.rs).
3. **Whole-file re-parse.** One local Claude transcript is 52 MB. Every append re-parses all 52 MB on the next 5-minute refresh.
   - All the JSONL formats below are append-only. Gemini has a narrow exception: it rewrites the file only to recover from corruption.
   - So `FileState` can store the byte offset of the last complete line and parse only the tail when `size` grows. Fall back to a full parse when `size` shrinks or the inode changes.
   - This matters more once seven agents are scanned.

### Unit consistency

Orby shows "tokens" as **everything the model processed**: input, output and cache tokens. Each agent splits buckets differently, so each parser must normalise before summing.

| Agent | `input` includes cache read? | `output` includes reasoning? | Sum for "all tokens" |
|---|---|---|---|
| Claude | no | n/a | `input + output + cache_creation + cache_read` (current code) |
| Codex | **yes** (`cached_input_tokens` ⊂ `input_tokens`) | yes (`reasoning_output_tokens` ⊂ `output_tokens`) | `total_tokens` = `input + output` (current code) |
| OpenCode | no | **no** (`reasoning` separate) | `input + output + reasoning + cache.read + cache.write` (= `tokens.total`) |
| Antigravity | no (UNVERIFIED; field 2 and field 5 look disjoint) | field 3 = 9 + 10 (thinking + visible; observed) | `f2 + f3 + f4 + f5` |
| Gemini CLI | **yes** (`cached` ⊂ `input`) | no (`thoughts` separate) | `total` (= `input + output + thoughts + tool`) |
| Qwen | **yes** (genai semantics) | no (`thoughtsTokenCount` separate) | `totalTokenCount` |
| Command Code | no | no reasoning field | `inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens` |
| Pi | no | yes (`reasoning` ⊂ `output`) | `totalTokens` (= `input + output + cacheRead + cacheWrite`) |

---

## 1. Claude Code (re-check)

**Token source.**
- **Path:** `~/.claude/projects/<project-slug>/<sessionId>.jsonl`, plus `…/<sessionId>/subagents/agent-*.jsonl` and legacy flat `agent-*.jsonl` files. `UsageScanner.jsonlFiles` already recurses into all of these.
  - Locally: 126 files, 421 MB, the largest 52 MB, 27 subagent files.
  - ccusage attributes subagent files to their parent session (https://github.com/ryoppippi/ccusage/blob/main/rust/adapters/claude/src/paths.rs).
- **Record:** `type:"assistant"` lines with:
  - `timestamp` (ISO 8601), `sessionId`, `requestId`, `isSidechain`
  - `message.id` (`msg_…`), `message.model`
  - `message.usage{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens, cache_creation{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}, service_tier}`. The nested `cache_creation` and `service_tier` fields are UNVERIFIED in docs but present in transcripts.
- **Dedupe:** key `message.id` (+ `requestId`), keep the line with the largest `output_tokens` (see bug 1).
  - Streaming can leave placeholder `output_tokens` of 1–2 even on the last line (user reports: https://github.com/anthropics/claude-code/issues/27361), so output is a lower bound.

**Limits.**
- **Local, official:** the statusline command receives JSON on stdin with `rate_limits.five_hour.{used_percentage, resets_at}` and `rate_limits.seven_day.{used_percentage, resets_at}` (`resets_at` is epoch seconds). Behind a gateway it also gets `rate_limits.spend_limit.{used_percentage, resets_at, used_usd, limit_usd, period}`. Source: https://code.claude.com/docs/en/statusline.
  - It is present "only for claude.ai Pro and Max subscribers… and only after the first API response". A window disappears once its `resets_at` passes.
  - There are no per-model (Opus/Sonnet) windows.
  - The same payload carries `session_id`, `transcript_path`, `cost.total_cost_usd` and `context_window.current_usage`.
- **Network, opt-in (current):** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`. It needs the `user:profile` scope.
  - Response keys: `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, `extra_usage`, and others, each `{utilization 0–100, resets_at ISO}`.
  - Undocumented, so **UNVERIFIED-official**. Reference: https://github.com/steipete/CodexBar/blob/main/docs/claude.md.
  - Reading the Keychain item `Claude Code-credentials` shows a Keychain prompt the first time. On Claude Code 2.1.x the item may hold only `mcpOAuth` (CodexBar), and `readClaudeCredentials` then falls through to `notSignedIn`.
- **Recommendation: a statusline relay.** This Mac already has a custom `statusLine` (`type: command`) in `~/.claude/settings.json`, so Orby can't simply install its own. A relay would:
  1. store the user's original command;
  2. set `statusLine.command` to `~/.orby/bin/orby-bridge --statusline claude -- <original>`;
  3. have the bridge tee stdin to the socket, then exec the original and pass its stdout through.

  `HookInstaller` would have to restore the original command on uninstall. The data is live only while a session runs, so keep the OAuth fetch as the opt-in fallback for "no session in the last N minutes".

**Cost.** Bounded by transcript size (421 MB total here). Offset-based tail parsing (bug 3) is the main win.

## 2. Codex (re-check)

**Token source.**
- **Path:** `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`, plus `~/.codex/archived_sessions/` (not scanned today; prefer the active copy if both exist). Rollouts may also be `.jsonl.zst` (https://github.com/openai/codex/blob/main/codex-rs/rollout/src/lib.rs), and Orby's `.jsonl` filter skips those.
  - Locally: 14 files, 41 MB, CLI 0.159.3.
- **Record:** `{"timestamp": ISO, "type": "event_msg", "payload": {"type": "token_count", "info": {...}, "rate_limits": {...}}}`.
  - `info.total_token_usage` / `info.last_token_usage` = `{input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_output_tokens, total_tokens}`, plus `info.model_context_window`.
  - `cache_write_input_tokens` is new; it is present in local 0.159.3 logs.
  - Schema: https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs.
  - Model comes from `turn_context` lines; session id from the first `session_meta` line (`payload.session_id` / `payload.id`, observed locally).
- **Dedupe:** see bug 2. `input_tokens` already includes `cached_input_tokens`, so never add them together.

**Limits (local).** `rate_limits` = `{limit_id, limit_name, primary{used_percent, window_minutes, resets_at}, secondary{…}, credits{has_credits, unlimited, balance}, individual_limit, spend_control_reached, plan_type, rate_limit_reached_type}`.
- The primary window is 300 min and the secondary 10080 min, matching `RateLimits.codex`.
- Values are only as fresh as the last turn.
- A fresher source is `codex app-server` JSON-RPC `account/rateLimits/read` (https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/common.rs). It calls `chatgpt.com/backend-api/wham/usage` over the network with `~/.codex/auth.json` or the Keychain item `Codex Auth`, so it must be **opt-in**. Not recommended.

**Cost.** Small. Same tail-parsing advice as Claude.

## 3. OpenCode (inspected locally, v1.18.35)

**Token source.**
- **Path:** `~/.local/share/opencode/opencode.db`. Other release channels use `opencode-<channel>.db`, and `OPENCODE_DB` overrides the path. SQLite in WAL mode with Drizzle migrations (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/core/src/database/database.ts).
  - JSON storage moved to SQLite in v1.2.0, and the JSON migration was removed in v1.16.0. On this Mac `storage/` holds only `migration`, `plugin` and `session_diff`, with no message JSON.
- **Tables** (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/core/src/session/sql.ts):
  - `message(id, session_id, time_created, time_updated, data json)` and `part(id, message_id, session_id, time_created, time_updated, data json)`.
  - `session` also has rollups `tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write, cost`, added and backfilled by migration `20260510033149_session_usage`. Locally a session's rollup exactly equals the sum of its messages (checked on one session: 272,063 / 16,828 / 4,812,672).
  - v2 has `session_message(id, session_id, type, seq, data)`. Locally it holds only `agent-switched` and `model-switched` rows, but v2 assistant rows will carry `tokens` there (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/schema/src/session-message.ts).
  - **`event`** (2.8 GB of the 3.8 GB file) is an event-sourcing log of `message.updated.1`, `message.part.updated.1` and similar. It repeats every update, so **never sum from it**.
- **Assistant `message.data`** (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/schema/src/v1/session.ts). A real row, anonymized, with `path`, `summary` and `system` removed:

  ```json
  {"parentID":"msg_<redacted>","role":"assistant","mode":"build","agent":"build","cost":0,
   "tokens":{"total":110857,"input":464,"output":100,"reasoning":85,"cache":{"write":0,"read":110208}},
   "modelID":"gpt-5.6-sol","providerID":"openai","time":{"created":1792…,"completed":1792…}}
  ```

  `tokens.total` = `input + output + reasoning + cache.read + cache.write` (464 + 100 + 85 + 110208 = 110857). The buckets are disjoint.
- **Step parts:** `part.data` with `type:"step-finish"` carries the same `tokens` per step. In 1.18.x every step is its own assistant message (no message locally has more than one step-finish), but upstream says steps roll up into messages. **Sum messages, not parts.**
- **Dedupe:** `message.id` is the primary key, and rows are updated in place while a turn streams. Upsert by `id` and take the latest `time_updated`. Session id is the `session_id` column; the model is `providerID/modelID`.
  - Subagent sessions are separate `session` rows with `parent_id`. Their messages are already their own rows, so there is no double count.
  - 318 of 29,835 assistant messages lack `tokens.total` (older versions). Compute the sum instead of trusting `total`.
- **Query:**

  ```sql
  -- open with SQLITE_OPEN_READONLY (file:…?mode=ro); never write
  SELECT id, session_id, time_created, time_updated,
         json_extract(data,'$.providerID') AS provider,
         json_extract(data,'$.modelID')    AS model,
         json_extract(data,'$.tokens.input')       AS input,
         json_extract(data,'$.tokens.output')      AS output,
         json_extract(data,'$.tokens.reasoning')   AS reasoning,
         json_extract(data,'$.tokens.cache.read')  AS cache_read,
         json_extract(data,'$.tokens.cache.write') AS cache_write
  FROM message
  WHERE time_updated > :watermark            -- incremental; full rescan when the DB file is replaced
    AND json_extract(data,'$.role') = 'assistant';
  ```

  Bucket by local day of `time_created` (epoch ms). `opencode stats` itself sums `session.tokens_*` filtered by `session.time_updated` (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/opencode/src/cli/cmd/stats.ts), which is too coarse for a per-day chart.

**Limits.**
- **No local quota.** OpenCode stores provider response headers only on **failed** requests, in `message.data.error.data.responseHeaders`. A real 429 from the ChatGPT backend (anonymized) carried the full Codex window state:

  ```
  x-codex-plan-type = plus            x-codex-primary-used-percent = 100   x-codex-primary-window-minutes = 300
  x-codex-primary-reset-at = 1789…    x-codex-secondary-used-percent = 44  x-codex-secondary-window-minutes = 10080
  ```

  This is opportunistic: it appears only after a failure, and only for OpenAI's subscription provider. It isn't a reliable limits source.
- **OpenCode Go subscription:** `GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer <key>` returns `{usage:{rolling|weekly|monthly:{status, percent, resetsAt}}}` (https://github.com/anomalyco/opencode/blob/v1.19.3/packages/console/app/src/routes/zen/go/v1/usage.ts).
  - The key is in `~/.local/share/opencode/auth.json` (mode 600), per tokscale's client (https://github.com/junhoyeo/tokscale/blob/v4.20.0/crates/tokscale-cli/src/commands/usage/opencode_go.rs). OpenCode itself never calls this endpoint, so the auth.json key layout is UNVERIFIED-official.
  - It would be opt-in network, and Orby would read an API key from a file.

**Cost.**
- On this Mac the DB is **3.8 GB**: `event` 2.8 GB, `part` 662 MB, `message` 230 MB, `session` 22 MB.
- The 7-day query above takes **0.54 s** (a full scan of `message`; there's no index on `time_created` alone).
- Run it only when `opencode.db` or `opencode.db-wal` mtime changes, and use the `time_updated` watermark.
- Never copy the DB in production. Open it read-only; WAL readers are safe alongside OpenCode's writer.
- Swift can use the system `SQLite3` module, so no new dependency is needed.

## 4. Antigravity (inspected locally: `agy` CLI and the app/IDE data directories)

**Token source.**
- **CLI:** `~/.gemini/antigravity-cli/conversations/<conversationId>.db`, one SQLite file per conversation (WAL mode, `-wal` up to 18 MB while active). Locally: 19 conversations, 60 MB.
  - Tables: `steps(idx, step_type, status, metadata blob, …)`, `gen_metadata(idx, data blob, size)`, `trajectory_metadata_blob`, `executor_metadata`, `parent_references`.
  - `conversation_summaries.db` beside it holds titles and times, not usage.
- **App:** `~/.gemini/antigravity/conversations/` has 42 `.pb` and 3 `.db` (the `.db` files are newer, same schema).
- **IDE:** `~/.gemini/antigravity-ide/conversations/` has 42 `.pb` files.
  - The `.pb` files are **encrypted** (entropy 7.998 bits/byte, no parseable protobuf), so their usage can't be read.
- The blobs are protobuf with no published `.proto`. The **field map below was decoded locally** and matches ccusage's adapter (https://github.com/ccusage/ccusage/blob/v20.0.37/rust/adapters/antigravity/src/parser.rs), so it is **UNVERIFIED-official** but consistent across both.
  - `steps.metadata` (per step): `1` = created `Timestamp{1: seconds, 2: nanos}`, `9` = usage message, `11` = model enum, `12` = step UUID.
  - Usage message (also at `gen_metadata.data → 1.4` and `→ 1.17.2`):

    | Field | Meaning |
    |---|---|
    | `1` | model enum (e.g. 1319) |
    | `2` | input |
    | `3` | output total |
    | `4` | cache write |
    | `5` | cache read |
    | `6` | API provider enum |
    | `7` | message id (`bot-<uuid>`) |
    | `8` | map (`sessionID`) |
    | `9` / `10` | thinking / visible output |
    | `11` | response id |

  - Field 3 = 9 + 10 in every sample checked (156 = 75 + 81, 160 = 102 + 58). tokscale and ccusage disagree on which of 9/10 is thinking (https://github.com/junhoyeo/tokscale/blob/62ca1eb1677556972ba963fdfa3a41ab23c1eb4b/crates/tokscale-core/src/sessions/antigravity_cli.rs). That doesn't matter for totals.
  - `gen_metadata.data → 1.19` is the model name string (`gemini-3.8-flash-…`).
- **Sample, decoded and anonymized** (`steps.metadata` of one step):

  ```
  1  { 1: 1792534779  2: 570699000 }          # created_at
  9  { 1: 1319  2: 26726  3: 160  6: 24  7: "bot-<uuid>"  9: 102  10: 58  11: "<response-id>" }
  11 1319
  ```

- **Query plus decode:**
  - Run `SELECT idx, metadata FROM steps WHERE metadata IS NOT NULL`.
  - Varint-decode field 9; skip the step if it's absent (701 of 1,437 steps had usage).
  - Sum `f2 + f3 + f4 + f5` and bucket by field 1.
  - For the model name, join `gen_metadata`, or map the enum.
  - A hand-written varint reader of about 50 lines is enough; no SwiftProtobuf is needed.
- **Dedupe:**
  - The same usage appears up to three times per generation (`steps.metadata.9`, `gen_metadata.1.4`, `gen_metadata.1.17.2`; locally `1.4` and `1.17.2` were identical, with the same response id). Read **one** source and dedupe by response id (field 11), then message id (7).
  - ccusage treats `1.17` as retry usages, so with that source, dedupe matters even more.
  - Session id = the `.db` filename stem (= `cascade_id`).
- Locally, `steps` decoding over all 19 CLI DBs found 701 usage records, 0 duplicate response ids, and took **0.08 s**.

**Limits.** All three options below are local for Orby; `agy` itself talks to Google.
- **(a) Statusline stdin, official** (https://antigravity.google/docs/cli/statusline):
  - Configured in `~/.gemini/antigravity-cli/settings.json` as `"statusLine":{"type":"command","command":…}`.
  - The payload includes `session_id`/`conversation_id`, `cwd`, `transcript_path?`, `model{id, display_name}`, `plan_tier` and `email`.
  - It also includes `context_window{total_input_tokens, total_output_tokens, current_usage{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}}`.
  - Quota comes as **`quota: { "<bucket-id>": {remaining_fraction, reset_time, reset_in_seconds?} }`**. The only documented key is `gemini-weekly`; others are UNVERIFIED.
  - The local binary confirms this: `types.StatusLineData` with `map[string]types.StatusLineQuotaBucket`.
  - Orby needs only the same statusline relay as Claude. The local `settings.json` has no `statusLine` yet, so installing one is simpler here.
- **(b) Headless:** `agy -p "/usage" --output-format json`.
  - The binary's changelog strings confirm `-p "/usage"`, `/quota` and `/credits` emit records, with UTC timestamps for piped or JSON output.
  - The `/usage` JSON shape is undocumented (UNVERIFIED). CodexBar uses it (https://github.com/steipete/CodexBar/blob/v0.78.0/docs/antigravity.md).
  - It spawns `agy`, which makes a network call to Google with the user's own Antigravity login, so treat it as **opt-in**.
- **(c) Local language server, community only, UNVERIFIED-official:**
  - The IDE/app runs a `language_server` with `--csrf_token` and `--extension_server_port` in its argv.
  - `POST https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` (or `GetUserStatus`) with `X-Codeium-Csrf-Token` returns `groups[].buckets[].remaining.remainingFraction` or `clientModelConfigs[].quotaInfo{remainingFraction, resetTime}`.
  - Sources: https://github.com/Henrik-3/AntigravityQuota/blob/542e0845a4eb10707c91e69ba24977de24674d53/src/core/quota_manager.ts and CodexBar.
  - The `agy` binary contains the same RPC names (`GetUserStatus`, `RetrieveUserQuotaSummaryResponse`, `/v1internal:retrieveUserQuotaSummary`, `QuotaInfo`).
  - This means reading another process's argv and calling a self-signed localhost endpoint, which is brittle (agy ≥1.2.2 returns 401 without CSRF). Not recommended.
- **Plan policy** (https://antigravity.google/docs/plans): Ultra quota refreshes every 5 h; Pro every 5 h until a weekly cap; free users weekly. Per-model numbers aren't published.
- On this Mac the CLI log shows "You are not logged into Antigravity", so no live quota could be observed.

**Cost.** Small: 60 MB across about 20 files, decoded in 80 ms. Cache per file on `(mtime, size)` of both `<id>.db` and `<id>.db-wal`, because the main file's mtime may not change while the WAL grows.

## 5. Gemini CLI (v0.63.0 installed, no local chats; source v0.65.0)

**Token source.**
- **Path:** `~/.gemini/tmp/<projectShortId>/chats/session-<YYYY-MM-DDTHH-MM>-<first8(sessionId)>.jsonl`. Subagents write to `chats/<parentSessionId>/<sessionId>.jsonl`.
  - The directory name used to be a sha256 hash; it is now a slug from `~/.gemini/projects.json` (https://github.com/google-gemini/gemini-cli/blob/v0.65.0/packages/core/src/config/storage.ts).
  - Legacy `session-*.json` whole-file JSON is migrated to `.jsonl` when a session is resumed.
- **Write pattern:** append-only (`appendRecord` uses `fs.appendFileSync`; confirmed in the local 0.63.0 bundle).
  - The first line is metadata `{sessionId, projectHash, startTime, lastUpdated, kind?}`.
  - Control lines `{$set}`, `{$patch:{id, updates, removeIds, orderIds}}` and `{$rewindTo:id}` follow.
  - The file is rewritten whole only when it is corrupt.
- **Record:** `type:"gemini"` messages carry `id`, `timestamp` (ISO), `model` and `tokens{input, output, cached, thoughts, tool, total}`. These map from `promptTokenCount`, `candidatesTokenCount`, `cachedContentTokenCount`, `thoughtsTokenCount`, `toolUsePromptTokenCount` and `totalTokenCount` (`recordMessageTokens`, https://github.com/google-gemini/gemini-cli/blob/v0.65.0/packages/core/src/services/chatRecordingService.ts). There is no cache-write field.
- **Dedupe:**
  - `pushMessage` **re-appends the whole message** under the same `id` when tokens arrive, so take the last record per `id`.
  - Respect `$rewindTo` and `removeIds`; ccusage does (https://github.com/ccusage/ccusage/blob/v20.0.37/rust/adapters/gemini/src/parser.rs).
  - Because of rewinds, an offset-based tail parse must keep the per-file id map, not just running sums.

**Limits.**
- **Network only, in memory:** `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` with `{project}` returns `{buckets:[{modelId, remainingFraction, remainingAmount?, resetTime, tokenType?}]}` (https://github.com/google-gemini/gemini-cli/blob/v0.65.0/packages/core/src/code_assist/types.ts).
  - The project id comes from `loadCodeAssist`, and auth is the OAuth token in `~/.gemini/oauth_creds.json`.
  - Gemini CLI caches the result in memory only (`lastRetrievedQuota`), and shows it in `/stats model`.
- **Since 2026-06-18** "Login with Google" no longer works for consumer tiers (Individual, AI Pro, Ultra); Google points them to Antigravity CLI (https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals).
- Published daily request caps: https://github.com/google-gemini/gemini-cli/blob/v0.65.0/docs/resources/quota-and-pricing.md.
- Optional local telemetry (`telemetry.outfile`) writes pretty-printed, not line-delimited, OTel records with `*_token_count` fields. It is off by default and not worth relying on.

**Recommendation.** Orby has no Gemini `AgentKind` (`Models.swift`). Add tokens only if Gemini CLI support is added; skip limits.

## 6. Qwen Code (source v0.25.3; not installed here)

**Token source.**
- **Path:** `~/.qwen/projects/<cwd with non-alphanumerics → '-'>/chats/<sessionId>.jsonl`. `QWEN_HOME` / `QWEN_RUNTIME_DIR` override it (https://github.com/QwenLM/qwen-code/blob/v0.25.3/packages/core/src/config/storage.ts).
- **Write pattern:** append-only, `appendFile` with `flush:true` (https://github.com/QwenLM/qwen-code/blob/v0.25.3/packages/core/src/utils/jsonl-utils.ts). Safe for offset scanning.
- **Record:** `{uuid, parentUuid, sessionId, timestamp (ISO), type, subtype, cwd, version, model, usageMetadata}`. `usageMetadata` is on `type:"assistant"` records (https://github.com/QwenLM/qwen-code/blob/v0.25.3/packages/core/src/services/chatRecordingService.ts), with genai fields `promptTokenCount` (includes cache), `candidatesTokenCount`, `cachedContentTokenCount`, `thoughtsTokenCount` and `totalTokenCount`. There is no cache-write field.
- **Dedupe:** by `uuid`. Skip `type:"system"` / `subtype:"ui_telemetry"` records, which may repeat the same usage (UNVERIFIED inference). ccusage keys on (sessionId, timestamp, model, counts) (https://github.com/ccusage/ccusage/blob/v20.0.37/rust/adapters/qwen/src/parser.rs).

**Limits.**
- The Qwen OAuth free tier (formerly 2,000 requests/day, 60/min) was **discontinued on 2026-04-15** (https://github.com/QwenLM/qwen-code/blob/v0.25.3/docs/users/configuration/auth.md).
- Paid Qwen Cloud plan quotas exist only behind cookie-authenticated web console APIs (CodexBar `docs/qwen-cloud.md`, community).

**Recommendation.** Tokens: S, reuse the JSONL scanner. No limits.

## 7. Command Code (closed source, npm `command-code` 1.86.0; not installed here)

**Token source.**
- **Path:** `~/.commandcode/projects/<slug(cwd)>/<sessionId>.jsonl`. The slug algorithm is UNVERIFIED (minified).
  - Ignore sidecars (`<id>.checkpoints.jsonl`, `.prompts.*`, `.v2.bak`).
- **Format:** Pi-like v3 tree. A header `{type:"session", version:3, id, timestamp, cwd, parentSession?}` is followed by `{type:"message", id, parentId, timestamp, message, usage?, model?, effort?}`.
  - `usage` is at the **entry level** and only on assistant entries: `{inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, cacheWriteTokens1h?, costUsd?}`. The buckets are disjoint and there's no reasoning field.
  - `model` is a `"provider/model"` string.
  - Evidence: strings in the published `dist/cli.mjs` (`toSessionUsage`, `appendMessage`) and tokscale (https://github.com/junhoyeo/tokscale/blob/v4.20.0/crates/tokscale-core/src/sessions/commandcode.rs). **UNVERIFIED-official.**
- **Dedupe:** key `id:timestamp` across forked or cloned files. tokscale counts only the active branch (follow `parentId` from the last entry). For a usage total, all branches arguably count, since abandoned branches were still billed; pick one rule and document it.
- Legacy flat transcripts have no usage.

**Limits.**
- **Network only:** `/usage` calls `https://api.commandcode.ai/alpha/whoami?limits=1`, `/alpha/billing/credits?orgId=` (`monthlyCredits`, `purchasedCredits`, `windowLimits`) and `/alpha/usage/summary`, with a Bearer key from `~/.commandcode/auth.json` or `COMMAND_CODE_API_KEY`. Field names inside `windowLimits` are UNVERIFIED.
- The docs describe a 5-hour rolling window plus a weekly window, measured in credits (https://commandcode.ai/docs/resources/usage-limits).
- Opt-in only, and it means reading an API key file.

## 8. Pi (`@earendil-works/pi-coding-agent` 1.3.0; not installed here, since `~/.pi/agent` has no `sessions/`)

**Token source.**
- **Path:** `~/.pi/agent/sessions/--<cwd, '/' → '-'>--/<ISO-ts>_<sessionId>.jsonl` (overridden by `PI_CODING_AGENT_DIR`). Format reference: https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/docs/session-format.md.
- **Format:** append-only tree. The header is `{type:"session", version:3, id, timestamp, cwd, parentSession?}`. Entries are `{type, id, parentId, timestamp}`.
  - `type:"message"` holds an assistant message with `provider`, `model`, `responseId?` and `usage{input, output, cacheRead, cacheWrite, cacheWrite1h?, reasoning?, totalTokens, cost{…}}` (https://github.com/earendil-works/pi/blob/v1.3.0/packages/ai/src/types.ts).
  - `reasoning` ⊂ `output`, and `input` excludes cache.
  - `type:"usage"` entries (for example cache warming), `compaction` and `branch_summary` can also carry usage (https://github.com/earendil-works/pi/blob/v1.3.0/packages/coding-agent/src/core/usage-totals.ts).
- **Dedupe:** `/fork` and `/clone` copy entries into a new file **keeping the original `id` and `timestamp`**, so dedupe on entry `id` across files. ccusage also skips the replayed parent prefix (https://github.com/ccusage/ccusage/blob/v20.0.37/rust/adapters/pi/src/loader.rs).

**Limits.** None are persisted. Response headers are reachable only at runtime through the `after_provider_response` extension hook. In principle the Orby Pi extension could forward `x-codex-*` / `anthropic-ratelimit-*` headers when Pi runs on a subscription login, but that is speculative (UNVERIFIED) and not recommended now.

## 9. Cursor (IDE + `agent` CLI; not installed here)

**Token source: none usable.**
- **IDE:** `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (`cursorDiskKV` keys `bubbleId:*`, `composerData:*`, `agentKv:*`). Bubbles carry `tokenCount` but it stays `{0,0}`, and `composerData.usageData` is empty. CodeBurn falls back to chars ÷ 4 (https://raw.githubusercontent.com/getagentseal/codeburn/main/docs/providers/cursor.md). UNVERIFIED-official.
- **CLI:** `~/.cursor/projects/<id>/agent-transcripts/*.jsonl` and `~/.cursor/chats/<hash>/<agentId>/store.db` have no usage and no per-row timestamps (https://raw.githubusercontent.com/getagentseal/codeburn/main/docs/providers/cursor-agent.md, https://forum.cursor.com/t/richer-agent-transcripts-lifecycle-data-for-observability-langfuse-stop-hooks/166592).
  - `--output-format json` has no usage either (https://cursor.com/docs/cli/reference/output-format).
- Cursor's hook payloads (see `agent-integrations.md` §5) also carry no token counts.

**Limits.**
- **Network only, unofficial:**
  - `POST https://cursor.com/api/dashboard/get-filtered-usage-events` returns `usageEventsDisplay[].tokenUsage{inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, totalCents}` per event, with `timestamp`, `model` and `conversationId` (https://github.com/pingdotgg/t3code/blob/main/packages/provider-cursor/src/server/accountUsage.ts).
  - `GET /api/usage-summary` and `GET /api/dashboard/v2/usage-status` return `usedCents`, `limitCents` and `resetsAt` (https://github.com/steipete/CodexBar/blob/main/docs/cursor.md).
  - `api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` returns `planUsage{limit, remaining, totalPercentUsed}`, `billingCycleEnd` (https://github.com/lidge-jun/opencodex/blob/main/src/providers/quota/vendor-probes-oauth.ts).
- **Auth:**
  - IDE: the JWT at `ItemTable` key `cursorAuth/accessToken` in `state.vscdb`, sent as the cookie `WorkosCursorSessionToken=<userId>::<jwt>`.
  - CLI: the Keychain item `cursor-access-token` / `cursor-user`, which triggers a Keychain prompt (https://github.com/pingdotgg/t3code/blob/main/packages/provider-cursor/src/server/CursorKeychain.ts).
  - Using these means Orby replays the user's full session credential to an undocumented endpoint. That's a higher privacy and stability risk than Claude's scoped OAuth token.
- **Plans** (https://cursor.com/docs/account/pricing): weekly pools on current plans (dollar amounts unpublished); legacy plans have monthly pools (https://cursor.com/docs/account/pricing/legacy-cursor-plans).

**Recommendation.** Don't show Cursor tokens; estimates would mislead next to real counts. Defer limits. If ever added, use opt-in with explicit wording that Orby will use the Cursor login.

---

## Privacy and opt-in rules applied

| Source | Leaves the Mac? | Credential touched | Prompt |
|---|---|---|---|
| All transcript and DB token reads | No | None | None |
| Claude/Antigravity statusline relay | No (stdin → Unix socket) | None | None. It does edit the agent's settings file, so back it up and restore the original command |
| Codex `rate_limits` in rollouts | No | None | None |
| Claude OAuth usage (current) | **Yes**: api.anthropic.com | Claude Code OAuth token (Keychain) | Keychain prompt; opt-in toggle exists |
| `agy -p /usage` | **Yes**, by agy to Google | agy's own login | None; opt-in |
| Antigravity localhost language server | Not by Orby (the LS may refresh from Google) | CSRF token from another process's argv | None; brittle, not recommended |
| Gemini `retrieveUserQuota` | **Yes**: Google | `~/.gemini/oauth_creds.json` | Opt-in; consumer login is dead |
| OpenCode Go usage | **Yes**: opencode.ai | API key in `auth.json` | Opt-in |
| Command Code `/alpha/*` | **Yes**: api.commandcode.ai | API key in `auth.json` | Opt-in |
| Cursor dashboard APIs | **Yes**: cursor.com | Full session JWT (`state.vscdb` or Keychain) | Keychain prompt for the CLI; opt-in with warning |

## Suggested order

1. Fix Claude max-usage dedupe and Codex duplicate-event dedupe (S, in `Usage.swift`, with tests).
2. Switch `FileState` to offset-based tail parsing, keeping per-file id maps for Gemini/Claude-style rewrites (S–M).
3. Add JSONL parsers for **Qwen, Pi and Command Code** behind `UsageIndex` (S each). They're simple, but none are installed here, so test against fixtures built from the documented shapes.
4. Add the **OpenCode** read-only SQLite reader with a `time_updated` watermark (M).
5. Add the **Antigravity** `.db` + protobuf reader for the CLI and app (M).
6. Add a statusline relay for **Claude and Antigravity** limits, so limits stay local with no network (M; needs `HookInstaller` support for wrapping an existing `statusLine.command`).
7. Optional opt-in network limits: OpenCode Go, Command Code. Defer Cursor and Gemini.
