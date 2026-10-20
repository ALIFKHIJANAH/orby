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
    static let didOnboard = "didOnboard"
    static let autoConfigureAgents = "autoConfigureAgents"
    static let antigravityAnswerFromNotch = "antigravityAnswerFromNotch"
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
    case auto, main
    var id: String { rawValue }
    var label: String { self == .auto ? "Built-in display (notch) if available" : "Display with the menu bar" }
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
            PrefKey.didOnboard: false,
            PrefKey.autoConfigureAgents: false,
            PrefKey.antigravityAnswerFromNotch: true,
        ]
        for cue in SoundCue.allCases { values[PrefKey.soundEnabled(cue)] = cue != .start }
        defaults.register(defaults: values)
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func double(_ key: String) -> Double { defaults.double(forKey: key) }
    static var soundTheme: SoundTheme { SoundTheme(rawValue: defaults.string(forKey: PrefKey.soundTheme) ?? "") ?? .chiptune }
    static var display: DisplayChoice { DisplayChoice(rawValue: defaults.string(forKey: PrefKey.display) ?? "") ?? .auto }
}
