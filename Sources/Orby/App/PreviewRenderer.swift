import AppKit
import NotchCore
import NotchShared
import SwiftUI

/// `Orby --render-previews <dir>` renders each panel state to PNG with fake sessions.
/// Used for visual checks and README screenshots without needing Screen Recording access.
@MainActor
enum PreviewRenderer {
    /// Set while rendering, so views skip input locks and other live-only behaviour.
    static var active = false

    static func run(outputDir: String) {
        active = true
        Prefs.register()
        let dir = URL(fileURLWithPath: outputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = makeFakeRepo()

        let scenarios: [(String, CGFloat, (IslandModel) -> Void)] = [
            ("collapsed-working", 90, { m in working(m, repo); m.collapse() }),
            ("collapsed-attention", 90, { m in working(m, repo); permission(m, repo); m.collapse() }),
            ("collapsed-thinking", 90, { m in working(m, repo); thinking(m); m.collapse() }),
            ("expanded-sessions", 520, { m in working(m, repo); thinking(m); m.expand(.click) }),
            ("expanded-permission", 520, { m in working(m, repo); codexWaiting(m); permission(m, repo); m.expand(.attention) }),
            ("expanded-edit", 560, { m in working(m, repo); editRequest(m, repo); m.expand(.attention) }),
            ("expanded-antigravity", 440, { m in working(m, repo); antigravityPrompt(m) }),
            ("expanded-question", 600, { m in working(m, repo); question(m, repo); m.expand(.attention) }),
            ("expanded-question-multi", 600, { m in working(m, repo); multiQuestion(m, repo); m.expand(.attention) }),
            ("expanded-plan", 700, { m in working(m, repo); plan(m, repo); m.expand(.attention) }),
            ("expanded-usage", 680, { m in working(m, repo); sampleUsage(m); m.expand(.click); m.tab = .usage }),
        ]
        for (name, height, setup) in scenarios {
            let model = IslandModel()
            model.metrics = NotchMetrics(hasNotch: true, notchWidth: 185, notchHeight: 32, screenFrame: .zero)
            setup(model)
            let view = NotchRootView()
                .environmentObject(model)
                .frame(width: NotchPanelController.canvas.width, height: height, alignment: .top)
                .clipped()
                .background(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.62)], startPoint: .top, endPoint: .bottom))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
            print("rendered \(name).png")
        }
        renderMascots(to: dir)
    }

    /// Every orb expression on one sheet, snapped a few times so the motion cycles show.
    private static func renderMascots(to dir: URL) {
        let poses: [(String, SessionPhase, ActivityKind?, Date?)] =
            ActivityKind.allCases.map { ($0.rawValue, .working, $0, nil) } + [
                ("thinking", .thinking, nil, nil), ("approval", .needsApproval, nil, nil), ("done", .done, nil, nil),
                ("error", .error, nil, nil), ("compacting", .compacting, nil, nil), ("ready", .ready, nil, .now),
                ("dozing", .ready, nil, .distantPast),
            ]
        let agents = AgentKind.allCases.filter { $0 != .unknown }
        for frame in 1...3 {
            let sheet = VStack(alignment: .leading, spacing: 18) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 22) {
                        ForEach(Array(poses.enumerated()).filter { $0.offset % 3 == row }, id: \.offset) { i, pose in
                            VStack(spacing: 8) {
                                AgentMascot(
                                    agent: agents[i % agents.count], phase: pose.1, size: 56, activity: pose.2, subagents: 2, idleSince: pose.3
                                )
                                .frame(width: 120, height: 120)
                                Text(pose.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }
            .padding(30)
            .background(Color(white: 0.08))
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            {
                try? png.write(to: dir.appendingPathComponent("mascots-\(frame).png"))
                print("rendered mascots-\(frame).png")
            }
            Thread.sleep(forTimeInterval: 0.37)
        }
    }

    private static func send(_ m: IslandModel, _ payload: JSONValue, source: String = "claude", reply: Bool = false) {
        m.receive(BridgeEnvelope(source: source, payload: payload, env: ["TERM_PROGRAM": "iTerm.app"], expectsReply: reply), connection: nil)
    }

    private static func makeFakeRepo() -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orby-preview/acme-web")
        try? FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try? "ref: refs/heads/feat/login\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        return root.path
    }

    private static func working(_ m: IslandModel, _ repo: String) {
        send(m, ["hook_event_name": "UserPromptSubmit", "session_id": "a", "cwd": .string(repo), "prompt": "Fix the OAuth redirect loop on login"])
        send(m, ["hook_event_name": "PreToolUse", "session_id": "a", "cwd": .string(repo), "tool_name": "Bash", "tool_input": ["command": "cd web && pnpm test auth --reporter=dot", "description": "Run the auth tests"]])
        send(m, ["hook_event_name": "UserPromptSubmit", "session_id": "b", "cwd": "/Users/me/api-server", "prompt": "Add rate limiting to the public API"], source: "codex")
        send(m, ["hook_event_name": "PreToolUse", "session_id": "b", "cwd": "/Users/me/api-server", "tool_name": "apply_patch", "tool_input": ["input": "*** Begin Patch\n*** Update File: /Users/me/api-server/src/middleware/rateLimit.ts\n*** Add File: /Users/me/api-server/src/config/limits.ts\n*** Update File: /Users/me/api-server/test/rateLimit.test.ts\n*** End Patch"]], source: "codex")
        send(m, ["hook_event_name": "UserPromptSubmit", "session_id": "c", "cwd": "/Users/me/docs-site", "prompt": "Update the changelog for v2.3"])
        send(m, ["hook_event_name": "Stop", "session_id": "c", "cwd": "/Users/me/docs-site"])
        var reply = TranscriptInfo()
        reply.lastAssistantText = "## Summary\n\nUpdated **CHANGELOG.md** for `v2.3` and bumped the version in `package.json`.\n\n- Added the rate-limit entry"
        m.previewApply(reply, to: "claude:c")
    }

    private static func thinking(_ m: IslandModel) {
        let cwd: JSONValue = "/Users/me/mobile-app"
        send(m, ["hook_event_name": "UserPromptSubmit", "session_id": "d", "cwd": cwd, "prompt": "Why does the iOS build fail on CI?"])
        send(m, ["hook_event_name": "PreToolUse", "session_id": "d", "cwd": cwd, "tool_name": "Read", "tool_input": ["file_path": "/x/ci.yml"]])
        send(m, ["hook_event_name": "PostToolUse", "session_id": "d", "cwd": cwd, "tool_name": "Read", "tool_input": ["file_path": "/x/ci.yml"]])
        var info = TranscriptInfo()
        info.latestThinking = "The workflow pins Xcode 15, but the project needs the iOS 18 SDK — that mismatch explains the failure."
        m.previewApply(info, to: "claude:d")
    }

    private static func permission(_ m: IslandModel, _ repo: String) {
        send(m, [
            "hook_event_name": "PermissionRequest", "session_id": "a", "cwd": .string(repo), "tool_name": "Bash",
            "tool_input": ["command": "rm -rf node_modules && pnpm install --frozen-lockfile", "description": "Reinstall dependencies"],
            "permission_suggestions": [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "pnpm install:*"]], "behavior": "allow", "destination": "localSettings"]],
        ], reply: true)
    }

    /// A second agent waiting, so the queue pager and strip show up.
    private static func codexWaiting(_ m: IslandModel) {
        send(m, [
            "hook_event_name": "PermissionRequest", "session_id": "b", "cwd": "/Users/me/api-server", "tool_name": "shell",
            "tool_input": ["command": ["bash", "-lc", "npm publish --access public"]],
        ], source: "codex", reply: true)
    }

    /// Antigravity asks in its own terminal; the prompt comes from its CLI log, matched by step.
    private static func antigravityPrompt(_ m: IslandModel) {
        let base: [String: JSONValue] = ["conversationId": "g1", "workspacePaths": ["/Users/me/mobile-app"], "modelName": "gemini-3-pro"]
        func event(_ name: String, _ extra: [String: JSONValue] = [:]) -> JSONValue {
            .object(base.merging(extra) { _, new in new }.merging(["hook_event_name": .string(name)]) { _, new in new })
        }
        send(m, event("PreInvocation"), source: "antigravity")
        send(m, event("PreToolUse", ["stepIdx": 3, "toolCall": ["name": "run_command", "args": ["CommandLine": "rm -rf build && flutter build ios --release"]]]),
            source: "antigravity")
        m.antigravityLog(.confirmationShown(tool: "RunCommand", step: 3), logID: "cli-preview")
        // What the controller reads back from Antigravity's pane.
        let screen = """
            Run this command?
            > 1. Yes, run command
              2. Yes, and always allow in this conversation for commands that start with 'flutter'
              3. Yes, and always allow for commands that start with 'flutter' (Persist to settings.json)
              4. No, cancel
              ↑/↓ Navigate · tab Amend
            """
        if let menu = AntigravityMenu.parse(screen) { m.previewSetMenu(menu, for: "agy:cli-preview:3") }
    }

    private static func editRequest(_ m: IslandModel, _ repo: String) {
        let old = "export async function callback(req, res) {\n  const user = await exchange(req.query.code)\n  return redirect(next ?? \"/\")\n  await setSession(res, user)\n}"
        let new = "export async function callback(req, res) {\n  const user = await exchange(req.query.code)\n  await setSession(res, user)\n  return redirect(next ?? \"/\")\n}"
        send(m, [
            "hook_event_name": "PermissionRequest", "session_id": "a", "cwd": .string(repo), "tool_name": "Edit",
            "tool_input": ["file_path": .string(repo + "/src/auth/callback.ts"), "old_string": .string(old), "new_string": .string(new)],
            "permission_suggestions": [["type": "setMode", "mode": "acceptEdits", "destination": "session"]],
        ], reply: true)
    }

    private static func multiQuestion(_ m: IslandModel, _ repo: String) {
        send(m, [
            "hook_event_name": "PermissionRequest", "session_id": "a", "cwd": .string(repo), "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [
                [
                    "question": "Which providers should the login page offer?", "header": "Providers", "multiSelect": true,
                    "options": [
                        ["label": "Google", "description": "Most users already have an account"],
                        ["label": "GitHub", "description": "Good for a developer audience"],
                        ["label": "Email link", "description": "No password, works everywhere"],
                    ],
                ],
                ["question": "Keep the old password login?", "header": "Legacy", "options": [["label": "Yes"], ["label": "No"]]],
            ]],
        ], reply: true)
    }

    private static func question(_ m: IslandModel, _ repo: String) {
        send(m, [
            "hook_event_name": "PermissionRequest", "session_id": "a", "cwd": .string(repo), "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [[
                "question": "Which session store should the login flow use?", "header": "Storage", "multiSelect": false,
                "options": [
                    ["label": "Redis", "description": "Shared across instances, needs a Redis server"],
                    ["label": "Signed cookies", "description": "Stateless, 4 KB limit"],
                    ["label": "Postgres", "description": "Reuse the existing database"],
                ],
            ]]],
        ], reply: true)
    }

    private static func plan(_ m: IslandModel, _ repo: String) {
        let md = """
            # Fix OAuth redirect loop

            The callback handler re-enters `/login` because the session cookie is set **after** the redirect.

            ## Steps
            1. Move `setSession()` before `redirect()` in `auth/callback.ts`
            2. Add a guard for `?error=` responses
            3. Add an integration test covering the loop

            - [ ] Verify on staging
            ```ts
            await setSession(res, user)
            return redirect(next ?? "/")
            ```
            """
        send(m, ["hook_event_name": "PermissionRequest", "session_id": "a", "cwd": .string(repo), "tool_name": "ExitPlanMode", "tool_input": ["plan": .string(md)]], reply: true)
    }

    private static func sampleUsage(_ m: IslandModel) {
        var h = TokenHistory()
        // Millions of tokens per day, oldest first.
        let amounts: [(AgentKind, [Double])] = [
            (.claude, [4.1, 6.3, 2.2, 8.8, 5.0, 3.4, 7.2]),
            (.codex, [1.2, 0.4, 2.9, 1.1, 0, 2.2, 1.8]),
            (.opencode, [2.4, 0, 1.6, 0.9, 3.1, 0, 1.3]),
            (.antigravity, [0, 0.8, 0.5, 0, 1.4, 0.6, 0.9]),
            (.qwen, [0, 0, 0.3, 0.2, 0, 0.4, 0]),
            (.pi, [0.2, 0, 0, 0.1, 0.3, 0, 0.2]),
        ]
        for (agent, perDay) in amounts {
            for (i, m) in perDay.enumerated() where m > 0 {
                let day = TokenHistory.dayKey(Date().addingTimeInterval(Double(i - 6) * 86400))
                h.add(day: day, agent: agent, tokens: Int(m * 1_000_000))
            }
        }
        let claude = RateLimits(provider: .claude, plan: nil, windows: [
            UsageWindow(label: "5h", used: 0.34, resetsAt: Date().addingTimeInterval(7_400)),
            UsageWindow(label: "7d", used: 0.62, resetsAt: Date().addingTimeInterval(260_000)),
        ], fetchedAt: Date())
        let codex = RateLimits(provider: .codex, plan: "plus", windows: [
            UsageWindow(label: "5h", used: 0.08, resetsAt: Date().addingTimeInterval(12_000)),
            UsageWindow(label: "7d", used: 0.91, resetsAt: Date().addingTimeInterval(90_000)),
        ], fetchedAt: Date())
        let seen = Date().addingTimeInterval(-180)
        let antigravity = AntigravityQuota(buckets: [
            "gemini-5h": .init(id: "gemini-5h", remaining: 0.97, resetsAt: Date().addingTimeInterval(3_900), observedAt: seen),
            "gemini-weekly": .init(id: "gemini-weekly", remaining: 0.88, resetsAt: Date().addingTimeInterval(475_000), observedAt: seen),
            "3p-5h": .init(id: "3p-5h", remaining: 1, resetsAt: Date().addingTimeInterval(17_000), observedAt: seen),
            "3p-weekly": .init(id: "3p-weekly", remaining: 0.18, resetsAt: Date().addingTimeInterval(476_000), observedAt: seen),
        ], plan: "Pro").rateLimits
        m.usage.loadPreview(history: h, claude: claude, codex: codex, antigravity: antigravity)
    }
}
