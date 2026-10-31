import AppKit
import Network

/// Whether a timed background check should run: someone could be at the Mac and it's online.
/// During a dark wake (Power Nap, a closed lid) timers still fire, but the display stays off and
/// the network is often down; after a real wake Wi-Fi takes a moment to come back.
@MainActor
final class UserPresence {
    private(set) var online = true
    /// Set before sleep, so a timer that fires on wake ahead of the wake notification still waits.
    private var asleep = false
    private var wokeAt = Date.distantPast
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.online = online }
        }
        monitor.start(queue: .global(qos: .utility))
        let center = NSWorkspace.shared.notificationCenter
        let events: [(Notification.Name, (UserPresence) -> Void)] = [
            (NSWorkspace.willSleepNotification, { $0.asleep = true }),
            (NSWorkspace.didWakeNotification, { $0.asleep = false; $0.wokeAt = Date() }),
            (NSWorkspace.screensDidWakeNotification, { $0.wokeAt = Date() }),
        ]
        for (name, apply) in events {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { apply(self) } }
            })
        }
    }

    /// Display on, session unlocked, online, and awake for at least a minute.
    var isActive: Bool {
        guard online, !asleep, Date().timeIntervalSince(wokeAt) > 60, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return false }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool != true
    }
}
