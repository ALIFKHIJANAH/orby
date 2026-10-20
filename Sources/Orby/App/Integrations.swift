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
        return results
    }
}
