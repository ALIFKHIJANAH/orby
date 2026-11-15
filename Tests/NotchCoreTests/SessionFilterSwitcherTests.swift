import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

private func session(
    _ id: String, cwd: String = "/tmp/proj", title: String? = nil, phase: SessionPhase = .done,
    updated: TimeInterval = 0, branch: String? = nil
) -> AgentSession {
    var s = AgentSession(agent: .claude, sessionID: id, cwd: cwd, now: Date(timeIntervalSince1970: updated))
    s.title = title
    s.phase = phase
    if let branch { s.git = GitInfo(branch: branch, repoRoot: cwd, worktreeRoot: cwd) }
    return s
}

@Suite struct SessionFilterTests {
    @Test func folderRulesMatchTheFolderAndEverythingUnderIt() {
        let f = SessionFilter(folders: ["/work/scratch/"], home: "/Users/me")
        #expect(f.hides(cwd: "/work/scratch", firstPrompt: nil))
        #expect(f.hides(cwd: "/work/scratch/deep/er", firstPrompt: nil))
        #expect(f.hides(cwd: "/Work/Scratch/x", firstPrompt: nil))
        #expect(!f.hides(cwd: "/work/scratch2", firstPrompt: nil))
        #expect(!f.hides(cwd: "/work", firstPrompt: nil))
        #expect(!f.hides(cwd: "", firstPrompt: nil))
    }

    @Test func tildeExpandsAndBlankOrRelativeRulesAreIgnored() {
        let f = SessionFilter(folderLines: "~/tmp\n\n   \nrelative/dir\n", promptLines: "", home: "/Users/me")
        #expect(f.folders == ["/Users/me/tmp"])
        #expect(f.hides(cwd: "/Users/me/tmp/a", firstPrompt: nil))
        #expect(!f.hides(cwd: "/Users/me/relative/dir", firstPrompt: nil))
        #expect(SessionFilter(folderLines: "\n \n", promptLines: " \n").isEmpty)
    }

    @Test func promptRulesMatchSubstringsIgnoringCase() {
        let f = SessionFilter(folderLines: "", promptLines: "You are working inside Orca\n  nightly lint  ")
        #expect(f.promptSubstrings == ["You are working inside Orca", "nightly lint"])
        #expect(f.hides(cwd: "/a", firstPrompt: "Preamble.\nyou are WORKING inside orca, a multi-agent IDE"))
        #expect(f.hides(cwd: "/a", firstPrompt: "run the Nightly Lint job"))
        #expect(!f.hides(cwd: "/a", firstPrompt: "fix the login bug"))
        #expect(!f.hides(cwd: "/a", firstPrompt: nil))
    }

    @Test func sessionUsesItsFullFirstPromptNotTheLatestOne() {
        var engine = SessionEngine()
        let env = { (prompt: String) in
            BridgeEnvelope(
                id: UUID().uuidString, source: "claude",
                payload: ["hook_event_name": "UserPromptSubmit", "session_id": "s", "cwd": "/a", "prompt": .string(prompt)],
                env: [:], expectsReply: false)
        }
        _ = engine.handle(env("Context line\nThis is a nightly lint run"))
        _ = engine.handle(env("now do something else"))
        let s = engine.sessions["claude:s"]!
        #expect(s.title == "Context line")
        #expect(s.firstPrompt == "Context line\nThis is a nightly lint run")
        #expect(SessionFilter(promptSubstrings: ["nightly lint"]).hides(s))
        #expect(!SessionFilter(promptSubstrings: ["something else"]).hides(s))
    }

    @Test func emptyFilterHidesNothing() {
        #expect(!SessionFilter().hides(session("a", title: "anything")))
    }
}

@Suite struct SessionSwitcherTests {
    let sessions = [
        session("done-old", cwd: "/w/api", title: "Add endpoint", phase: .done, updated: 10),
        session("working", cwd: "/w/web", title: "Fix navbar", phase: .working, updated: 20),
        session("done-new", cwd: "/w/docs", title: "Write API guide", phase: .done, updated: 30),
        session("waiting", cwd: "/w/mobile", title: "Ship release", phase: .needsApproval, updated: 5),
    ]

    @Test func ordersByWhatNeedsYouThenWorkingThenNewest() {
        #expect(SessionSwitcher.entries(sessions, query: "").map(\.sessionID) == ["waiting", "working", "done-new", "done-old"])
        #expect(SessionSwitcher.entries(sessions, query: "   ").count == 4)
    }

    @Test func filtersByProjectOrTitleIgnoringCase() {
        #expect(SessionSwitcher.entries(sessions, query: "NAV").map(\.sessionID) == ["working"])
        #expect(SessionSwitcher.entries(sessions, query: "mobile").map(\.sessionID) == ["waiting"])
        #expect(SessionSwitcher.entries(sessions, query: "zzz").isEmpty)
    }

    @Test func everyWordMustMatch() {
        #expect(SessionSwitcher.entries(sessions, query: "api guide").map(\.sessionID) == ["done-new"])
        #expect(SessionSwitcher.entries(sessions, query: "api navbar").isEmpty)
    }

    @Test func projectPrefixRanksAboveTitleMatches() {
        // "api" is the api project's name and a word in the docs session's title.
        #expect(SessionSwitcher.entries(sessions, query: "api").map(\.sessionID) == ["done-old", "done-new"])
        // Word starts beat mid-word matches; ties keep the status order.
        let list = [
            session("mid", cwd: "/w/x", title: "rebuild cache", phase: .working, updated: 9),
            session("start", cwd: "/w/y", title: "build it", phase: .done, updated: 1),
        ]
        #expect(SessionSwitcher.entries(list, query: "build").map(\.sessionID) == ["start", "mid"])
    }

    @Test func matchesBranchNames() {
        let list = [session("b", cwd: "/w/z", title: "x", branch: "feat/login")]
        #expect(SessionSwitcher.entries(list, query: "login").map(\.sessionID) == ["b"])
    }

    @Test func selectionWraps() {
        #expect(SessionSwitcher.move(0, by: -1, count: 3) == 2)
        #expect(SessionSwitcher.move(2, by: 1, count: 3) == 0)
        #expect(SessionSwitcher.move(1, by: 1, count: 3) == 2)
        #expect(SessionSwitcher.move(5, by: 1, count: 0) == 0)
    }
}
