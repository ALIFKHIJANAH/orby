import Foundation
import NotchShared

/// Adds/removes Orby's hook entries in an agent's hook config, leaving every
/// other tool's hooks untouched. Writes a timestamped backup before any change.
/// Agents without JSON hooks (OpenCode, Pi) get a plugin file instead; Command Code gets both.
public enum HookTarget: String, CaseIterable, Sendable {
    case claude, codex, antigravity, opencode, pi, commandcode, qwen

    public var agent: AgentKind {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .antigravity: .antigravity
        case .opencode: .opencode
        case .pi: .pi
        case .commandcode: .commandcode
        case .qwen: .qwen
        }
    }

    /// False for agents Orby reaches only through a plugin file.
    public var hasHookConfig: Bool { self != .opencode && self != .pi }

    /// The hook config Orby edits, or the plugin file for plugin-only agents.
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
        case .opencode, .pi:
            return pluginURL(home: home)!
        case .commandcode:
            return home.appendingPathComponent(".commandcode/settings.json")
        case .qwen:
            return home.appendingPathComponent(".qwen/settings.json")
        }
    }

    /// Source file Orby owns in the agent's plugin/extension/mod directory.
    public func pluginURL(home: URL = NotchPaths.homeDirectory) -> URL? {
        let env = ProcessInfo.processInfo.environment
        // Overrides only apply to the real home, so tests with a temp home stay put.
        func override(_ key: String) -> URL? {
            guard home == NotchPaths.homeDirectory, let dir = env[key], !dir.isEmpty else { return nil }
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        switch self {
        case .opencode:
            let config = override("XDG_CONFIG_HOME") ?? home.appendingPathComponent(".config")
            return config.appendingPathComponent("opencode/plugins/orby.js")
        case .pi:
            let agentDir = override("PI_CODING_AGENT_DIR") ?? home.appendingPathComponent(".pi/agent")
            return agentDir.appendingPathComponent("extensions/orby.ts")
        case .commandcode:
            return home.appendingPathComponent(".commandcode/mods/orby.ts")
        case .claude, .codex, .antigravity, .qwen:
            return nil
        }
    }

    /// Directories whose existence means the agent is installed on this Mac.
    public func agentDirectories(home: URL = NotchPaths.homeDirectory) -> [URL] {
        switch self {
        case .claude, .codex, .commandcode, .qwen: [configURL(home: home).deletingLastPathComponent()]
        case .antigravity:
            ["antigravity", "antigravity-ide", "antigravity-cli"].map { home.appendingPathComponent(".gemini/\($0)") }
        case .opencode:
            // Config dir, the curl installer's bin dir, or the data dir.
            [
                pluginURL(home: home)!.deletingLastPathComponent().deletingLastPathComponent(),
                home.appendingPathComponent(".opencode"), home.appendingPathComponent(".local/share/opencode"),
            ]
        case .pi:
            [pluginURL(home: home)!.deletingLastPathComponent().deletingLastPathComponent()]
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
        case .qwen:
            [
                "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop",
                "PreCompact", "PostCompact",
            ]
        case .commandcode:
            // The only hook events it has; prompts, approvals and exit come through the mod.
            ["SessionStart", "PreToolUse", "PostToolUse", "Stop"]
        case .opencode, .pi:
            []
        }
    }

    /// Seconds the agent waits for the hook. Permission requests block until the user decides.
    public func timeout(for event: String) -> Int {
        guard blockingEvents.contains(event) else { return 10 }
        switch self {
        case .claude: return 86400
        // Qwen reads any timeout of 1000 or more as milliseconds.
        case .qwen: return 600
        default: return 7200
        }
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
        guard target.hasHookConfig, let data = try? Data(contentsOf: target.configURL(home: home)), let root = try? JSONValue.decode(data) else { return false }
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
        guard target.agentDirectories(home: home).contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .agentMissing
        }
        // Each part Orby writes (hook config, plugin file) is either fully there, missing or partial.
        var parts: [Status] = []
        if target.hasHookConfig {
            let url = target.configURL(home: home)
            if let data = try? Data(contentsOf: url) {
                guard let root = try? JSONValue.decode(data) else { return .unreadable("\(url.lastPathComponent) is not valid JSON") }
                parts.append(isInstalled(target, in: root) ? .installed : ourEvents(target, in: root).isEmpty ? .notInstalled : .partial)
            } else {
                parts.append(.notInstalled)
            }
        }
        if let url = target.pluginURL(home: home) {
            switch PluginInstaller.state(target, home: home) {
            case .current: parts.append(.installed)
            case .missing: parts.append(.notInstalled)
            // Written by an older Orby: Repair rewrites it.
            case .outdated: parts.append(.partial)
            case .foreign: return .unreadable("\(url.lastPathComponent) belongs to another tool")
            }
        }
        if parts.allSatisfy({ $0 == .installed }) { return .installed }
        return parts.allSatisfy({ $0 == .notInstalled }) ? .notInstalled : .partial
    }

    public enum InstallError: LocalizedError {
        case invalidJSON(URL)
        case foreignPlugin(URL)
        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let url): "\(url.path) isn’t valid JSON, so it was left untouched."
            case .foreignPlugin(let url): "\(url.path) wasn’t written by Orby, so it was left untouched."
            }
        }
    }

    /// Install (or remove) hooks and plugin files on disk. Returns a backup path, if a file was changed.
    @discardableResult
    public static func apply(
        _ target: HookTarget, install: Bool, home: URL = NotchPaths.homeDirectory,
        backupDir: URL = NotchPaths.backups, now: Date = Date()
    ) throws -> URL? {
        // Check the plugin slot first so a refusal leaves the hook config untouched too.
        if target.pluginURL(home: home) != nil, PluginInstaller.state(target, home: home) == .foreign {
            throw InstallError.foreignPlugin(target.pluginURL(home: home)!)
        }
        var backup: URL?
        if target.hasHookConfig {
            backup = try applyHooks(target, install: install, home: home, backupDir: backupDir, now: now)
        }
        if target.pluginURL(home: home) != nil {
            let pluginBackup = try PluginInstaller.apply(target, install: install, home: home, backupDir: backupDir, now: now)
            backup = backup ?? pluginBackup
        }
        return backup
    }

    static func backup(_ data: Data, of url: URL, for target: HookTarget, in backupDir: URL, now: Date) throws -> URL {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let b = backupDir.appendingPathComponent("\(target.rawValue)-\(url.lastPathComponent).\(stamp)")
        try data.write(to: b)
        return b
    }

    private static func applyHooks(_ target: HookTarget, install: Bool, home: URL, backupDir: URL, now: Date) throws -> URL? {
        let fm = FileManager.default
        // Write through symlinks (dotfile repos) instead of replacing the link with a file.
        let url = target.configURL(home: home).resolvingSymlinksInPath()
        var root: JSONValue = .object([:])
        var saved: URL?
        if let data = try? Data(contentsOf: url) {
            guard let parsed = try? JSONValue.decode(data) else { throw InstallError.invalidJSON(url) }
            root = parsed
            saved = try backup(data, of: url, for: target, in: backupDir, now: now)
        } else if !install {
            return nil
        }
        let updated = install ? installing(target, into: root) : uninstalling(from: root)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.encoded(pretty: true).write(to: url, options: .atomic)
        return saved
    }
}
