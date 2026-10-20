import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

@Suite struct CommandHumanizerTests {
    @Test(arguments: [
        ("npm test", "Running tests"),
        ("cd web && pnpm test auth", "Running tests"),
        ("CI=1 FORCE_COLOR=0 yarn vitest run", "Running tests"),
        ("python3 -m pytest -q tests/", "Running tests"),
        ("swift test --parallel", "Running tests"),
        ("xcodebuild -scheme App test", "Running tests"),
        ("pnpm install --frozen-lockfile", "Installing dependencies"),
        ("rm -rf node_modules && pnpm install", "Installing dependencies"),
        ("npm i", "Installing dependencies"),
        ("pnpm add zod", "Adding zod"),
        ("brew install ripgrep", "Installing ripgrep"),
        ("npm run build", "Building"),
        ("cargo build --release", "Building"),
        ("npm run dev", "Starting the dev server"),
        ("npx eslint src --fix", "Formatting"),
        ("npx tsc --noEmit", "Type-checking"),
        ("git status", "Checking git status"),
        ("git diff HEAD~1", "Reviewing changes"),
        ("git log --oneline -5", "Reading git history"),
        ("git add -A && git commit -m \"Fix login redirect\"", "Committing “Fix login redirect”"),
        ("git push origin main", "Pushing to origin"),
        ("git checkout -b feat/login", "Creating branch feat/login"),
        ("gh pr create --fill", "Opening a pull request"),
        ("cat src/App.swift | head -40", "Reading App.swift"),
        ("sed -n '1,80p' Sources/Main.swift", "Reading Main.swift"),
        ("rg -n \"TODO\" src", "Searching for “TODO”"),
        ("find . -name '*.swift'", "Finding files"),
        ("ls -la", "Listing files"),
        ("mkdir -p build/out", "Creating out"),
        ("curl -s https://api.example.com/v1/users", "Fetching api.example.com"),
        ("docker compose up -d", "Starting containers"),
        ("bash -lc 'cargo test'", "Running tests"),
        ("sudo lsof -i :3000", "Checking processes"),
        ("./scripts/deploy.sh", "Running deploy.sh"),
    ])
    func humanizes(command: String, expected: String) {
        #expect(CommandHumanizer.describe(command) == expected)
    }

    @Test func prefersClaudesOwnDescription() {
        let a = ToolDescriber.activity(tool: "Bash", input: ["command": "pnpm test auth", "description": "Run the auth tests"])
        #expect(a.progressive == "Run the auth tests")
        #expect(a.intent == "run the auth tests")
        #expect(a.detail == "pnpm test auth")
    }
}

@Suite struct ActivityTests {
    @Test func intentForms() {
        #expect(Activity("Installing dependencies").intent == "install dependencies")
        #expect(Activity("Editing App.swift").intent == "edit App.swift")
        #expect(Activity("Type-checking").intent == "type-check")
        #expect(Activity("GitHub sync").intent == "GitHub sync")
        #expect(Activity("Same", detail: "Same").detail == nil)
    }

    @Test func toolPhrases() {
        #expect(ToolDescriber.describe(tool: "Glob", input: ["pattern": "**/*.swift"]) == "Finding Swift files")
        #expect(ToolDescriber.describe(tool: "Grep", input: ["pattern": "fetchUser"]) == "Searching for “fetchUser”")
        #expect(ToolDescriber.describe(tool: "WebFetch", input: ["url": "https://docs.swift.org/x"]) == "Reading docs.swift.org")
        #expect(ToolDescriber.describe(tool: "TodoWrite", input: [:]) == "Updating the to-do list")
        #expect(ToolDescriber.describe(tool: "mcp__claude_ai_Notion__notion-search", input: [:]) == "Using Notion: notion search")
        let ask = ToolDescriber.describe(
            tool: "AskUserQuestion", input: ["questions": [["question": "Which DB?", "options": []]]])
        #expect(ask == "Asking: Which DB?")
        #expect(ToolDescriber.describe(tool: "ExitPlanMode", input: ["plan": "## Fix the **login** loop\n\nSteps…"]) == "Plan ready: Fix the login loop")
    }

    @Test func codexPatchFiles() {
        let patch = "*** Begin Patch\n*** Update File: /repo/Sources/App.swift\n@@\n-a\n+b\n*** Add File: /repo/Sources/New.swift\n+x\n*** Update File: /repo/README.md\n*** End Patch"
        let a = ToolDescriber.activity(tool: "apply_patch", input: ["input": .string(patch)])
        #expect(a.progressive == "Editing App.swift and 2 more files")
        #expect(a.detail == "App.swift, New.swift, README.md")
        let created = ToolDescriber.activity(tool: "apply_patch", input: ["command": ["apply_patch", "*** Add File: a/b.ts\n+x"]])
        #expect(created.progressive == "Creating b.ts")
    }

    @Test func permissionAttention() {
        var engine = SessionEngine()
        let env = BridgeEnvelope(
            id: "r", source: "claude",
            payload: [
                "hook_event_name": "PermissionRequest", "session_id": "s", "cwd": "/tmp", "tool_name": "Bash",
                "tool_input": ["command": "rm -rf node_modules && pnpm install", "description": "Reinstall dependencies"],
            ], expectsReply: true)
        _ = engine.handle(env)
        #expect(engine.sessions["claude:s"]?.attention == "Wants to reinstall dependencies")
        _ = engine.resolve(requestID: "r")
        #expect(engine.sessions["claude:s"]?.attention == nil)
    }
}

@Suite struct PlainTextTests {
    @Test func stripsMarkdownAndFillerHeadings() {
        let reply = """
            ## Summary

            Fixed the **OAuth redirect loop** in `auth/callback.ts` — see [the PR](https://x.y/1).

            - Moved `setSession()` before the redirect
            - Added a regression test
            """
        #expect(PlainText.summary(reply, max: 200)
            == "Fixed the OAuth redirect loop in auth/callback.ts — see the PR. Moved setSession() before the redirect. Added a regression test")
        #expect(PlainText.summary(reply, max: 80) == "Fixed the OAuth redirect loop in auth/callback.ts — see the PR.")
    }

    @Test func skipsCodeAndTables() {
        let text = "```swift\nlet x = 1\n```\n| a | b |\n|---|---|\nAll tests pass now."
        #expect(PlainText.summary(text, max: 100) == "All tests pass now.")
    }

    @Test func cutsAtWordBoundary() {
        let long = "The workflow pins an old Xcode version that cannot build against the newest iOS SDK required here"
        let cut = PlainText.summary(long, max: 40)
        #expect(cut == "The workflow pins an old Xcode version…")
        #expect(cut.count <= 40)
    }

    @Test func singleLineUnchanged() {
        #expect(PlainText.summary("quota exceeded", max: 160) == "quota exceeded")
    }

    @Test func latestSentenceForThoughts() {
        let thought = "**Inspecting CI.** The config looks fine. The failure must come from the Xcode pin, so check `ci.yml` next."
        #expect(PlainText.latest(thought, max: 140) == "The failure must come from the Xcode pin, so check ci.yml next.")
        #expect(PlainText.latest("Hmm. Okay.", max: 140) == "Hmm. Okay.")
    }
}
