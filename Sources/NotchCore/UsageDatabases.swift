import Foundation
import NotchShared
import SQLite3

/// Token counts that OpenCode and Antigravity keep in SQLite. Each database is opened read-only
/// for one query and closed again, so nothing is written and the agent's writer is never blocked.
/// Not thread-safe: owned by `UsageIndex`.
final class UsageDatabases {
    /// The main file's mtime can stay put while the WAL grows, so both are part of the stamp.
    struct Stamp: Equatable {
        var inode: Int
        var size: Int
        var mtime: Date
        var walSize: Int
        var walMtime: Date?
    }

    private struct OpenCodeState {
        var stamp: Stamp
        /// Highest `time_updated` read so far (epoch ms); later reads only ask for newer rows.
        var watermark: Int64 = 0
        var messages: [String: UsageRecord] = [:]
    }

    private var openCode: [String: OpenCodeState] = [:]
    private var antigravity: [String: (stamp: Stamp, records: [UsageRecord])] = [:]
    /// Whether the last `refresh` read or dropped anything.
    private(set) var changed = false

    func refresh(home: URL, cutoff: Date) -> [UsageRecord] {
        changed = false
        return refreshOpenCode(home: home, cutoff: cutoff) + refreshAntigravity(home: home, cutoff: cutoff)
    }

    static func stamp(_ url: URL) -> Stamp? {
        guard let db = UsageScanner.fileInfo(url) else { return nil }
        let wal = UsageScanner.fileInfo(URL(fileURLWithPath: url.path + "-wal"))
        return Stamp(inode: db.inode, size: db.size, mtime: db.mtime, walSize: wal?.size ?? 0, walMtime: wal?.mtime)
    }

    // MARK: OpenCode

    /// `opencode.db`, plus `opencode-<channel>.db` for other release channels.
    static func openCodeDatabases(home: URL) -> [URL] {
        let dir = home.appendingPathComponent(".local/share/opencode")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0 == "opencode.db" || ($0.hasPrefix("opencode-") && $0.hasSuffix(".db")) }
            .sorted().map { dir.appendingPathComponent($0) }
    }

    /// Assistant messages only: the `event` table repeats every streaming update and `part`
    /// duplicates per-step usage. Buckets are disjoint, so the sum is everything processed.
    static let openCodeQuery = """
        SELECT id, time_created, time_updated,
               json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'),
               json_extract(data, '$.tokens.reasoning'), json_extract(data, '$.tokens.cache.read'),
               json_extract(data, '$.tokens.cache.write')
        FROM message
        WHERE time_updated >= ?1 AND time_created >= ?2 AND json_extract(data, '$.role') = 'assistant'
        """

    private func refreshOpenCode(home: URL, cutoff: Date) -> [UsageRecord] {
        var live = Set<String>()
        for url in Self.openCodeDatabases(home: home) {
            live.insert(url.path)
            guard let stamp = Self.stamp(url) else { continue }
            var state = openCode[url.path]
            if state?.stamp == stamp { continue }
            if state?.stamp.inode != stamp.inode { state = nil }
            var next = state ?? OpenCodeState(stamp: stamp)
            guard let db = ReadOnlyDatabase(url) else { continue }
            let ok = db.query(Self.openCodeQuery, [next.watermark, Int64(cutoff.timeIntervalSince1970 * 1000)]) { row in
                guard let id = row.text(0) else { return }
                let tokens = (3...7).map { Int(row.int(Int32($0))) }.reduce(0, +)
                next.watermark = max(next.watermark, row.int(2))
                next.messages[id] = UsageRecord(
                    key: nil, date: Date(timeIntervalSince1970: Double(row.int(1)) / 1000), agent: .opencode, tokens: tokens)
            }
            // On a failed read keep the old state, so the next refresh retries.
            guard ok else { continue }
            changed = true
            next.stamp = stamp
            next.messages = next.messages.filter { $0.value.date >= cutoff && $0.value.tokens > 0 }
            openCode[url.path] = next
        }
        if openCode.keys.contains(where: { !live.contains($0) }) {
            openCode = openCode.filter { live.contains($0.key) }
            changed = true
        }
        return openCode.values.flatMap(\.messages.values)
    }

    // MARK: Antigravity

    /// CLI and app conversations share one schema; the IDE's older `.pb` files are encrypted.
    static let antigravityFolders = [
        ".gemini/antigravity-cli/conversations", ".gemini/antigravity/conversations", ".gemini/antigravity-ide/conversations",
    ]

    private func refreshAntigravity(home: URL, cutoff: Date) -> [UsageRecord] {
        var live = Set<String>()
        for folder in Self.antigravityFolders {
            for f in UsageScanner.files(under: home.appendingPathComponent(folder), ext: "db", modifiedAfter: cutoff)
            where f.url.lastPathComponent != "conversation_summaries.db" {
                live.insert(f.url.path)
                guard let stamp = Self.stamp(f.url), antigravity[f.url.path]?.stamp != stamp,
                    let records = Self.readAntigravity(f.url)
                else { continue }
                antigravity[f.url.path] = (stamp, records)
                changed = true
            }
        }
        if antigravity.keys.contains(where: { !live.contains($0) }) {
            antigravity = antigravity.filter { live.contains($0.key) }
            changed = true
        }
        return antigravity.values.flatMap(\.records)
    }

    /// One record per step that carries usage. `steps.metadata` (protobuf): 1 = created
    /// Timestamp, 9 = usage {2 input, 3 output (thinking + visible), 4 cache write, 5 cache read,
    /// 7 message id, 11 response id}. Field map decoded locally; Google publishes no schema.
    static func readAntigravity(_ url: URL) -> [UsageRecord]? {
        guard let db = ReadOnlyDatabase(url) else { return nil }
        let conversation = url.deletingPathExtension().lastPathComponent
        var records: [UsageRecord] = []
        let ok = db.query("SELECT idx, metadata FROM steps WHERE metadata IS NOT NULL") { row in
            if let r = antigravityUsage(step: row.blob(1), fallbackKey: "\(conversation):\(row.int(0))") { records.append(r) }
        }
        return ok ? records : nil
    }

    static func antigravityUsage(step metadata: Data, fallbackKey: String) -> UsageRecord? {
        guard let step = ProtoMessage(metadata), let usage = step.message(9), let created = step.message(1),
            let seconds = created.varint(1)
        else { return nil }
        let tokens = [2, 3, 4, 5].compactMap(usage.varint).reduce(0, +)
        guard tokens > 0 else { return nil }
        let date = Date(timeIntervalSince1970: Double(seconds) + Double(created.varint(2) ?? 0) / 1e9)
        // The same conversation can sit in both the CLI and app folders.
        let id = usage.string(11) ?? usage.string(7) ?? fallbackKey
        return UsageRecord(key: "antigravity:" + id, date: date, agent: .antigravity, tokens: tokens)
    }
}

/// Just enough of the protobuf wire format to pull numbered fields out of a message.
/// Repeated fields keep their first occurrence.
struct ProtoMessage {
    private var varints: [Int: UInt64] = [:]
    private var blobs: [Int: Data] = [:]

    init?(_ data: Data) {
        let b = [UInt8](data)
        var i = 0
        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while i < b.count, shift < 64 {
                let byte = b[i]
                i += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while i < b.count {
            guard let tag = varint(), tag >> 3 > 0 else { return nil }
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                guard let v = varint() else { return nil }
                if varints[field] == nil { varints[field] = v }
            case 1: i += 8
            case 2:
                guard let n = varint(), n <= UInt64(b.count - i) else { return nil }
                if blobs[field] == nil { blobs[field] = Data(b[i..<(i + Int(n))]) }
                i += Int(n)
            case 5: i += 4
            default: return nil
            }
            guard i <= b.count else { return nil }
        }
    }

    func varint(_ field: Int) -> Int? { varints[field].map { Int(truncatingIfNeeded: $0) } }
    func message(_ field: Int) -> ProtoMessage? { blobs[field].flatMap(ProtoMessage.init) }
    func string(_ field: Int) -> String? { blobs[field].flatMap { String(data: $0, encoding: .utf8) } }
}

/// A SQLite database opened read-only (`mode=ro` + `query_only`). It reads through the WAL like
/// any other reader, so the agent's latest commits are visible without copying the file.
final class ReadOnlyDatabase {
    private let handle: OpaquePointer

    /// Falls back to `immutable=1` when the WAL index can't be opened read-only; that misses
    /// writes not yet checkpointed but still never touches the file.
    init?(_ url: URL) {
        let path = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        for options in ["mode=ro", "mode=ro&immutable=1"] {
            var db: OpaquePointer?
            if sqlite3_open_v2("file:\(path)?\(options)", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
                let db
            {
                sqlite3_busy_timeout(db, 250)
                if sqlite3_exec(db, "PRAGMA query_only = 1; SELECT count(*) FROM sqlite_master", nil, nil, nil) == SQLITE_OK {
                    handle = db
                    return
                }
            }
            sqlite3_close_v2(db)
        }
        return nil
    }

    deinit { sqlite3_close_v2(handle) }

    struct Row {
        let stmt: OpaquePointer
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        func blob(_ i: Int32) -> Data {
            guard let p = sqlite3_column_blob(stmt, i) else { return Data() }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
    }

    /// Runs `sql` with integer parameters, calling `row` per result row. False on any error.
    func query(_ sql: String, _ params: [Int64] = [], row: (Row) -> Void) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), p) }
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: row(Row(stmt: stmt))
            case SQLITE_DONE: return true
            default: return false
            }
        }
    }
}
