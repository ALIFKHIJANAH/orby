import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

@Suite struct AgentLaunchTests {
    @Test func eachAgentStartsWithItsFirstPrompt() {
        #expect(AgentLaunch.command(.claude, prompt: "Fix the login bug") == "claude 'Fix the login bug'")
        #expect(AgentLaunch.command(.codex, prompt: "Fix it") == "codex 'Fix it'")
        #expect(AgentLaunch.command(.antigravity, prompt: "Fix it") == "agy -i 'Fix it'")
        #expect(AgentLaunch.command(.opencode, prompt: "Fix it") == "opencode --prompt 'Fix it'")
    }

    @Test func noPromptStartsTheBareCLI() {
        #expect(AgentLaunch.command(.claude) == "claude")
        #expect(AgentLaunch.command(.antigravity, prompt: "  \n ") == "agy")
        #expect(AgentLaunch.command(.opencode) == "opencode")
    }

    @Test func promptIsQuotedAndKeptOnOneLine() {
        // Typed into a shell: a newline would run the command early, and $ or ' must stay literal.
        let cmd = AgentLaunch.command(.claude, prompt: "Don't touch $HOME\nthen run `ls`\n")
        #expect(cmd == "claude 'Don'\\''t touch $HOME then run `ls`'")
    }

    @Test func folderPrefix() {
        #expect(AgentLaunch.inFolder("/Users/me/My Project", "claude") == "cd '/Users/me/My Project' && claude")
    }

    @Test func recentFoldersNewestFirstWithoutDuplicates() {
        #expect(AgentLaunch.remember("/b", in: ["/a", "/b", "/c"]) == ["/b", "/a", "/c"])
        #expect(AgentLaunch.remember("/new", in: []) == ["/new"])
        let full = (1...8).map { "/\($0)" }
        #expect(AgentLaunch.remember("/9", in: full) == ["/9"] + full.prefix(7))
    }
}

@Suite struct OrcaWorktreeTests {
    // Trimmed from real `orca worktree list --json` output.
    let list: JSONValue = [
        "ok": true,
        "result": ["worktrees": [
            ["path": "/Users/me/api", "branch": "refs/heads/feat/rbac", "isMainWorktree": true, "isBare": false, "isArchived": false],
            ["path": "/Users/me/orca/workspaces/api/arrangement", "branch": "refs/heads/me/arrangement", "isMainWorktree": false],
            ["path": "/Users/me/old", "branch": "refs/heads/main", "isArchived": true],
            ["path": "/Users/me/bare.git", "isBare": true],
        ]],
    ]

    @Test func parsesLiveCheckouts() {
        let w = OrcaFleet.worktrees(list)
        #expect(w == [
            OrcaWorktree(path: "/Users/me/api", branch: "feat/rbac"),
            OrcaWorktree(path: "/Users/me/orca/workspaces/api/arrangement", branch: "me/arrangement"),
        ])
        #expect(OrcaFleet.worktrees(["ok": false]).isEmpty)
    }

    @Test func findsTheCheckoutHoldingAFolder() {
        let w = [OrcaWorktree(path: "/a/foo", branch: nil), OrcaWorktree(path: "/a/foo/nested", branch: nil)]
        #expect(OrcaFleet.worktree(containing: "/a/foo", in: w)?.path == "/a/foo")
        #expect(OrcaFleet.worktree(containing: "/a/foo/src", in: w)?.path == "/a/foo")
        // The innermost checkout wins.
        #expect(OrcaFleet.worktree(containing: "/a/foo/nested/x", in: w)?.path == "/a/foo/nested")
        // A sibling that only shares a name prefix is not inside.
        #expect(OrcaFleet.worktree(containing: "/a/foobar", in: w) == nil)
    }
}
