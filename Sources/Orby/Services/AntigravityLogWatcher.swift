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

    init(
        directory: URL = NotchPaths.homeDirectory.appendingPathComponent(".gemini/antigravity-cli/log"),
        onEvent: @escaping (AntigravityLog.Event, String) -> Void
    ) {
        self.directory = directory
        self.onEvent = onEvent
    }

    func start() {
        guard timer == nil else { return }
        poll()
        started = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let cutoff = Date().addingTimeInterval(-15 * 60)
        for url in files where url.lastPathComponent.hasPrefix("cli-") && url.pathExtension == "log" {
            let values = try? url.resourceValues(forKeys: Set(keys))
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
