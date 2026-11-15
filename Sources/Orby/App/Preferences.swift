import Foundation
import NotchCore

/// UserDefaults keys shared by @AppStorage in views and by non-view code.
enum PrefKey {
    static let expandOnHover = "expandOnHover"
    static let hoverDelay = "hoverDelay"
    static let autoExpandAttention = "autoExpandAttention"
    static let autoExpandCompletion = "autoExpandCompletion"
    static let completionRevealSeconds = "completionRevealSeconds"
    static let quietWhenTerminalFocused = "quietWhenTerminalFocused"
    static let clickToJump = "clickToJump"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let hideWhenIdle = "hideWhenIdle"
    static let showHeadphoneConnected = "showHeadphoneConnected"
    static let idleHideSeconds = "idleHideSeconds"
    static let finishedSessionTTLMinutes = "finishedSessionTTLMinutes"
    static let display = "display"
    static let notchWidthOverride = "notchWidthOverride"
    static let notchHeightOverride = "notchHeightOverride"
    static let panelWidth = "panelWidth"
    static let soundTheme = "soundTheme"
    static let soundVolume = "soundVolume"
    static let customSoundFolder = "customSoundFolder"
    static let claudeUsageEnabled = "claudeUsageEnabled"
    static let showUsageInHeader = "showUsageInHeader"
    /// macOS notification when a plan limit crosses 80% or 95%.
    static let usageAlerts = "usageAlerts"
    /// Header shows the limits the user picked instead of the two closest to running out.
    static let pickHeaderLimits = "pickHeaderLimits"
    /// Picked header limits, one `RateLimits.windowID` per line, in display order.
    static let headerLimits = "headerLimits"
    static let didOnboard = "didOnboard"
    /// Ask GitHub once a day whether a newer release is out; when it last did.
    static let checkForUpdates = "checkForUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let autoConfigureAgents = "autoConfigureAgents"
    static let antigravityAnswerFromNotch = "antigravityAnswerFromNotch"
    /// Relay agy's status line (plan quota) to Orby. Also lets auto-configure reinstall it.
    static let antigravityStatusLine = "antigravityStatusLine"
    /// Run `agy -p "/usage"` every few minutes (agy then asks Google with the user's login).
    static let antigravityUsageEnabled = "antigravityUsageEnabled"
    /// Minutes a trusted session auto-allows safe requests.
    static let trustMinutes = "trustMinutes"
    /// Replay a request's cue once after this many minutes unanswered; 0 = off.
    static let reminderMinutes = "reminderMinutes"
    static let muteWhenLocked = "muteWhenLocked"
    static let quietHoursEnabled = "quietHoursEnabled"
    static let quietHoursStart = "quietHoursStart"
    static let quietHoursEnd = "quietHoursEnd"
    /// Starting an agent from the notch: the terminal picked by default (a `LaunchTerminal`),
    /// the default folder ("" = none), and the agent used last.
    static let launchTerminal = "launchTerminal"
    static let launchFolder = "launchFolder"
    static let launchAgent = "launchAgent"
    /// Folders agents were started in from the notch, newest first, one per line.
    static let recentFolders = "recentFolders"
    /// ⌥⌘N opens the new-agent launcher from any app.
    static let newAgentShortcut = "newAgentShortcut"
    /// ⌃⌥J jumps to the session that needs you from any app. Off by default: it's a global key.
    static let jumpShortcut = "jumpShortcut"
    /// Silence sounds while a macOS Focus is on. Reading Focus needs permission, asked only from Settings.
    static let followFocus = "followFocus"
    /// A `KeepAwakePolicy.Mode`: hold off idle sleep while an agent works. Off by default.
    static let keepAwake = "keepAwake"
    /// Extra Claude Code config folders (besides ~/.claude and $CLAUDE_CONFIG_DIR), one path per line.
    static let claudeConfigDirs = "claudeConfigDirs"
    /// Sessions kept out of the list: folders (one per line, the folder and everything under it)
    /// and text in the first prompt (one per line).
    static let hiddenFolders = "hiddenFolders"
    static let hiddenPrompts = "hiddenPrompts"
    /// ⌃⌥S opens the session switcher from any app. Off by default: it's a global key.
    static let switcherShortcut = "switcherShortcut"
    static func soundEnabled(_ cue: SoundCue) -> String { "sound.\(cue.rawValue)" }
}

enum SoundTheme: String, CaseIterable, Identifiable {
    case chiptune, system, custom, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chiptune: "8-bit"
        case .system: "macOS sounds"
        case .custom: "Custom folder"
        case .off: "Off"
        }
    }
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case auto, main, every, menuBarOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Built-in display (notch) if available"
        case .main: "Display with the menu bar"
        case .every: "Every display"
        case .menuBarOnly: "Menu bar only (no island)"
        }
    }
    var placement: DisplayLayout.Placement {
        switch self {
        case .auto: .notchOrMain
        case .main: .menuBar
        case .every: .every
        case .menuBarOnly: .none
        }
    }
}

enum Prefs {
    static let defaults = UserDefaults.standard

    static func register() {
        var values: [String: Any] = [
            PrefKey.expandOnHover: true,
            PrefKey.hoverDelay: 0.15,
            PrefKey.autoExpandAttention: true,
            PrefKey.autoExpandCompletion: true,
            PrefKey.completionRevealSeconds: 4.0,
            PrefKey.quietWhenTerminalFocused: true,
            PrefKey.clickToJump: true,
            PrefKey.showMenuBarIcon: true,
            PrefKey.hideWhenIdle: true,
            PrefKey.showHeadphoneConnected: true,
            PrefKey.idleHideSeconds: 10.0,
            PrefKey.finishedSessionTTLMinutes: 60.0,
            PrefKey.display: DisplayChoice.auto.rawValue,
            PrefKey.notchWidthOverride: 0.0,
            PrefKey.notchHeightOverride: 0.0,
            PrefKey.panelWidth: 560.0,
            PrefKey.soundTheme: SoundTheme.chiptune.rawValue,
            PrefKey.soundVolume: 0.5,
            PrefKey.claudeUsageEnabled: false,
            PrefKey.showUsageInHeader: true,
            PrefKey.usageAlerts: true,
            PrefKey.pickHeaderLimits: false,
            PrefKey.headerLimits: "",
            PrefKey.didOnboard: false,
            PrefKey.checkForUpdates: true,
            PrefKey.autoConfigureAgents: false,
            PrefKey.antigravityAnswerFromNotch: true,
            PrefKey.antigravityStatusLine: false,
            PrefKey.antigravityUsageEnabled: false,
            PrefKey.trustMinutes: 30.0,
            PrefKey.reminderMinutes: 0.0,
            PrefKey.muteWhenLocked: true,
            PrefKey.quietHoursEnabled: false,
            PrefKey.quietHoursStart: 22,
            PrefKey.quietHoursEnd: 8,
            PrefKey.launchFolder: "",
            PrefKey.recentFolders: "",
            PrefKey.newAgentShortcut: true,
            PrefKey.jumpShortcut: false,
            PrefKey.followFocus: true,
            PrefKey.keepAwake: KeepAwakePolicy.Mode.off.rawValue,
            PrefKey.claudeConfigDirs: "",
            PrefKey.hiddenFolders: "",
            PrefKey.hiddenPrompts: "",
            PrefKey.switcherShortcut: false,
        ]
        for cue in SoundCue.allCases { values[PrefKey.soundEnabled(cue)] = cue != .start }
        defaults.register(defaults: values)
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func lines(_ stored: String) -> [String] { stored.split(separator: "\n").map(String.init) }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }
    static var soundTheme: SoundTheme { SoundTheme(rawValue: defaults.string(forKey: PrefKey.soundTheme) ?? "") ?? .chiptune }
    static var keepAwake: KeepAwakePolicy.Mode { KeepAwakePolicy.Mode(rawValue: defaults.string(forKey: PrefKey.keepAwake) ?? "") ?? .off }
    static var claudeConfigDirs: [URL] { ClaudeConfigDirs.extras(lines(defaults.string(forKey: PrefKey.claudeConfigDirs) ?? "")) }
    static var sessionFilter: SessionFilter {
        SessionFilter(
            folderLines: defaults.string(forKey: PrefKey.hiddenFolders) ?? "",
            promptLines: defaults.string(forKey: PrefKey.hiddenPrompts) ?? "")
    }
    static var display: DisplayChoice { DisplayChoice(rawValue: defaults.string(forKey: PrefKey.display) ?? "") ?? .auto }
}
