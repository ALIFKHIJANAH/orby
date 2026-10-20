import AppKit
import Combine
import NotchCore
import NotchShared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandModel()
    private var panel: NotchPanelController?
    private var server: SocketServer?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var antigravityWatcher: AntigravityLogWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigration.run()
        Prefs.register()
        BridgeSetup.installIfNeeded()
        if Prefs.bool(PrefKey.autoConfigureAgents) {
            for target in HookTarget.allCases where HookInstaller.status(target) == .notInstalled {
                _ = try? HookInstaller.apply(target, install: true)
            }
        }

        let model = self.model
        let server = SocketServer { envelope, connection in
            DispatchQueue.main.async { MainActor.assumeIsolated { model.receive(envelope, connection: connection) } }
        }
        do {
            try server.start()
        } catch {
            NSLog("Orby: socket failed: \(error)")
        }
        self.server = server

        SettingsWindowController.shared.sound = model.sound
        SettingsWindowController.shared.usage = model.usage
        model.start()
        // Antigravity reports permission prompts only in its CLI log.
        let watcher = AntigravityLogWatcher { event, logID in model.antigravityLog(event, logID: logID) }
        watcher.start()
        antigravityWatcher = watcher
        let panel = NotchPanelController(model: model)
        panel.show()
        self.panel = panel

        setupStatusItem()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.setupStatusItem() }
            .store(in: &cancellables)

        if !Prefs.bool(PrefKey.didOnboard) {
            Prefs.defaults.set(true, forKey: PrefKey.didOnboard)
            if !IntegrationStatus.current().anyInstalled { SettingsWindowController.shared.show(tab: .integrations) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let wanted = Prefs.bool(PrefKey.showMenuBarIcon)
        if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        } else if wanted, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Orby")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt on open so it always lists live sessions.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if model.sessions.isEmpty {
            menu.addItem(NSMenuItem(title: "No active agents", action: nil, keyEquivalent: ""))
        }
        for s in model.sessions {
            let item = NSMenuItem(title: "\(s.title ?? s.projectName) — \(s.phase.label)", action: #selector(jumpTo(_:)), keyEquivalent: "")
            item.representedObject = s.id
            item.target = self
            item.image = NSImage(systemSymbolName: s.phase.needsUser ? "exclamationmark.circle.fill" : s.phase.group == .working ? "circle.dotted" : "checkmark.circle", accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Island", action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Orby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func jumpTo(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let s = model.session(for: id) else { return }
        model.jump(to: s)
    }

    @objc private func toggleIsland() { model.toggle() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
}
