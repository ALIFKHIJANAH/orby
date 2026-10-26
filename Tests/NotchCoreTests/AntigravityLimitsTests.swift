import Foundation
import Testing

@testable import NotchCore
@testable import NotchShared

/// The sample payload from https://antigravity.google/docs/cli/statusline.
let documentedStatusLine = #"""
    {"cwd":"/home/user/my-project","session_id":"12345678-abcd-ef01-2345-6789abcdef01",
     "conversation_id":"12345678-abcd-ef01-2345-6789abcdef01",
     "transcript_path":"/home/user/.gemini/antigravity/brain/12345678-abcd-ef01-2345-6789abcdef01/.system_generated/logs/transcript.jsonl",
     "model":{"id":"Gemini 3.5 Flash (High)","display_name":"Gemini 3.5 Flash (High)"},
     "workspace":{"current_dir":"/home/user/my-project","project_dir":"/home/user/my-project"},"version":"1.0.13",
     "context_window":{"total_input_tokens":88244,"total_output_tokens":61074,"context_window_size":1048576,
       "used_percentage":14.24,"remaining_percentage":85.76,
       "current_usage":{"input_tokens":63382,"output_tokens":346,"cache_creation_input_tokens":0,"cache_read_input_tokens":20857}},
     "exceeds_200k_tokens":false,"product":"antigravity",
     "quota":{"gemini-weekly":{"remaining_fraction":0.9378,"reset_time":"2026-07-06T07:50:32Z","reset_in_seconds":560580}},
     "agent_state":"idle","vcs":{"type":"git","branch":"main","dirty":false},"sandbox":{"enabled":false},
     "artifact_count":2,"plan_tier":"Pro","email":"developer@email.com","task_count":1,"terminal_width":111,
     "execution_mode":"planning"}
    """#

/// `agy -p "/usage" --output-format json` as agy 1.4.3 printed it on a real Mac (descriptions trimmed).
let capturedUsageOutput = #"""
    {"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t98%\t2026-10-26T14:41:30Z\n",
     "duration_seconds":0,"num_turns":0,
     "usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},
     "command":{"name":"usage","data":{"description":"Within each group, models share a weekly limit and a 5-hour limit.",
       "groups":[
         {"name":"Gemini Models","description":"Models within this group: Gemini Flash, Gemini Pro","buckets":[
           {"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.9769336581230164,"reset_time":"2026-10-26T14:41:30Z"},
           {"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.9701865315437317,"reset_time":"2026-10-21T03:19:39Z"}]},
         {"name":"Claude and GPT models","description":"Models within this group: Claude Opus, Claude Sonnet, GPT-OSS","buckets":[
           {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.8193972110748291,"reset_time":"2026-10-26T14:59:34Z"},
           {"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":1,"reset_time":"2026-10-21T07:14:47Z"}]}]}}}
    """#

private func json(_ s: String) throws -> JSONValue { try JSONValue.decode(Data(s.utf8)) }
private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

struct AntigravityQuotaTests {
    @Test func documentedStatusLinePayload() throws {
        let now = iso("2026-07-01T00:00:00Z")
        let q = try #require(AntigravityQuota.statusLine(json(documentedStatusLine), now: now))
        #expect(q.plan == "Pro")
        let b = try #require(q.buckets["gemini-weekly"])
        #expect(abs(b.remaining - 0.9378) < 1e-9)
        #expect(b.resetsAt == iso("2026-07-06T07:50:32Z"))
        let limits = try #require(q.rateLimits)
        #expect(limits.provider == .antigravity)
        #expect(limits.plan == "Pro")
        #expect(limits.fetchedAt == now)
        #expect(limits.windows.map(\.label) == ["Gemini 7d"])
        #expect(abs(limits.windows[0].used - 0.0622) < 1e-9)
    }

    @Test func resetInSecondsWhenNoResetTime() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let q = try #require(
            AntigravityQuota.statusLine(json(#"{"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_in_seconds":600}}}"#), now: now))
        #expect(q.buckets["gemini-5h"]?.resetsAt == now.addingTimeInterval(600))
        #expect(q.plan == nil)
    }

    @Test func statusLineWithoutQuotaOrPlanIsNothing() throws {
        #expect(AntigravityQuota.statusLine(try json(#"{"model":{"id":"x"},"quota":{}}"#)) == nil)
        #expect(AntigravityQuota.statusLine(try json(#"{"quota":{"gemini-weekly":{"remaining_fraction":"lots"}}}"#)) == nil)
        // Plan alone is kept, so the block can show the tier before any quota arrives.
        #expect(AntigravityQuota.statusLine(try json(#"{"plan_tier":"Ultra"}"#))?.plan == "Ultra")
    }

    @Test func summaryLineForTheStatusBar() throws {
        #expect(AntigravityStatusLine.summary(try json(documentedStatusLine)) == "Gemini 3.5 Flash (High) · Gemini 7d 94% left")
        let tight = #"{"model":{"id":"m"},"quota":{"gemini-weekly":{"remaining_fraction":0.9},"3p-5h":{"remaining_fraction":0.25}}}"#
        #expect(AntigravityStatusLine.summary(try json(tight)) == "m · Claude/GPT 5h 25% left")
        #expect(AntigravityStatusLine.summary(try json("{}")) == "")
    }

    @Test func bucketLabels() {
        #expect(AntigravityStatusLine.label(bucket: "gemini-weekly") == "Gemini 7d")
        #expect(AntigravityStatusLine.label(bucket: "gemini-5h") == "Gemini 5h")
        #expect(AntigravityStatusLine.label(bucket: "3p-weekly") == "Claude/GPT 7d")
        #expect(AntigravityStatusLine.label(bucket: "flash_lite-daily") == "Flash Lite 1d")
        #expect(AntigravityStatusLine.label(bucket: "credits") == "Credits")
    }

    @Test func capturedUsageCommandOutput() throws {
        let now = iso("2026-10-21T02:15:00Z")
        let q = try #require(AntigravityQuota.usageCommand(json(capturedUsageOutput), now: now))
        #expect(Set(q.buckets.keys) == ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h"])
        #expect(q.plan == nil)
        let limits = try #require(q.rateLimits)
        #expect(limits.windows.map(\.label) == ["Gemini 5h", "Gemini 7d", "Claude/GPT 5h", "Claude/GPT 7d"])
        #expect(limits.windows.map { Int(($0.used * 100).rounded()) } == [3, 2, 0, 18])
        #expect(limits.windows[0].resetsAt == iso("2026-10-21T03:19:39Z"))
        // Not mostPressured: it skips windows past their reset by the real clock, and these reset in 2026-10.
        #expect(limits.windows.max { $0.used < $1.used }?.label == "Claude/GPT 7d")
    }

    @Test func usageCommandIsReadDefensively() throws {
        // A model turn means agy took "/usage" as a prompt: its text isn't quota.
        #expect(AntigravityQuota.usageCommand(try json(#"{"num_turns":1,"buckets":[{"id":"x","remaining_fraction":0.5}]}"#)) == nil)
        #expect(AntigravityQuota.usageCommand(try json(#"{"response":"Gemini\t98%"}"#)) == nil)
        #expect(AntigravityQuota.usageCommand(try json(#"{"groups":[{"buckets":[{"id":"a","remaining_fraction":7}]}]}"#)) == nil)
        // Other spellings of the same thing are fine.
        let camel = #"{"quota":{"items":[{"bucketId":"gemini-weekly","remainingFraction":0.4,"resetTime":"2026-10-26T14:41:30Z"},{"id":"pro-5h","remainingPercent":75}]}}"#
        let q = try #require(AntigravityQuota.usageCommand(json(camel)))
        #expect(q.buckets["gemini-weekly"]?.remaining == 0.4)
        #expect(q.buckets["pro-5h"]?.remaining == 0.75)
    }

    @Test func newestReadingWinsPerBucket() {
        let t0 = Date(timeIntervalSince1970: 1000), t1 = t0.addingTimeInterval(60)
        var q = AntigravityQuota(buckets: ["gemini-weekly": .init(id: "gemini-weekly", remaining: 0.9, resetsAt: nil, observedAt: t1)], plan: "Pro")
        q.merge(AntigravityQuota(buckets: [
            "gemini-weekly": .init(id: "gemini-weekly", remaining: 0.5, resetsAt: nil, observedAt: t0),
            "gemini-5h": .init(id: "gemini-5h", remaining: 0.7, resetsAt: nil, observedAt: t0),
        ]))
        #expect(q.buckets["gemini-weekly"]?.remaining == 0.9)
        #expect(q.buckets["gemini-5h"]?.remaining == 0.7)
        // `/usage` has no plan tier; the status line's stays.
        #expect(q.plan == "Pro")
        q.merge(AntigravityQuota(buckets: ["gemini-weekly": .init(id: "gemini-weekly", remaining: 0.2, resetsAt: nil, observedAt: t1.addingTimeInterval(1))]))
        #expect(q.buckets["gemini-weekly"]?.remaining == 0.2)
        #expect(q.rateLimits?.fetchedAt == t1.addingTimeInterval(1))
    }

    @Test func windowsPastTheirResetAreStale() {
        let now = Date()
        let old = UsageWindow(label: "Gemini 5h", used: 0.95, resetsAt: now.addingTimeInterval(-60))
        let fresh = UsageWindow(label: "Gemini 7d", used: 0.4, resetsAt: now.addingTimeInterval(3600))
        #expect(old.isStale(now: now))
        #expect(!fresh.isStale(now: now))
        #expect(!UsageWindow(label: "x", used: 0.1, resetsAt: nil).isStale(now: now))
        let limits = RateLimits(provider: .antigravity, plan: nil, windows: [old, fresh], fetchedAt: now)
        #expect(limits.mostPressured == fresh)
    }

    @Test func headerChipsIncludeAntigravity() {
        let now = Date()
        func limits(_ agent: AgentKind, _ used: Double) -> RateLimits {
            RateLimits(provider: agent, plan: nil, windows: [UsageWindow(label: "7d", used: used, resetsAt: nil)], fetchedAt: now)
        }
        let all = [limits(.claude, 0.3), limits(.codex, 0.5), limits(.antigravity, 0.82)]
        #expect(RateLimits.closestToLimit(all).map(\.provider) == [.antigravity, .codex])
    }

    @Test func headlessUsageNeedsANewEnoughAgy() {
        #expect(AntigravityQuota.supportsHeadlessUsage(version: "1.4.3"))
        #expect(AntigravityQuota.supportsHeadlessUsage(version: "agy 1.1.11\n"))
        #expect(AntigravityQuota.supportsHeadlessUsage(version: "2.0.0"))
        #expect(!AntigravityQuota.supportsHeadlessUsage(version: "1.1.10"))
        #expect(!AntigravityQuota.supportsHeadlessUsage(version: "1.0.13"))
        #expect(!AntigravityQuota.supportsHeadlessUsage(version: "unknown"))
    }

    @Test func engineIgnoresStatusLineRelays() throws {
        var engine = SessionEngine()
        var payload = try json(documentedStatusLine).object!
        payload["hook_event_name"] = .string(AntigravityStatusLine.eventName)
        let out = engine.handle(BridgeEnvelope(source: "antigravity", payload: .object(payload)))
        #expect(out.sessionKey == nil)
        #expect(engine.sessions.isEmpty)
    }
}

struct StatusLineInstallerTests {
    final class Home {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orby-sl-\(UUID().uuidString)")
        var settings: URL { StatusLineInstaller.settingsURL(home: root) }
        var backups: URL { root.appendingPathComponent("backups") }
        var state: URL { root.appendingPathComponent(".orby") }
        var saved: URL { StatusLineInstaller.savedURL(stateDir: state) }

        init(settings json: String?) throws {
            try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let json { try Data(json.utf8).write(to: settings) }
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        @discardableResult
        func apply(_ install: Bool) throws -> URL? {
            try StatusLineInstaller.apply(install: install, home: root, backupDir: backups, stateDir: state)
        }
        func read() throws -> JSONValue { try JSONValue.decode(Data(contentsOf: settings)) }
        var backupCount: Int { (try? FileManager.default.contentsOfDirectory(atPath: backups.path).count) ?? 0 }
    }

    static let userSettings = #"{"model":"Gemini 3.8 Flash (Medium)","permissions":{"allow":["command(ls)"]},"trustedWorkspaces":["/Users/me"]}"#

    @Test func installWithoutAnExistingStatusLine() throws {
        let home = try Home(settings: Self.userSettings)
        #expect(StatusLineInstaller.status(home: home.root) == .notInstalled)
        let backup = try #require(try home.apply(true))
        #expect(try Data(contentsOf: backup) == Data(Self.userSettings.utf8))
        let root = try home.read()
        #expect(root["model"]?.string == "Gemini 3.8 Flash (Medium)")
        #expect(root["trustedWorkspaces"] == ["/Users/me"])
        #expect(root["statusLine"]?["type"]?.string == "command")
        let command = try #require(root["statusLine"]?["command"]?.string)
        #expect(command.contains("orby-bridge\" --statusline --source antigravity"))
        #expect(!command.contains("--wrap"))
        #expect(StatusLineInstaller.status(home: home.root) == .installed)
        #expect(!FileManager.default.fileExists(atPath: home.saved.path))

        // Idempotent: nothing to change, no new backup.
        #expect(try home.apply(true) == nil)
        #expect(home.backupCount == 1)

        try home.apply(false)
        let restored = try home.read()
        #expect(restored["statusLine"] == nil)
        #expect(restored == (try JSONValue.decode(Data(Self.userSettings.utf8))))
        #expect(try home.apply(false) == nil)
    }

    @Test func wrapsAndRestoresTheUsersStatusLine() throws {
        let mine: JSONValue = ["type": "command", "command": "~/bin/it's-mine.sh --flag", "padding": 1, "stack_with_default": true]
        var settings = try JSONValue.decode(Data(Self.userSettings.utf8)).object!
        settings["statusLine"] = mine
        let home = try Home(settings: String(decoding: try JSONValue.object(settings).encoded(), as: UTF8.self))

        try home.apply(true)
        let line = try #require(try home.read()["statusLine"])
        #expect(StatusLineInstaller.isOurs(line))
        #expect(line["padding"] == 1)
        #expect(line["stack_with_default"] == true)
        let command = try #require(line["command"]?.string)
        #expect(StatusLineInstaller.wrappedCommand(in: command) == "~/bin/it's-mine.sh --flag")
        #expect(try JSONValue.decode(Data(contentsOf: home.saved))["statusLine"] == mine)

        // Reinstalling keeps wrapping the user's command, not ours.
        #expect(try home.apply(true) == nil)
        #expect(try JSONValue.decode(Data(contentsOf: home.saved))["statusLine"] == mine)

        try home.apply(false)
        #expect(try home.read()["statusLine"] == mine)
        #expect(try home.read() == .object(settings))
        #expect(!FileManager.default.fileExists(atPath: home.saved.path))
    }

    @Test func restoresFromTheCommandWhenTheSavedCopyIsGone() throws {
        let home = try Home(settings: #"{"statusLine":{"type":"command","command":"echo hi"}}"#)
        try home.apply(true)
        try FileManager.default.removeItem(at: home.saved)
        // Still wraps after a reinstall, and uninstall still puts it back.
        try home.apply(true)
        #expect(StatusLineInstaller.wrappedCommand(in: try home.read()["statusLine"]?["command"]?.string ?? "") == "echo hi")
        try FileManager.default.removeItem(at: home.saved)
        try home.apply(false)
        #expect(try home.read()["statusLine"] == ["type": "command", "command": "echo hi"])
    }

    @Test func disabledStatusLineIsNotRunButComesBack() throws {
        let mine: JSONValue = ["type": "command", "command": "~/sl.sh", "enabled": false]
        let home = try Home(settings: String(decoding: try JSONValue.object(["statusLine": mine]).encoded(), as: UTF8.self))
        try home.apply(true)
        let line = try #require(try home.read()["statusLine"])
        #expect(line["enabled"] == nil)
        let command = line["command"]?.string ?? ""
        #expect(!command.contains("--wrap"))
        try home.apply(false)
        #expect(try home.read()["statusLine"] == mine)
    }

    @Test func leavesAStatusLineTheUserChangedSinceAlone() throws {
        let home = try Home(settings: "{}")
        try home.apply(true)
        let theirs: JSONValue = ["statusLine": ["type": "command", "command": "starship"]]
        try theirs.encoded().write(to: home.settings)
        #expect(try home.apply(false) == nil)
        #expect(try home.read() == theirs)
    }

    @Test func missingSettingsFileAndLegacyAndInvalidJSON() throws {
        let fresh = try Home(settings: nil)
        #expect(try fresh.apply(true) == nil)  // nothing to back up
        #expect(StatusLineInstaller.status(home: fresh.root) == .installed)

        let legacy = try Home(settings: #"{"statusLine":{"type":"command","command":"$HOME/.notchisland/bin/notchisland-bridge --statusline"}}"#)
        try legacy.apply(true)
        let upgraded = try legacy.read()["statusLine"]?["command"]?.string ?? ""
        #expect(upgraded.contains("orby-bridge") && !upgraded.contains("notchisland"))
        #expect(!FileManager.default.fileExists(atPath: legacy.saved.path))

        let broken = try Home(settings: "{ not json")
        #expect(throws: HookInstaller.InstallError.self) { try broken.apply(true) }
        #expect(try String(contentsOf: broken.settings, encoding: .utf8) == "{ not json")
        if case .unreadable = StatusLineInstaller.status(home: broken.root) {} else { Issue.record("expected unreadable") }

        let none = FileManager.default.temporaryDirectory.appendingPathComponent("orby-sl-none-\(UUID().uuidString)")
        #expect(StatusLineInstaller.status(home: none) == .agentMissing)
    }

    @Test func commandFallsBackWhenTheBridgeIsGone() throws {
        let tmp = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        #expect(try runShell(StatusLineInstaller.command(wrapping: nil), home: tmp, stdin: "{}") == "")
        #expect(try runShell(StatusLineInstaller.command(wrapping: "cat; echo \" it's mine\""), home: tmp, stdin: "in") == "in it's mine\n")
    }
}

/// Runs a status line command the way agy does: through a shell, payload on stdin.
func runShell(_ command: String, home: String, stdin: String) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", command]
    p.environment = ["HOME": home, "ORBY_HOME": home + "/.orby", "PATH": "/usr/bin:/bin"]
    let inPipe = Pipe(), outPipe = Pipe()
    p.standardInput = inPipe
    p.standardOutput = outPipe
    try p.run()
    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
    try inPipe.fileHandleForWriting.close()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    #expect(p.terminationStatus == 0)
    return String(decoding: out, as: UTF8.self)
}

@Suite(.serialized) struct StatusLineBridgeTests {
    static var ready: Bool { BridgeEndToEndTests.bridgePath != nil }

    /// A temp home with the bridge where the installed command looks for it.
    final class Harness: @unchecked Sendable {
        let home = "/tmp/ni-\(UUID().uuidString.prefix(8))"
        let received = Locked<[BridgeEnvelope]>([])
        var server: SocketServer?

        init(appRunning: Bool) throws {
            let bin = home + "/.orby/bin"
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: bin + "/orby-bridge", withDestinationPath: BridgeEndToEndTests.bridgePath!)
            guard appRunning else { return }
            let received = received
            server = SocketServer(path: home + "/.orby/run/app.sock") { env, _ in received.mutate { $0.append(env) } }
            try server?.start()
        }
        deinit {
            server?.stop()
            try? FileManager.default.removeItem(atPath: home)
        }

        func waitForRelay() -> BridgeEnvelope? {
            for _ in 0..<40 where received.value.isEmpty { usleep(25_000) }
            return received.value.first
        }
    }

    @Test(.enabled(if: ready)) func relaysAndPrintsItsOwnLine() throws {
        let h = try Harness(appRunning: true)
        let out = try runShell(StatusLineInstaller.command(wrapping: nil), home: h.home, stdin: documentedStatusLine)
        #expect(out == "Gemini 3.5 Flash (High) · Gemini 7d 94% left\n")
        let env = try #require(h.waitForRelay())
        #expect(env.source == "antigravity")
        #expect(env.eventName == AntigravityStatusLine.eventName)
        #expect(!env.expectsReply)
        #expect(AntigravityQuota.statusLine(env.payload)?.plan == "Pro")
    }

    @Test(.enabled(if: ready)) func runsTheWrappedCommandWithTheSameInput() throws {
        let h = try Harness(appRunning: true)
        let wrapped = #"cat > "$HOME/got.json"; printf '%s\n' "user's line""#
        let out = try runShell(StatusLineInstaller.command(wrapping: wrapped), home: h.home, stdin: documentedStatusLine)
        #expect(out == "user's line\n")
        #expect(try String(contentsOfFile: h.home + "/got.json", encoding: .utf8) == documentedStatusLine)
        #expect(h.waitForRelay() != nil)
    }

    @Test(.enabled(if: ready)) func silentRelayWhenTheAppIsNotRunning() throws {
        let h = try Harness(appRunning: false)
        let start = Date()
        #expect(try runShell(StatusLineInstaller.command(wrapping: nil), home: h.home, stdin: documentedStatusLine).hasPrefix("Gemini 3.5"))
        // A wrapped command that ignores its input still works.
        #expect(try runShell(StatusLineInstaller.command(wrapping: "echo mine"), home: h.home, stdin: documentedStatusLine) == "mine\n")
        #expect(try runShell(StatusLineInstaller.command(wrapping: nil), home: h.home, stdin: "not json") == "")
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
