import Foundation
import NotchCore
import NotchShared

/// One line per blocked request's lifecycle in ~/.orby/logs/requests.log, so a
/// "my click did nothing" report can be matched against what the app actually did.
enum RequestLog {
    private static let queue = DispatchQueue(label: "orby.requestlog")
    private static let maxBytes = 1_000_000
    private static var url: URL { NotchPaths.root.appendingPathComponent("logs/requests.log") }
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func write(_ step: String, id: String, session: String? = nil, tool: String? = nil, pid: Int32? = nil) {
        let fields = [
            formatter.string(from: Date()), step, "id=\(UUID(uuidString: id) != nil ? String(id.prefix(8)) : id)",
            session.map { "session=\($0)" },
            tool.map { "tool=\($0)" }, pid.map { "pid=\($0)" },
        ].compactMap { $0 }
        let line = fields.joined(separator: " ") + "\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = url.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    /// Why the engine let go of a request, named after the event that settled it.
    static func releaseReason(for event: String) -> String {
        switch event {
        case "PermissionRequest": "superseded"
        case "PreToolUse": "tool-started"
        case "PostToolUse", "PostToolUseFailure": "tool-finished"
        case "UserPromptSubmit": "new-prompt"
        case "Stop", "Interrupt", "StopFailure": "stop"
        case "SessionEnd": "session-end"
        default: event
        }
    }

    static func label(_ decision: PermissionDecision) -> String {
        switch decision {
        case .allow(let input, let rules):
            "allow" + (input != nil ? "+input" : "") + (rules != nil ? "+permissions" : "")
        case .deny: "deny"
        case .passthrough: "terminal"
        }
    }
}
