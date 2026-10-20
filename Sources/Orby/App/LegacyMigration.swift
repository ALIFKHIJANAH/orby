import Foundation
import NotchCore
import NotchShared

/// Carries an install over from when the app was called NotchIsland: data folder, settings
/// and agent hooks. Every step is a no-op once done, so it simply runs on each launch.
enum LegacyMigration {
    static let legacyBundleID = "dev.notchisland.app"

    static func run() {
        moveDataFolder()
        copyPreferences()
        for target in HookTarget.allCases where HookInstaller.hasLegacy(target) {
            do {
                try HookInstaller.apply(target, install: true)
            } catch {
                NSLog("Orby: failed to migrate \(target.rawValue) hooks: \(error)")
            }
        }
    }

    private static func moveDataFolder() {
        // A custom ORBY_HOME (tests) must never swallow the real ~/.notchisland.
        guard ProcessInfo.processInfo.environment["ORBY_HOME"] == nil else { return }
        let fm = FileManager.default
        let old = NotchPaths.legacyRoot, new = NotchPaths.root
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            try? fm.removeItem(at: NotchPaths.bin.appendingPathComponent("notchisland-bridge"))
            try? fm.removeItem(at: NotchPaths.socket)
        } catch {
            NSLog("Orby: failed to move \(old.path): \(error)")
        }
    }

    private static func copyPreferences() {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, id != legacyBundleID,
            defaults.persistentDomain(forName: id)?.isEmpty ?? true,
            let old = defaults.persistentDomain(forName: legacyBundleID), !old.isEmpty
        else { return }
        defaults.setPersistentDomain(old, forName: id)
    }
}
