import Foundation
import NotchShared
import Testing

@testable import NotchCore

@Suite struct FocusQuietTests {
    static let noon = QuietHoursTests.at(12)
    static let night = QuietHoursTests.at(23)

    private func silent(
        _ rules: QuietRules, at date: Date = noon, locked: Bool = false, focus: Bool?
    ) -> Bool {
        rules.silencesSounds(at: date, screenLocked: locked, focusOn: focus, calendar: QuietHoursTests.calendar)
    }

    @Test func focusOnSilencesWhenFollowingFocus() {
        let rules = QuietRules(muteWhenLocked: false, quietHours: nil, followFocus: true)
        #expect(silent(rules, focus: true))
        #expect(!silent(rules, focus: false))
    }

    @Test func unknownFocusCountsAsOff() {
        // No permission to read Focus: never silence because of it.
        #expect(!silent(QuietRules(muteWhenLocked: false, quietHours: nil, followFocus: true), focus: nil))
    }

    @Test func focusIgnoredWhenSettingOff() {
        #expect(!silent(QuietRules(muteWhenLocked: false, quietHours: nil, followFocus: false), focus: true))
    }

    @Test func quietHoursStillApplyWithoutFocus() {
        let rules = QuietRules(muteWhenLocked: false, quietHours: (22, 8), followFocus: true)
        #expect(silent(rules, at: Self.night, focus: false))
        #expect(!silent(rules, at: Self.noon, focus: false))
        #expect(silent(rules, at: Self.noon, focus: true))
    }

    @Test func lockedScreen() {
        #expect(silent(QuietRules(muteWhenLocked: true, quietHours: nil, followFocus: false), locked: true, focus: false))
        #expect(!silent(QuietRules(muteWhenLocked: false, quietHours: nil, followFocus: false), locked: true, focus: false))
    }
}

@Suite struct KeepAwakeTests {
    @Test func defaultOffNeverTakes() {
        var policy = KeepAwakePolicy()
        #expect(policy.update(mode: .off, anyWorking: true) == nil)
        #expect(!policy.held)
    }

    @Test func takenWhileWorkingReleasedWhenIdle() {
        var policy = KeepAwakePolicy()
        #expect(policy.update(mode: .whileWorking, anyWorking: false) == nil)
        #expect(policy.update(mode: .whileWorking, anyWorking: true) == .take)
        #expect(policy.held)
        // More working events don't take a second assertion.
        #expect(policy.update(mode: .whileWorking, anyWorking: true) == nil)
        #expect(policy.update(mode: .whileWorking, anyWorking: false) == .release)
        #expect(!policy.held)
        #expect(policy.update(mode: .whileWorking, anyWorking: false) == nil)
    }

    @Test func turningSettingOffReleases() {
        var policy = KeepAwakePolicy()
        #expect(policy.update(mode: .whileWorking, anyWorking: true) == .take)
        #expect(policy.update(mode: .off, anyWorking: true) == .release)
        #expect(policy.update(mode: .whileWorking, anyWorking: true) == .take)
    }

    @Test func stopReleasesOnlyWhenHeld() {
        var policy = KeepAwakePolicy()
        #expect(policy.stop() == nil)
        _ = policy.update(mode: .whileWorking, anyWorking: true)
        #expect(policy.stop() == .release)
        #expect(!policy.held)
        #expect(policy.stop() == nil)
    }
}

@Suite struct ClaudeConfigDirTests {
    private func tempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("orby-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func extrasSkipDefaultsBlanksAndDuplicates() {
        let home = URL(fileURLWithPath: "/Users/me")
        let env = ["CLAUDE_CONFIG_DIR": "/Users/me/.claude-env"]
        let dirs = ClaudeConfigDirs.extras(
            ["~/.claude", "/Users/me/.claude/", "/Users/me/.claude-env", "  ", "~/.claude-work", "/Users/me/.claude-work/", "/opt/claude"],
            home: home, environment: env)
        #expect(dirs.map(\.path) == ["/Users/me/.claude-work", "/opt/claude"])
        #expect(ClaudeConfigDirs.defaultDir(home: home, environment: env).path == "/Users/me/.claude-env")
        #expect(ClaudeConfigDirs.defaultDir(home: home, environment: [:]).path == "/Users/me/.claude")
    }

    @Test func installAndUninstallAcrossFolders() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let backups = home.appendingPathComponent("backups")
        let work = home.appendingPathComponent(".claude-work")
        let personal = home.appendingPathComponent(".claude-personal")
        let gone = home.appendingPathComponent(".claude-gone")
        for dir in [work, personal] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        // One folder already has someone else's hooks and settings, which must survive.
        let foreign: JSONValue = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "other-tool"]]]]],
        ]
        try foreign.encoded().write(to: ClaudeConfigDirs.settingsURL(personal))

        #expect(HookInstaller.status(claudeConfigDir: gone) == .agentMissing)
        #expect(HookInstaller.status(claudeConfigDir: work) == .notInstalled)
        #expect(HookInstaller.status(claudeConfigDir: personal) == .notInstalled)

        let now = Date()
        #expect(try HookInstaller.apply(claudeConfigDir: work, install: true, backupDir: backups, now: now) == nil)
        let backup = try #require(try HookInstaller.apply(claudeConfigDir: personal, install: true, backupDir: backups, now: now))
        #expect(backup.lastPathComponent.hasPrefix("claude-_claude-personal-settings.json."))
        #expect(HookInstaller.status(claudeConfigDir: work) == .installed)
        #expect(HookInstaller.status(claudeConfigDir: personal) == .installed)

        // Installing in an extra folder doesn't touch the default one.
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/settings.json").path))

        try HookInstaller.apply(claudeConfigDir: personal, install: false, backupDir: backups, now: now.addingTimeInterval(1))
        #expect(HookInstaller.status(claudeConfigDir: personal) == .notInstalled)
        #expect(HookInstaller.status(claudeConfigDir: work) == .installed)
        let kept = try JSONValue.decode(Data(contentsOf: ClaudeConfigDirs.settingsURL(personal)))
        #expect(kept["model"]?.string == "opus")
        #expect(kept["hooks"]?["Stop"]?.array?.count == 1)
        #expect(HookInstaller.foreignBlockingHooks(in: kept).isEmpty)

        try HookInstaller.apply(claudeConfigDir: work, install: false, backupDir: backups)
        #expect(HookInstaller.status(claudeConfigDir: work) == .notInstalled)
        // Removing from a folder with no settings file writes nothing.
        let empty = home.appendingPathComponent(".claude-empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(try HookInstaller.apply(claudeConfigDir: empty, install: false, backupDir: backups) == nil)
        #expect(!FileManager.default.fileExists(atPath: ClaudeConfigDirs.settingsURL(empty).path))
    }

    @Test func unreadableSettingsLeftAlone() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dir = home.appendingPathComponent(".claude-broken")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: ClaudeConfigDirs.settingsURL(dir))
        #expect(HookInstaller.status(claudeConfigDir: dir) == .unreadable("settings.json is not valid JSON"))
        #expect(throws: HookInstaller.InstallError.self) {
            try HookInstaller.apply(claudeConfigDir: dir, install: true, backupDir: home.appendingPathComponent("b"))
        }
        #expect(try String(contentsOf: ClaudeConfigDirs.settingsURL(dir), encoding: .utf8) == "{ nope")
    }
}
