import Foundation
import NotchShared

/// Adds/removes Orby's hook entries in an agent's hook config, leaving every
/// other tool's hooks untouched. Writes a timestamped backup before any change.
public enum HookTarget: String, CaseIterable, Sendable {
    case claude, codex, antigravity

    public var agent: AgentKind {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .antigravity: .antigravity
        }
    }

    public func configURL(home: URL = NotchPaths.homeDirectory) -> URL {
        switch self {
        case .claude:
            if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
                return URL(fileURLWithPath: dir).appendingPathComponent("settings.json")
            }
            return home.appendingPathComponent(".claude/settings.json")
        case .codex:
            return home.appendingPathComponent(".codex/hooks.json")
        case .antigravity:
            // Global hooks shared by the Antigravity app, IDE and CLI.
            return home.appendingPathComponent(".gemini/config/hooks.json")
        }
    }

    /// Directories whose existence means the agent is installed on this Mac.
    public func agentDirectories(home: URL = NotchPaths.homeDirectory) -> [URL] {
        switch self {
        case .claude, .codex: [configURL(home: home).deletingLastPathComponent()]
        case .antigravity:
            ["antigravity", "antigravity-ide", "antigravity-cli"].map { home.appendingPathComponent(".gemini/\($0)") }
        }
    }

    public var events: [String] {
        switch self {
        case .claude:
            [
                "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop",
                "PreCompact", "PostCompact",
            ]
        case .codex:
            [
                "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop",
                "SubagentStop", "PostCompact",
            ]
        case .antigravity:
            ["SessionStart", "PreInvocation", "PreToolUse", "PostToolUse", "Stop"]
        }
    }

    /// Seconds the agent waits for the hook. Permission requests block until the user decides.
    public func timeout(for event: String) -> Int {
        guard blockingEvents.contains(event) else { return 10 }
        return self == .claude ? 86400 : 7200
    }
}

public enum HookInstaller {
    public static let marker = "orby-bridge"
    /// Antigravity's hooks.json is keyed by hook name; this is ours.
    public static let antigravityHookName = "orby"
    /// Names from before the NotchIsland → Orby rename, still recognised so old hooks get replaced.
    static let legacyMarker = "notchisland-bridge"
    static let legacyAntigravityHookName = "notchisland"

    /// Guarded so a missing bridge (app deleted) is a silent no-op instead of a hook error.
    public static func command(for target: HookTarget, event: String) -> String {
        let bridge = "$HOME/.orby/bin/orby-bridge"
        guard target == .antigravity else {
            return "[ -x \"\(bridge)\" ] && exec \"\(bridge)\" --source \(target.rawValue) || true"
        }
        // Antigravity expects a reply on stdout, even when the bridge is gone.
        let fallback = (try? antigravityPassthrough(event: event).encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "[ -x \"\(bridge)\" ] && exec \"\(bridge)\" --source antigravity --event \(event) || { cat >/dev/null; echo '\(fallback)'; }"
    }

    public static func isOurs(_ hook: JSONValue) -> Bool {
        guard let command = hook["command"]?.string else { return false }
        return command.contains(marker) || command.contains(legacyMarker)
    }

    /// True when the config still runs the pre-rename `notchisland-bridge`.
    public static func hasLegacy(in root: JSONValue) -> Bool {
        if root[legacyAntigravityHookName].map(ourEvents(inAntigravityHook:))?.isEmpty == false { return true }
        return (root["hooks"]?.object ?? [:]).values.contains { groups in
            (groups.array ?? []).contains { group in
                (group["hooks"]?.array ?? []).contains { $0["command"]?.string?.contains(legacyMarker) ?? false }
            }
        }
    }

    public static func hasLegacy(_ target: HookTarget, home: URL = NotchPaths.homeDirectory) -> Bool {
        guard let data = try? Data(contentsOf: target.configURL(home: home)), let root = try? JSONValue.decode(data) else { return false }
        return hasLegacy(in: root)
    }

    private static func handler(_ target: HookTarget, _ event: String) -> JSONValue {
        ["type": "command", "command": .string(command(for: target, event: event)), "timeout": .number(Double(target.timeout(for: event)))]
    }

    public static func installing(_ target: HookTarget, into root: JSONValue) -> JSONValue {
        var root = uninstalling(from: root).object ?? [:]
        if target == .antigravity {
            var hook: [String: JSONValue] = [:]
            for event in target.events {
                // Tool events take matcher groups; the others take handlers directly.
                hook[event] =
                    event.hasSuffix("ToolUse") ? [["matcher": "*", "hooks": [handler(target, event)]]] : [handler(target, event)]
            }
            root[antigravityHookName] = .object(hook)
            return .object(root)
        }
        var hooks = root["hooks"]?.object ?? [:]
        for event in target.events {
            var groups = hooks[event]?.array ?? []
            groups.append(["hooks": [handler(target, event)]])
            hooks[event] = .array(groups)
        }
        root["hooks"] = .object(hooks)
        return .object(root)
    }

    /// Removes only our hook commands; drops groups/events that become empty because of it.
    public static func uninstalling(from root: JSONValue) -> JSONValue {
        guard var obj = root.object else { return root }
        for name in [antigravityHookName, legacyAntigravityHookName]
        where obj[name].map(ourEvents(inAntigravityHook:))?.isEmpty == false {
            obj[name] = nil
        }
        guard let hooks = obj["hooks"]?.object else { return .object(obj) }
        var cleaned: [String: JSONValue] = [:]
        for (event, value) in hooks {
            guard let groups = value.array else { cleaned[event] = value; continue }
            let kept = groups.compactMap { group -> JSONValue? in
                guard var g = group.object, let list = g["hooks"]?.array else { return group }
                let remaining = list.filter { !isOurs($0) }
                if remaining.isEmpty && !list.isEmpty { return nil }
                g["hooks"] = .array(remaining)
                return .object(g)
            }
            if !kept.isEmpty || groups.isEmpty { cleaned[event] = .array(kept) }
        }
        obj["hooks"] = .object(cleaned)
        return .object(obj)
    }

    public static func isInstalled(_ target: HookTarget, in root: JSONValue) -> Bool {
        ourEvents(target, in: root).isSuperset(of: target.events)
    }

    /// Events that currently run our bridge.
    private static func ourEvents(_ target: HookTarget, in root: JSONValue) -> Set<String> {
        if target == .antigravity { return root[antigravityHookName].map(ourEvents(inAntigravityHook:)) ?? [] }
        return Set(
            target.events.filter { event in
                (root["hooks"]?[event]?.array ?? []).contains { ($0["hooks"]?.array ?? []).contains(where: isOurs) }
            })
    }

    private static func ourEvents(inAntigravityHook hook: JSONValue) -> Set<String> {
        Set(
            (hook.object ?? [:]).compactMap { event, entries in
                let ours = (entries.array ?? []).contains { isOurs($0) || ($0["hooks"]?.array ?? []).contains(where: isOurs) }
                return ours ? event : nil
            })
    }

    /// Other tools whose PermissionRequest hooks wait a long time. The agent waits for every
    /// hook, so a blocked one can delay or override the answer given in the notch.
    public static func foreignBlockingHooks(in root: JSONValue, minimumTimeout: Int = 60) -> [String] {
        var names = Set<String>()
        for group in root["hooks"]?["PermissionRequest"]?.array ?? [] {
            for hook in group["hooks"]?.array ?? [] where !isOurs(hook) {
                guard let command = hook["command"]?.string, (hook["timeout"]?.int ?? 60) > minimumTimeout else { continue }
                names.insert(toolName(for: command))
            }
        }
        return names.sorted()
    }

    static func toolName(for command: String) -> String {
        let known = [("vibe-island", "Vibe Island"), ("agentnotch", "AgentNotch"), ("orca", "Orca"), ("claude-island", "Claude Island")]
        let lower = command.lowercased()
        if let match = known.first(where: { lower.contains($0.0) }) { return match.1 }
        let program = command.split(separator: " ").first.map { ($0 as NSString).lastPathComponent } ?? command
        return program.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    public static func foreignBlockingHooks(_ target: HookTarget, home: URL = NotchPaths.homeDirectory) -> [String] {
        guard let data = try? Data(contentsOf: target.configURL(home: home)), let root = try? JSONValue.decode(data) else { return [] }
        return foreignBlockingHooks(in: root)
    }

    public enum Status: Equatable, Sendable {
        case agentMissing, notInstalled, installed, partial, unreadable(String)
    }

    public static func status(_ target: HookTarget, home: URL = NotchPaths.homeDirectory) -> Status {
        let url = target.configURL(home: home)
        guard target.agentDirectories(home: home).contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .agentMissing
        }
        guard let data = try? Data(contentsOf: url) else { return .notInstalled }
        guard let root = try? JSONValue.decode(data) else { return .unreadable("\(url.lastPathComponent) is not valid JSON") }
        if isInstalled(target, in: root) { return .installed }
        return ourEvents(target, in: root).isEmpty ? .notInstalled : .partial
    }

    public enum InstallError: LocalizedError {
        case invalidJSON(URL)
        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let url): "\(url.path) isn’t valid JSON, so it was left untouched."
            }
        }
    }

    /// Install (or remove) hooks on disk. Returns the backup path, if a file existed.
    @discardableResult
    public static func apply(
        _ target: HookTarget, install: Bool, home: URL = NotchPaths.homeDirectory,
        backupDir: URL = NotchPaths.backups, now: Date = Date()
    ) throws -> URL? {
        let fm = FileManager.default
        // Write through symlinks (dotfile repos) instead of replacing the link with a file.
        let url = target.configURL(home: home).resolvingSymlinksInPath()
        var root: JSONValue = .object([:])
        var backup: URL?
        if let data = try? Data(contentsOf: url) {
            guard let parsed = try? JSONValue.decode(data) else { throw InstallError.invalidJSON(url) }
            root = parsed
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let b = backupDir.appendingPathComponent("\(target.rawValue)-\(url.lastPathComponent).\(stamp)")
            try data.write(to: b)
            backup = b
        } else if !install {
            return nil
        }
        let updated = install ? installing(target, into: root) : uninstalling(from: root)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.encoded(pretty: true).write(to: url, options: .atomic)
        return backup
    }
}
