import Foundation
import NotchShared

/// Points Antigravity CLI's `statusLine` at the bridge, which relays agy's quota to Orby.
/// Only the `statusLine` key is touched. A status line the user already had is saved to
/// ~/.orby/statusline/antigravity.json, run by the relay (so it keeps showing), and put back
/// exactly on uninstall.
public enum StatusLineInstaller {
    public static func settingsURL(home: URL = NotchPaths.homeDirectory) -> URL {
        home.appendingPathComponent(".gemini/antigravity-cli/settings.json")
    }

    public static func savedURL(stateDir: URL = NotchPaths.root) -> URL {
        stateDir.appendingPathComponent("statusline/antigravity.json")
    }

    /// Guarded like the hooks: with the bridge gone it runs the wrapped command, or prints nothing.
    public static func command(wrapping original: String?) -> String {
        let bridge = "$HOME/.orby/bin/orby-bridge"
        let run = "exec \"\(bridge)\" --statusline --source antigravity"
        guard let original, !original.isEmpty else { return "[ -x \"\(bridge)\" ] && \(run) || cat >/dev/null" }
        let quoted = shellQuote(original)
        return "[ -x \"\(bridge)\" ] && \(run) --wrap \(quoted) || sh -c \(quoted)"
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The command passed to `--wrap` in one of our status lines, read back from its shell quoting.
    static func wrappedCommand(in command: String) -> String? {
        guard let range = command.range(of: "--wrap ") else { return nil }
        var out = ""
        var rest = command[range.upperBound...]
        while rest.first == "'" || rest.hasPrefix("\\'") {
            if rest.hasPrefix("\\'") {
                out += "'"
                rest = rest.dropFirst(2)
                continue
            }
            rest = rest.dropFirst()
            guard let end = rest.firstIndex(of: "'") else { return nil }
            out += rest[..<end]
            rest = rest[rest.index(after: end)...]
        }
        return out.isEmpty ? nil : out
    }

    public static func isOurs(_ statusLine: JSONValue?) -> Bool {
        guard let command = statusLine?["command"]?.string else { return false }
        return (command.contains(HookInstaller.marker) || command.contains(HookInstaller.legacyMarker)) && command.contains("--statusline")
    }

    /// The command of a status line worth keeping on screen, if any.
    static func runnableCommand(_ statusLine: JSONValue?) -> String? {
        guard let s = statusLine, s["enabled"]?.bool != false, (s["type"]?.string ?? "command") == "command",
            let command = s["command"]?.string, !command.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return command
    }

    /// `saved` is the user's own status line from an earlier install. Returns the new settings
    /// and what to save now (nil: nothing to restore later).
    public static func installing(into root: JSONValue, saved: JSONValue?) -> (root: JSONValue, saved: JSONValue?) {
        var obj = root.object ?? [:]
        let current = obj["statusLine"]
        var original: JSONValue? = isOurs(current) ? saved : current
        // Ours, but the saved copy is gone: the wrapped command is still in ours.
        if isOurs(current), original == nil, let wrapped = current?["command"]?.string.flatMap(wrappedCommand(in:)) {
            original = ["type": "command", "command": .string(wrapped)]
        }
        // Keep the user's padding/stacking; ours has to be enabled to relay anything.
        var line = original?.object ?? [:]
        line["enabled"] = nil
        line["type"] = "command"
        line["command"] = .string(command(wrapping: runnableCommand(original)))
        obj["statusLine"] = .object(line)
        return (.object(obj), original)
    }

    public static func uninstalling(from root: JSONValue, saved: JSONValue?) -> JSONValue {
        guard var obj = root.object, isOurs(obj["statusLine"]) else { return root }
        if let saved {
            obj["statusLine"] = saved
        } else if let wrapped = obj["statusLine"]?["command"]?.string.flatMap(wrappedCommand(in:)) {
            obj["statusLine"] = ["type": "command", "command": .string(wrapped)]
        } else {
            obj["statusLine"] = nil
        }
        return .object(obj)
    }

    public static func isInstalled(in root: JSONValue) -> Bool { isOurs(root["statusLine"]) }

    public static func status(home: URL = NotchPaths.homeDirectory) -> HookInstaller.Status {
        let url = settingsURL(home: home)
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { return .agentMissing }
        guard let data = try? Data(contentsOf: url) else { return .notInstalled }
        guard let root = try? JSONValue.decode(data) else { return .unreadable("\(url.lastPathComponent) is not valid JSON") }
        return isInstalled(in: root) ? .installed : .notInstalled
    }

    /// Install or remove the relay on disk. Returns the backup of settings.json, if it changed.
    @discardableResult
    public static func apply(
        install: Bool, home: URL = NotchPaths.homeDirectory, backupDir: URL = NotchPaths.backups,
        stateDir: URL = NotchPaths.root, now: Date = Date()
    ) throws -> URL? {
        let fm = FileManager.default
        // Write through symlinks (dotfile repos) instead of replacing the link with a file.
        let url = settingsURL(home: home).resolvingSymlinksInPath()
        let savedFile = savedURL(stateDir: stateDir)
        let saved = (try? Data(contentsOf: savedFile)).flatMap { try? JSONValue.decode($0) }?["statusLine"]
        var root: JSONValue = .object([:])
        var data: Data?
        if let d = try? Data(contentsOf: url) {
            guard let parsed = try? JSONValue.decode(d) else { throw HookInstaller.InstallError.invalidJSON(url) }
            root = parsed
            data = d
        }
        let updated: JSONValue
        if install {
            let result = installing(into: root, saved: saved)
            updated = result.root
            if let original = result.saved {
                try fm.createDirectory(at: savedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONValue.object(["statusLine": original]).encoded(pretty: true).write(to: savedFile, options: .atomic)
            } else {
                try? fm.removeItem(at: savedFile)
            }
        } else {
            updated = uninstalling(from: root, saved: saved)
            if updated != root { try? fm.removeItem(at: savedFile) }
        }
        guard updated != root else { return nil }
        let backup = try data.map { try HookInstaller.backup($0, of: url, for: .antigravity, in: backupDir, now: now) }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.encoded(pretty: true).write(to: url, options: .atomic)
        return backup
    }
}
