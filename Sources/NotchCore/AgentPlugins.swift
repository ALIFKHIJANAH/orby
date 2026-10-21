import Foundation
import NotchShared

/// Writes and removes the plugin file Orby owns in an agent's own plugin directory, for agents
/// that load JS/TS code instead of running hook commands (OpenCode, Pi, Command Code mods).
/// The file only ever belongs to Orby: one that lacks our header is never overwritten or deleted.
public enum PluginInstaller {
    /// First line of every file Orby writes; contains `HookInstaller.marker`.
    static let header = "// orby-bridge: written by Orby (Settings → Integrations). Edits are overwritten."

    public enum State: Equatable, Sendable {
        case missing, current, outdated
        /// Something else already uses our file name.
        case foreign
    }

    public static func isOurs(_ text: String) -> Bool { text.hasPrefix(header) }

    public static func source(for target: HookTarget) -> String? {
        switch target {
        case .opencode: AgentPluginSource.openCode
        case .pi: AgentPluginSource.pi
        case .commandcode: AgentPluginSource.commandCode
        case .claude, .codex, .antigravity, .qwen: nil
        }
    }

    public static func state(_ target: HookTarget, home: URL = NotchPaths.homeDirectory) -> State {
        guard let url = target.pluginURL(home: home), let expected = source(for: target) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .missing }
        let text = String(decoding: data, as: UTF8.self)
        guard isOurs(text) else { return .foreign }
        return text == expected ? .current : .outdated
    }

    /// Returns the backup of the file it replaced or removed, if any.
    @discardableResult
    public static func apply(
        _ target: HookTarget, install: Bool, home: URL = NotchPaths.homeDirectory,
        backupDir: URL = NotchPaths.backups, now: Date = Date()
    ) throws -> URL? {
        guard let link = target.pluginURL(home: home), let expected = source(for: target) else { return nil }
        let fm = FileManager.default
        let url = link.resolvingSymlinksInPath()
        let existing = try? Data(contentsOf: url)
        if let existing, !isOurs(String(decoding: existing, as: UTF8.self)) { throw HookInstaller.InstallError.foreignPlugin(url) }
        if install, existing == Data(expected.utf8) { return nil }
        guard install || existing != nil else { return nil }
        let saved = try existing.map { try HookInstaller.backup($0, of: url, for: target, in: backupDir, now: now) }
        if install {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(expected.utf8).write(to: url, options: .atomic)
        } else {
            try fm.removeItem(at: url)
        }
        return saved
    }
}

/// The plugin sources. Each turns the agent's own events into the Claude-shaped hook payloads
/// the session engine understands and pipes them through orby-bridge, so the app needs no
/// per-agent socket code. Approvals come back as Claude's PermissionRequest output and are
/// translated into the agent's own reply here.
enum AgentPluginSource {
    /// Spawns the bridge and keeps hook events in order.
    private static func preamble(source: String) -> String {
        PluginInstaller.header + "\n" + #"""
            import { spawn } from "node:child_process"
            import { existsSync } from "node:fs"
            import { homedir } from "node:os"

            const BRIDGE = `${homedir()}/.orby/bin/orby-bridge`

            // Hands one hook payload to Orby. Resolves with the bridge's stdout: the user's decision
            // for a PermissionRequest, "" otherwise or when Orby isn't running. Never rejects.
            function bridge(payload, onSpawn) {
              return new Promise((resolve) => {
                if (!existsSync(BRIDGE)) return resolve("")
                let out = ""
                try {
                  const child = spawn(BRIDGE, ["--source", "SOURCE"], { stdio: ["pipe", "pipe", "ignore"] })
                  child.stdout.on("data", (d) => (out += d))
                  child.on("error", () => resolve(""))
                  child.on("close", () => resolve(out))
                  child.stdin.on("error", () => {})
                  child.stdin.end(JSON.stringify(payload))
                  if (onSpawn) onSpawn(child)
                } catch {
                  resolve("")
                }
              })
            }

            // Events go out one at a time so the notch never sees a tool finish before it starts.
            let tail = Promise.resolve("")
            function post(payload) {
              tail = tail.then(() => bridge(payload))
              return tail
            }

            // A permission request waits for the events before it, then blocks until the user decides.
            async function ask(payload, onSpawn) {
              await tail
              return bridge(payload, onSpawn)
            }

            function decision(out) {
              try {
                return JSON.parse(out).hookSpecificOutput.decision
              } catch {
                return undefined
              }
            }

            """#.replacingOccurrences(of: "\"SOURCE\"", with: "\"\(source)\"")
    }

    /// OpenCode 1.x plugin (`~/.config/opencode/plugins/orby.js`). Permission prompts and questions
    /// are answered through OpenCode's own reply API; the documented `permission.ask` hook is never called.
    static let openCode = preamble(source: "opencode") + #"""
        export const OrbyPlugin = async ({ client, directory, serverUrl }) => {
          const cwds = new Map() // session → its directory
          const parents = new Map() // subagent session → the session that started it
          const busy = new Set() // sessions with a turn in progress
          const calls = new Map() // callID → { tool, args }, to show the real command in a permission prompt
          const waiting = new Map() // request id → bridge blocked on the notch
          const handled = new Set()
          const answered = new Set() // answered in OpenCode, possibly before the notch saw it

          const learn = (info) => {
            if (!info?.id) return
            if (info.directory) cwds.set(info.id, info.directory)
            if (info.parentID) parents.set(info.id, info.parentID)
          }
          const root = (sid) => {
            let s = sid
            for (let i = 0; i < 8 && parents.has(s); i++) s = parents.get(s)
            return s
          }
          // Subagent sessions report into the session that started them, like Claude's subagents.
          const payload = (sid, event, extra = {}) => {
            const top = root(sid)
            const out = { hook_event_name: event, session_id: top, cwd: cwds.get(top) ?? directory, ...extra }
            if (top !== sid) out.agent_id = sid
            return out
          }

          const idle = (sid) => {
            if (!sid || !busy.delete(sid)) return
            post(payload(sid, parents.has(sid) ? "SubagentStop" : "Stop"))
          }

          // The plugin client's SDK generation varies between releases, so try it, then the raw route.
          const respond = async (path, body, viaClient) => {
            try {
              const r = await viaClient()
              if (r && !r.error) return
            } catch {}
            try {
              const r = await client?._client?.post?.({ url: path, body, headers: { "Content-Type": "application/json" } })
              if (r && !r.error) return
            } catch {}
            try {
              await fetch(new URL(path, serverUrl), {
                method: "POST",
                headers: { "Content-Type": "application/json", "x-opencode-directory": encodeURIComponent(directory) },
                body: JSON.stringify(body),
              })
            } catch {}
          }

          // The bridge blocked on the notch for a request; released if OpenCode got its answer first.
          const wait = (id) => (child) => (answered.has(id) ? child.kill() : waiting.set(id, child))
          // Answered in OpenCode itself: release the notch's copy.
          const release = (id) => {
            answered.add(id)
            waiting.get(id)?.kill()
            waiting.delete(id)
          }

          const permission = async (p) => {
            if (!p.id || !p.sessionID || handled.has(p.id)) return
            handled.add(p.id)
            const name = p.permission ?? p.action ?? "permission"
            const call = calls.get(p.tool?.callID ?? p.source?.callID)
            const always = p.always ?? p.save ?? []
            const out = await ask(
              payload(p.sessionID, "PermissionRequest", {
                tool_name: call?.tool ?? name,
                tool_input: call?.args ?? { patterns: p.patterns ?? p.resources ?? [], ...(p.metadata ?? {}) },
                // Lets the notch offer "Always allow", answered with OpenCode's "always".
                permission_suggestions: always.length
                  ? [{ type: "addRules", behavior: "allow", destination: "session", rules: always.map((r) => ({ toolName: name, ruleContent: r })) }]
                  : [],
              }),
              wait(p.id),
            )
            waiting.delete(p.id)
            const d = decision(out)
            if (!d || answered.has(p.id)) return
            const reply = d.behavior === "allow" ? (d.updatedPermissions?.length ? "always" : "once") : "reject"
            const body = reply === "reject" && d.message ? { reply, message: d.message } : { reply }
            await respond(`/permission/${p.id}/reply`, body, () => client?.permission?.reply?.({ requestID: p.id, ...body }))
          }

          const question = async (p) => {
            if (!p.id || !p.sessionID || handled.has(p.id)) return
            handled.add(p.id)
            const questions = p.questions ?? []
            const out = await ask(
              payload(p.sessionID, "PermissionRequest", {
                tool_name: "AskUserQuestion",
                tool_input: {
                  questions: questions.map((q) => ({
                    question: q.question,
                    header: q.header,
                    multiSelect: !!q.multiple,
                    options: (q.options ?? []).map((o) => ({ label: o.label, description: o.description })),
                  })),
                },
              }),
              wait(p.id),
            )
            waiting.delete(p.id)
            const d = decision(out)
            if (!d || answered.has(p.id)) return
            if (d.behavior !== "allow") {
              return respond(`/question/${p.id}/reject`, {}, () => client?.question?.reject?.({ requestID: p.id }))
            }
            // Orby answers like Claude: { question: "label, label" }. OpenCode wants labels per question.
            const given = d.updatedInput?.answers ?? {}
            const answers = questions.map((q) => {
              const a = given[q.question]
              if (typeof a !== "string" || !a) return []
              const labels = (q.options ?? []).map((o) => o.label).filter((l) => a === l || a.split(", ").includes(l))
              return labels.length ? labels : [a]
            })
            await respond(`/question/${p.id}/reply`, { answers }, () => client?.question?.reply?.({ requestID: p.id, answers }))
          }

          const onEvent = (event) => {
            const p = event?.properties ?? event?.data ?? {}
            switch (event?.type) {
              case "session.created":
                learn(p.info)
                if (p.info?.id) post(payload(p.info.id, p.info.parentID ? "SubagentStart" : "SessionStart"))
                break
              case "session.updated":
                learn(p.info)
                break
              case "session.status":
                if (p.status?.type === "idle") idle(p.sessionID)
                break
              case "session.idle":
                idle(p.sessionID)
                break
              case "session.error": {
                const sid = p.sessionID
                if (!sid || parents.has(sid) || !busy.delete(sid)) break
                const aborted = p.error?.name === "MessageAbortedError"
                post(payload(sid, aborted ? "Interrupt" : "StopFailure", aborted ? {} : { error: p.error?.data?.message ?? p.error?.name ?? "Error" }))
                break
              }
              case "session.deleted": {
                const sid = p.info?.id ?? p.sessionID
                if (sid && !parents.has(sid)) post(payload(sid, "SessionEnd"))
                cwds.delete(sid)
                parents.delete(sid)
                busy.delete(sid)
                break
              }
              case "permission.asked":
              case "permission.v2.asked":
                // Blocks until the user decides; don't hold up the next event.
                permission(p).catch(() => {})
                break
              case "question.asked":
              case "question.v2.asked":
                question(p).catch(() => {})
                break
              case "permission.replied":
              case "permission.v2.replied":
              case "question.replied":
              case "question.rejected":
              case "question.v2.replied":
              case "question.v2.rejected":
                release(p.requestID ?? p.id)
                break
            }
          }

          return {
            event: async ({ event }) => {
              try {
                onEvent(event)
              } catch {}
            },
            "chat.message": async (input, output) => {
              const sid = input?.sessionID
              if (!sid) return
              busy.add(sid)
              if (parents.has(sid)) return
              const prompt = (output?.parts ?? [])
                .filter((part) => part.type === "text" && !part.synthetic)
                .map((part) => part.text)
                .join("\n")
              const model = input.model?.modelID ?? output?.message?.model?.modelID
              post(payload(sid, "UserPromptSubmit", { prompt, ...(model ? { model } : {}) }))
            },
            "tool.execute.before": async (input, output) => {
              if (!input?.sessionID) return
              calls.set(input.callID, { tool: input.tool, args: output?.args ?? {} })
              busy.add(input.sessionID)
              post(payload(input.sessionID, "PreToolUse", { tool_name: input.tool, tool_input: output?.args ?? {} }))
            },
            "tool.execute.after": async (input) => {
              if (!input?.sessionID) return
              const call = calls.get(input.callID)
              calls.delete(input.callID)
              post(payload(input.sessionID, "PostToolUse", { tool_name: input.tool, tool_input: call?.args }))
            },
          }
        }

        """#

    /// Pi extension (`~/.pi/agent/extensions/orby.ts`). Pi never asks before running a tool, so
    /// there is nothing to approve: status only.
    static let pi = preamble(source: "pi") + #"""
        export default function (pi: any) {
          let busy = false
          let settle: any

          const who = (ctx: any) => {
            try {
              const sid = ctx?.sessionManager?.getSessionId?.()
              return sid ? { session_id: String(sid), cwd: ctx?.cwd ?? process.cwd() } : undefined
            } catch {
              return undefined
            }
          }
          const send = (session: any, event: string, extra: any = {}) => {
            if (session) post({ hook_event_name: event, ...session, ...extra })
          }
          const stop = (session: any) => {
            clearTimeout(settle)
            settle = undefined
            if (!busy) return
            busy = false
            send(session, "Stop")
          }

          pi.on("session_start", (event: any, ctx: any) => {
            // A reload re-registers the same session; it isn't a new one.
            if (event?.reason !== "reload") send(who(ctx), "SessionStart")
          })
          pi.on("before_agent_start", (event: any, ctx: any) => {
            busy = true
            send(who(ctx), "UserPromptSubmit", { prompt: event?.prompt ?? "" })
          })
          pi.on("agent_start", () => {
            clearTimeout(settle)
            busy = true
          })
          pi.on("tool_call", (event: any, ctx: any) => {
            busy = true
            send(who(ctx), "PreToolUse", { tool_name: event?.toolName, tool_input: event?.input ?? {} })
          })
          pi.on("tool_execution_end", (event: any, ctx: any) => {
            send(who(ctx), event?.isError ? "PostToolUseFailure" : "PostToolUse", { tool_name: event?.toolName })
          })
          // agent_end can be followed by an automatic retry; agent_settled (newer Pi) is final.
          pi.on("agent_end", (_event: any, ctx: any) => {
            const session = who(ctx)
            clearTimeout(settle)
            settle = setTimeout(() => stop(session), 1500)
          })
          pi.on("agent_settled", (_event: any, ctx: any) => stop(who(ctx)))
          pi.on("session_shutdown", (_event: any, ctx: any) => {
            clearTimeout(settle)
            busy = false
            send(who(ctx), "SessionEnd")
          })
        }

        """#

    /// Command Code mod (`~/.commandcode/mods/orby.ts`): the prompt, approval and exit events its
    /// settings.json hooks don't have. `onPermissionRequest` holds Command Code's own prompt back
    /// until it returns, so "Answer in Terminal" (no decision) hands the prompt back to it.
    static let commandCode = preamble(source: "commandcode") + #"""
        export default function (cmd: any) {
          let sessionId: string | undefined = process.env.COMMANDCODE_SESSION_ID
          let prompt: string | undefined

          const payload = (event: string, extra: any = {}) => ({
            hook_event_name: event,
            session_id: sessionId,
            cwd: cmd.cwd ?? process.cwd(),
            ...extra,
          })

          // The session id is only handed to mods when a run starts.
          cmd.on?.("run_start", (event: any) => {
            if (event?.sessionId) sessionId = String(event.sessionId)
            if (sessionId) post(payload("UserPromptSubmit", prompt ? { prompt } : {}))
            prompt = undefined
          })

          cmd.hooks({
            transformInput: ({ text }: any) => {
              prompt = text
              return undefined
            },
            onPermissionRequest: async ({ toolName, input, description, isSafetyPrompt }: any) => {
              if (!sessionId) return undefined
              // Command Code ignores "allow" on safety prompts: alert, and leave the answer to its own prompt.
              if (isSafetyPrompt) {
                post(payload("Notification", { notification_type: "permission_prompt", message: description ?? toolName }))
                return undefined
              }
              const d = decision(await ask(payload("PermissionRequest", { tool_name: toolName, tool_input: input ?? {} })))
              return d?.behavior === "allow" || d?.behavior === "deny" ? d.behavior : undefined
            },
            onSessionEnd: ({ reason }: any) => {
              if (reason === "shutdown" && sessionId) post(payload("SessionEnd"))
            },
          })
        }

        """#
}
