import Foundation
import NotchCore
import NotchShared

struct IntegrationStatus {
    var statuses: [HookTarget: HookInstaller.Status]

    static func current() -> IntegrationStatus {
        IntegrationStatus(statuses: Dictionary(uniqueKeysWithValues: HookTarget.allCases.map { ($0, HookInstaller.status($0)) }))
    }

    var anyInstalled: Bool { statuses.values.contains(.installed) }
}

extension HookTarget {
    /// What connecting this agent gets you, where it differs from Claude Code.
    var setupNote: String? {
        switch self {
        case .opencode:
            "Orby installed a plugin in OpenCode's plugins folder. Approvals and questions can be answered from the notch. Restart OpenCode to load it."
        case .pi:
            "Pi doesn't ask before running tools, so Orby shows its status only. Run /reload in Pi or restart it to load the extension."
        case .commandcode:
            "Status comes from hooks, approvals from an Orby mod. Mods are experimental in Command Code; while the notch shows a request, Command Code's own prompt waits for it."
        case .claude, .codex, .antigravity, .qwen:
            nil
        }
    }
}

enum BridgeSetup {
    /// The helper ships inside the app; hooks point at a stable copy so moving the app never breaks them.
    static var bundledBridge: URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/orby-bridge"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("orby-bridge"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: NotchPaths.installedBridge.path) }

    /// Copy the bundled bridge into ~/.orby/bin when missing or different.
    @discardableResult
    static func installIfNeeded() -> Bool {
        guard let source = bundledBridge else { return isInstalled }
        let fm = FileManager.default
        let dest = NotchPaths.installedBridge
        if let a = try? Data(contentsOf: source), let b = try? Data(contentsOf: dest), a == b { return true }
        do {
            try fm.createDirectory(at: NotchPaths.bin, withIntermediateDirectories: true)
            let tmp = dest.appendingPathExtension("tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: source, to: tmp)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            return true
        } catch {
            NSLog("Orby: failed to install bridge: \(error)")
            return false
        }
    }

    /// Set up every agent found on this Mac (used by onboarding and "auto-configure").
    static func configureDetectedAgents() -> [HookTarget: Result<URL?, Error>] {
        installIfNeeded()
        var results: [HookTarget: Result<URL?, Error>] = [:]
        for target in HookTarget.allCases where HookInstaller.status(target) != .agentMissing {
            results[target] = Result { try HookInstaller.apply(target, install: true) }
        }
        // The status line relay is opt-in: only reinstalled when its Settings toggle is on.
        if Prefs.bool(PrefKey.antigravityStatusLine), StatusLineInstaller.status() == .notInstalled {
            _ = try? StatusLineInstaller.apply(install: true)
        }
        return results
    }
}
