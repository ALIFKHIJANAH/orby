import Foundation
import NotchCore
import NotchShared

/// Tails Antigravity CLI's logs for permission prompts, which no hook reports.
/// One CLI process writes one `cli-<timestamp>.log`; only appended bytes are read.
@MainActor
final class AntigravityLogWatcher {
    private let directory: URL
    private let onEvent: (AntigravityLog.Event, String) -> Void
    private var offsets: [String: UInt64] = [:]
    private var partial: [String: String] = [:]
    private var timer: Timer?
    private var started = false
    /// Logs touched in the last 15 minutes. The folder holds hundreds of old logs (agy writes one
    /// per run), so it is only re-listed when it changes or every 30 s, not on every tick.
    private var recent: [URL] = []
    private var listedStamp: Date?
    private var listedAt = Date.distantPast

    init(
        directory: URL = NotchPaths.homeDirectory.appendingPathComponent(".gemini/antigravity-cli/log"),
        onEvent: @escaping (AntigravityLog.Event, String) -> Void
    ) {
        self.directory = directory
        self.onEvent = onEvent
    }

    func start() {
        guard timer == nil else { return }
        guard FileManager.default.fileExists(atPath: directory.path) else {
            // Antigravity hasn't run here: check back now and then instead of polling twice a
            // second. Every log that shows up later is new, so read it from the top.
            started = true
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
                MainActor.assumeIsolated { [weak self] in
                    self?.timer = nil
                    self?.start()
                }
            }
            timer?.tolerance = 5
            return
        }
        poll()
        started = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.poll() }
        }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func relistIfNeeded(cutoff: Date) {
        let stamp = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard stamp != listedStamp || Date().timeIntervalSince(listedAt) > 30 else { return }
        listedStamp = stamp
        listedAt = Date()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        recent = files.filter {
            $0.lastPathComponent.hasPrefix("cli-") && $0.pathExtension == "log"
                && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) >= cutoff
        }
    }

    private func poll() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let cutoff = Date().addingTimeInterval(-15 * 60)
        relistIfNeeded(cutoff: cutoff)
        for url in recent {
            // Fresh stat: cached URL resource values would hide the file growing.
            var url = url
            url.removeAllCachedResourceValues()
            let values = try? url.resourceValues(forKeys: keys)
            guard (values?.contentModificationDate ?? .distantPast) >= cutoff else { continue }
            let size = UInt64(values?.fileSize ?? 0)
            let name = url.lastPathComponent
            guard let offset = offsets[name] else {
                // Logs already there at launch hold history; only new logs are read from the top.
                offsets[name] = started ? 0 : size
                if started { read(url, name: name, from: 0, to: size) }
                continue
            }
            if size < offset { offsets[name] = 0 }  // rotated or truncated
            if size > (offsets[name] ?? 0) { read(url, name: name, from: offsets[name] ?? 0, to: size) }
        }
    }

    private func read(_ url: URL, name: String, from start: UInt64, to end: UInt64) {
        guard end > start, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.read(upToCount: Int(end - start)), !data.isEmpty else { return }
        offsets[name] = start + UInt64(data.count)
        let text = (partial[name] ?? "") + String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        // Keep an unfinished last line until the rest of it is written.
        partial[name] = lines.removeLast()
        let logID = (name as NSString).deletingPathExtension
        for line in lines {
            if let event = AntigravityLog.parse(line) { onEvent(event, logID) }
        }
    }
}
