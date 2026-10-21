import Foundation
import SQLite3
import Testing

@testable import NotchCore
@testable import NotchShared

/// A throwaway home directory with agent data laid out like the real thing.
private struct TempHome {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("orby-usage-\(UUID().uuidString)")

    @discardableResult
    func write(_ path: String, _ lines: [String]) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: file)
        return file
    }

    func append(_ path: String, _ text: String) throws {
        let h = try FileHandle(forWritingTo: url.appendingPathComponent(path))
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    func sqlite(_ path: String, _ sql: String) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        #expect(rc == SQLITE_OK, "\(err.map { String(cString: $0) } ?? "")")
        return file
    }

    /// Bumps a file's mtime so the index sees a change even within one clock tick.
    func touch(_ file: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

private let now = Date()
private func iso(_ secondsAgo: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo)) }
private func daysAgo(_ n: Int) -> String { TokenHistory.dayKey(Calendar.current.date(byAdding: .day, value: -n, to: now)!) }
private func tokens(_ r: UsageScanner.Result, _ agent: AgentKind) -> Int {
    r.history.days.values.reduce(0) { $0 + ($1[agent] ?? 0) }
}

/// Minimal protobuf writer for Antigravity fixtures.
private func pbVarint(_ value: UInt64) -> [UInt8] {
    var v = value
    var out: [UInt8] = []
    repeat {
        var byte = UInt8(v & 0x7f)
        v >>= 7
        if v != 0 { byte |= 0x80 }
        out.append(byte)
    } while v != 0
    return out
}
private func pb(_ field: Int, _ value: UInt64) -> [UInt8] { pbVarint(UInt64(field << 3)) + pbVarint(value) }
private func pb(_ field: Int, _ bytes: [UInt8]) -> [UInt8] { pbVarint(UInt64(field << 3 | 2)) + pbVarint(UInt64(bytes.count)) + bytes }
private func pb(_ field: Int, _ string: String) -> [UInt8] { pb(field, Array(string.utf8)) }
private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// One `steps.metadata` blob shaped like the research sample.
private func antigravityStep(created: Date, input: UInt64, output: UInt64, cacheRead: UInt64 = 0, response: String) -> [UInt8] {
    let seconds = UInt64(created.timeIntervalSince1970)
    let usage = pb(1, 1319) + pb(2, input) + pb(3, output) + pb(5, cacheRead) + pb(6, 24) + pb(7, "bot-\(response)")
        + pb(9, output / 2) + pb(10, output - output / 2) + pb(11, response)
    return pb(1, pb(1, seconds) + pb(2, 570_699_000)) + pb(9, usage) + pb(11, 1319) + pb(12, "step-uuid")
}

@Suite struct UsageParserTests {
    @Test func claudeKeepsLargestOutputPerMessageAcrossFiles() throws {
        let home = TempHome()
        defer { home.remove() }
        func line(_ id: String, input: Int, output: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(iso(60))","requestId":"req_\#(id)","message":{"id":"msg_\#(id)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        }
        // Streaming repeats usage per content block; output grows from 8 to 500.
        try home.write(".claude/projects/p/a.jsonl", [line("1", input: 100, output: 8), line("1", input: 100, output: 500)])
        try home.write(".claude/projects/p/b.jsonl", [line("1", input: 100, output: 500), line("2", input: 5, output: 10)])
        #expect(tokens(UsageScanner.scan(home: home.url, now: now), .claude) == 615)
    }

    @Test func codexSkipsRepeatedTokenCountEvents() throws {
        let home = TempHome()
        defer { home.remove() }
        func event(last: Int?, total: Int) -> String {
            let lastJSON = last.map { #""last_token_usage":{"total_tokens":\#($0)},"# } ?? ""
            return #"{"timestamp":"\#(iso(60))","type":"event_msg","payload":{"type":"token_count","info":{\#(lastJSON)"total_token_usage":{"total_tokens":\#(total)}}}}"#
        }
        try home.write(".codex/sessions/2026/10/21/rollout-a.jsonl", [
            event(last: 100, total: 100),
            event(last: 100, total: 100),  // duplicate: totals didn't move
            event(last: 150, total: 250),
            event(last: nil, total: 300),  // no per-turn usage: fall back to the delta
        ])
        #expect(tokens(UsageScanner.scan(home: home.url, now: now), .codex) == 300)
    }

    @Test func qwenCountsAssistantRecordsOnly() throws {
        let home = TempHome()
        defer { home.remove() }
        let usage = #""usageMetadata":{"promptTokenCount":1200,"candidatesTokenCount":80,"cachedContentTokenCount":1000,"thoughtsTokenCount":20,"totalTokenCount":1300}"#
        try home.write(".qwen/projects/-Users-me-proj/chats/s1.jsonl", [
            #"{"uuid":"u1","parentUuid":null,"sessionId":"s1","timestamp":"\#(iso(90))","type":"user","message":{"role":"user"}}"#,
            #"{"uuid":"u2","parentUuid":"u1","sessionId":"s1","timestamp":"\#(iso(80))","type":"assistant","model":"qwen3-coder-plus",\#(usage)}"#,
            #"{"uuid":"u3","parentUuid":"u2","sessionId":"s1","timestamp":"\#(iso(80))","type":"system","subtype":"ui_telemetry",\#(usage)}"#,
        ])
        #expect(tokens(UsageScanner.scan(home: home.url, now: now), .qwen) == 1300)

        let fallback = UsageScanner.qwenUsage(
            line: #"{"uuid":"u9","timestamp":"\#(iso(1))","type":"assistant","usageMetadata":{"promptTokenCount":40,"candidatesTokenCount":2,"thoughtsTokenCount":3}}"#)
        #expect(fallback?.tokens == 45)
    }

    @Test func piDedupesForkedEntries() throws {
        let home = TempHome()
        defer { home.remove() }
        let header = #"{"type":"session","version":3,"id":"s1","timestamp":"\#(iso(100))","cwd":"/Users/me/proj"}"#
        let e1 = #"{"type":"message","id":"e1","parentId":null,"timestamp":"\#(iso(90))","message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-5-5","usage":{"input":300,"output":50,"cacheRead":2000,"cacheWrite":100,"reasoning":20,"totalTokens":2450}}}"#
        let e2 = #"{"type":"message","id":"e2","parentId":"e1","timestamp":"\#(iso(80))","message":{"role":"assistant","usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0}}}"#
        let user = #"{"type":"message","id":"e0","parentId":null,"timestamp":"\#(iso(95))","message":{"role":"user","content":"hi"}}"#
        try home.write(".pi/agent/sessions/--Users-me-proj--/2026-10-21T10-00-00_s1.jsonl", [header, user, e1])
        // `/fork` copies e1 with its original id into the new file.
        try home.write(".pi/agent/sessions/--Users-me-proj--/2026-10-21T10-05-00_s2.jsonl", [header, e1, e2])
        #expect(tokens(UsageScanner.scan(home: home.url, now: now), .pi) == 2465)
    }

    @Test func commandCodeIgnoresSidecars() throws {
        let home = TempHome()
        defer { home.remove() }
        let assistant = #"{"type":"message","id":"m2","parentId":"m1","timestamp":"\#(iso(60))","model":"anthropic/claude-sonnet-5-5","message":{"role":"assistant"},"usage":{"inputTokens":400,"outputTokens":60,"cacheReadTokens":3000,"cacheWriteTokens":200,"costUsd":0.01}}"#
        try home.write(".commandcode/projects/users-me-proj/0b1c.jsonl", [
            #"{"type":"session","version":3,"id":"0b1c","timestamp":"\#(iso(100))","cwd":"/Users/me/proj"}"#,
            #"{"type":"message","id":"m1","parentId":null,"timestamp":"\#(iso(70))","message":{"role":"user","content":"hi"}}"#,
            assistant,
        ])
        try home.write(".commandcode/projects/users-me-proj/0b1c.checkpoints.jsonl", [assistant])
        #expect(tokens(UsageScanner.scan(home: home.url, now: now), .commandcode) == 3660)
    }

    @Test func protoReaderDecodesResearchSample() throws {
        let created = Date(timeIntervalSince1970: 1_792_534_779)
        let step = antigravityStep(created: created, input: 26726, output: 160, response: "resp-1")
        let r = try #require(UsageDatabases.antigravityUsage(step: Data(step), fallbackKey: "c:1"))
        #expect(r.tokens == 26886)
        #expect(r.key == "antigravity:resp-1")
        #expect(abs(r.date.timeIntervalSince1970 - 1_792_534_779.57) < 0.01)
        // A step without usage (field 9) is not a record; garbage is rejected.
        #expect(UsageDatabases.antigravityUsage(step: Data(pb(1, pb(1, 1)) + pb(11, 1319)), fallbackKey: "c:2") == nil)
        #expect(ProtoMessage(Data([0x0a, 0x05, 0x01])) == nil)
    }
}

@Suite struct UsageIndexTests {
    @Test func appendedLinesAreReadFromTheLastOffset() throws {
        let home = TempHome()
        defer { home.remove() }
        func line(_ id: String, _ input: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(iso(60))","message":{"id":"\#(id)","usage":{"input_tokens":\#(input),"output_tokens":0}}}"#
        }
        let path = ".claude/projects/p/s.jsonl"
        let file = try home.write(path, [line("a", 100)])
        let index = UsageIndex()
        #expect(tokens(index.refresh(home: home.url, now: now), .claude) == 100)

        // Corrupt the first line in place (same length) and append: only the tail is parsed,
        // so the cached record survives. A full re-parse would have dropped it.
        let h = try FileHandle(forWritingTo: file)
        try h.write(contentsOf: Data(String(repeating: "x", count: line("a", 100).utf8.count).utf8))
        try h.close()
        let second = line("b", 20)
        try home.append(path, String(second.dropLast(5)))  // still being written
        #expect(tokens(index.refresh(home: home.url, now: now), .claude) == 100)
        try home.append(path, String(second.suffix(5)) + "\n")
        #expect(tokens(index.refresh(home: home.url, now: now), .claude) == 120)

        // Shrunk: start over from the top.
        try home.write(path, [line("c", 7)])
        #expect(tokens(index.refresh(home: home.url, now: now), .claude) == 7)
    }

    @Test func openCodeReadsAssistantMessagesIncrementallyWithoutWriting() throws {
        let home = TempHome()
        defer { home.remove() }
        let ms = { (secondsAgo: Double) in Int64(now.addingTimeInterval(-secondsAgo).timeIntervalSince1970 * 1000) }
        func data(_ role: String, input: Int, output: Int, reasoning: Int, read: Int, write: Int) -> String {
            #"{"role":"\#(role)","modelID":"gpt-5.6-sol","providerID":"openai","tokens":{"total":0,"input":\#(input),"output":\#(output),"reasoning":\#(reasoning),"cache":{"write":\#(write),"read":\#(read)}}}"#
        }
        let db = try home.sqlite(".local/share/opencode/opencode.db", """
            CREATE TABLE message(id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
            INSERT INTO message VALUES('m1','s1',\(ms(300)),\(ms(300)),'\(data("assistant", input: 464, output: 100, reasoning: 85, read: 110208, write: 0))');
            INSERT INTO message VALUES('m2','s1',\(ms(200)),\(ms(200)),'{"role":"user"}');
            INSERT INTO message VALUES('m3','s1',\(ms(40 * 86400)),\(ms(40 * 86400)),'\(data("assistant", input: 9, output: 9, reasoning: 0, read: 0, write: 0))');
            """)
        let before = try FileManager.default.attributesOfItem(atPath: db.path)[.modificationDate] as? Date
        let index = UsageIndex()
        #expect(tokens(index.refresh(home: home.url, now: now), .opencode) == 110_857)
        #expect(try FileManager.default.attributesOfItem(atPath: db.path)[.modificationDate] as? Date == before)
        #expect(!FileManager.default.fileExists(atPath: db.path + "-journal"))

        // A streaming turn updates its row in place; a new turn adds one.
        _ = try home.sqlite(".local/share/opencode/opencode.db", """
            UPDATE message SET time_updated = \(ms(10)), data = '\(data("assistant", input: 464, output: 300, reasoning: 85, read: 110208, write: 0))' WHERE id = 'm1';
            INSERT INTO message VALUES('m4','s2',\(ms(5)),\(ms(5)),'\(data("assistant", input: 10, output: 1, reasoning: 0, read: 0, write: 4))');
            """)
        try home.touch(db, now.addingTimeInterval(5))
        #expect(tokens(index.refresh(home: home.url, now: now), .opencode) == 111_057 + 15)
    }

    @Test func antigravityDedupesAcrossCliAndAppFolders() throws {
        let home = TempHome()
        defer { home.remove() }
        let a = antigravityStep(created: now.addingTimeInterval(-120), input: 1000, output: 50, cacheRead: 200, response: "r1")
        let b = antigravityStep(created: now.addingTimeInterval(-60), input: 300, output: 20, response: "r2")
        let schema = "CREATE TABLE steps(idx INTEGER PRIMARY KEY, step_type INTEGER, status INTEGER, metadata BLOB);"
        _ = try home.sqlite(".gemini/antigravity-cli/conversations/c1.db", schema + """
            INSERT INTO steps VALUES(0, 1, 1, NULL);
            INSERT INTO steps VALUES(1, 2, 1, X'\(hex(a))');
            INSERT INTO steps VALUES(2, 2, 1, X'\(hex(b))');
            """)
        // The app folder holds the same conversation; summaries carry no usage.
        _ = try home.sqlite(".gemini/antigravity/conversations/c1.db", schema + "INSERT INTO steps VALUES(1, 2, 1, X'\(hex(a))');")
        _ = try home.sqlite(".gemini/antigravity-cli/conversations/conversation_summaries.db", "CREATE TABLE t(x);")
        #expect(tokens(UsageScanner.scan(home: home.url, now: now), .antigravity) == 1250 + 320)
    }
}

@Suite struct TokenHistoryTests {
    @Test func agentTotalsListOnlyAgentsWithUsageMostFirst() {
        var h = TokenHistory()
        let agents = AgentKind.allCases.filter { $0 != .unknown && $0 != .cursor }
        for (rank, agent) in agents.enumerated() {
            for day in 0..<7 {
                h.add(day: daysAgo(day), agent: agent, tokens: (rank + 1) * 1000)
            }
        }
        // Outside the window, and a zero entry: neither is listed.
        h.add(day: daysAgo(9), agent: .cursor, tokens: 5_000_000)
        h.add(day: TokenHistory.dayKey(now), agent: .unknown, tokens: 0)

        let totals = h.agentTotals(lastDays: 7, now: now)
        #expect(totals.map(\.agent) == agents.reversed())
        #expect(totals.first?.tokens == agents.count * 7000)
        #expect(totals.reduce(0) { $0 + $1.tokens } == h.lastDays(7, now: now).reduce(0) { $0 + h.total(day: $1.day) })
        #expect(h.agentTotals(lastDays: 10, now: now).first?.agent == .cursor)

        var tie = TokenHistory()
        tie.add(day: TokenHistory.dayKey(now), agent: .qwen, tokens: 10)
        tie.add(day: TokenHistory.dayKey(now), agent: .codex, tokens: 10)
        #expect(tie.agentTotals(lastDays: 1, now: now).map(\.agent) == [.codex, .qwen])
    }

    @Test func headerShowsTheTwoProvidersClosestToALimit() {
        func limits(_ agent: AgentKind, _ used: [Double]) -> RateLimits {
            RateLimits(provider: agent, plan: nil, windows: used.map { UsageWindow(label: "\($0)", used: $0, resetsAt: nil) }, fetchedAt: now)
        }
        let all = [limits(.claude, [0.2, 0.5]), limits(.codex, [0.91]), limits(.antigravity, []), limits(.opencode, [0.7, 0.1])]
        #expect(RateLimits.closestToLimit(all).map(\.provider) == [.codex, .opencode])
        #expect(RateLimits.closestToLimit([limits(.claude, [0.3])]).map(\.provider) == [.claude])
    }

    @Test func headerShowsPickedWindowsInOrder() {
        let all = [
            RateLimits(provider: .claude, plan: nil, windows: [UsageWindow(label: "5h", used: 0.2, resetsAt: nil)], fetchedAt: now),
            RateLimits(
                provider: .antigravity, plan: nil,
                windows: [UsageWindow(label: "Gemini 7d", used: 0.1, resetsAt: nil), UsageWindow(label: "Claude/GPT 7d", used: 0.8, resetsAt: nil)],
                fetchedAt: now),
        ]
        let picked = [RateLimits.windowID(.claude, "5h"), RateLimits.windowID(.codex, "7d"), RateLimits.windowID(.antigravity, "Gemini 7d")]
        let shown = RateLimits.headerWindows(all, picked: picked)
        // Codex has no data yet, so it's skipped; the low Gemini window still shows because it was picked.
        #expect(shown.map { "\($0.agent.rawValue) \($0.window.label)" } == ["claude 5h", "antigravity Gemini 7d"])
        #expect(RateLimits.headerWindows(all).map(\.window.label) == ["Claude/GPT 7d", "5h"])
    }
}
