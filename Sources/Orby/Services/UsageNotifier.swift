import Foundation
import NotchCore
import UserNotifications

/// Posts a macOS notification when a plan limit crosses 80% or 95%.
/// Needs the bundled app: `UNUserNotificationCenter` traps when run as a bare `swift run` binary.
@MainActor
final class UsageNotifier {
    private var tracker = UsageAlertTracker()
    private var asked = false

    func check(_ limits: [RateLimits]) {
        // Keep tracking while off, so turning it on doesn't alert for climbs that already happened.
        let alerts = tracker.check(limits)
        guard !alerts.isEmpty, Prefs.bool(PrefKey.usageAlerts), !PreviewRenderer.active,
            Bundle.main.bundleIdentifier != nil
        else { return }
        let center = UNUserNotificationCenter.current()
        let post = {
            for a in alerts {
                let content = UNMutableNotificationContent()
                content.title = a.title
                content.body = a.window.resetsAt.map { "Resets \(UsageWindow.relative($0))." } ?? ""
                let id = "usage.\(RateLimits.windowID(a.agent, a.window.label)).\(Int(a.threshold * 100))"
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            }
        }
        if asked { return post() }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.asked = true; post() } }
        }
    }
}
