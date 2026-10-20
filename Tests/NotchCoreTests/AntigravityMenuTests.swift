import Foundation
import Testing

@testable import NotchCore

/// Screens as Antigravity CLI 1.4.2 renders its permission prompt (captured live).
private let runCommandScreen = """
    ○ Thought for 4.4s (The task is to execute a simple command. First, the cur...)
    ● Ran (echo hi-from-notch-test) (ctrl+o to expand)

    Command
    ────────────────────────────────────────────────────────────────────────────────

    Requesting permission for:
       echo hi-from-notch-test

    Run this command?
    > 1. Yes, run command
      2. Yes, and always allow in this conversation for commands that start with
    'echo'
      3. Yes, and always allow for commands that start with 'echo' (Persist to
    settings.json)
      4. No, cancel

      ↑/↓ Navigate · tab Amend · ctrl+g edit/expand command
    esc to cancelGemini 3.8 Flash · medium
    """

@Suite struct AntigravityMenuTests {
    @Test func parsesTheRunCommandMenu() throws {
        let menu = try #require(AntigravityMenu.parse(runCommandScreen))
        #expect(menu.question == "Run this command?")
        #expect(menu.options.map(\.number) == [1, 2, 3, 4])
        #expect(menu.options.map(\.kind) == [.approve, .approveAlways, .approveAlways, .deny])
        #expect(menu.options[1].label == "Yes, and always allow in this conversation for commands that start with 'echo'")
        #expect(menu.approve?.number == 1)
        #expect(menu.approveAlways?.number == 2)
        #expect(menu.deny?.number == 4)
    }

    @Test func acceptsOtherCursorsAndShortMenus() throws {
        let screen = "Allow this edit to main.go?\n❯ 1. Yes\n  2. No, keep it as is\n\n  esc to cancel"
        let menu = try #require(AntigravityMenu.parse(screen))
        #expect(menu.options.map(\.kind) == [.approve, .deny])
    }

    @Test func ignoresAnsweredMenuWithLaterOutput() {
        // Terminal.app returns the whole scrollback: an old menu followed by what happened next.
        let stale = runCommandScreen + "\n● Ran (echo hi-from-notch-test)\nhi-from-notch-test\n\nDONE\n"
        #expect(AntigravityMenu.parse(stale) == nil)
    }

    @Test func noMenuMeansNothingToAnswer() {
        #expect(AntigravityMenu.parse("⣾  Running command...\n") == nil)
        // A numbered list in normal output is not a permission menu.
        #expect(AntigravityMenu.parse("Steps:\n1. Build\n2. Test\n") == nil)
    }

    @Test func stripsEscapeSequences() throws {
        let colored = "Run this command?\n\u{1B}[36m> 1. Yes, run command\u{1B}[0m\n  2. No, cancel\n"
        #expect(try #require(AntigravityMenu.parse(colored)).options.count == 2)
    }
}
