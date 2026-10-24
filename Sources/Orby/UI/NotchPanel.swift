import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating overlay above the menu bar. It never steals focus from the
/// editor; it only becomes key when the user clicks into a text field.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        // Once the cursor is over the panel, moves are routed here instead of to global monitors.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel is never key before you click it, and AppKit swallows that first click to
/// focus the window. Accepting first mouse delivers it to SwiftUI, so one click acts.
final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the panel: positions it on the right screen and toggles click-through so only the
/// visible black shape intercepts the mouse.
@MainActor
final class NotchPanelController {
    static let canvas = CGSize(width: 760, height: 760)

    private let panel = NotchPanel()
    private let model: IslandModel
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hoverWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var mouseInside = false
    private let debug = ProcessInfo.processInfo.environment["ORBY_DEBUG"] != nil

    init(model: IslandModel) {
        self.model = model
        let host = FirstClickHostingView(rootView: AnyView(NotchRootView().environmentObject(model)))
        host.frame = CGRect(origin: .zero, size: Self.canvas)
        host.autoresizingMask = [.width, .height]
        // The canvas size is fixed, so skip the size constraints SwiftUI otherwise re-derives on
        // every frame an orb animates.
        host.sizingOptions = []
        panel.contentView = host
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
        model.$shapeSize.combineLatest(model.$expansion)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouse(at: NSEvent.mouseLocation) } }
            .store(in: &cancellables)

        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moved) { [weak self] _ in
            Task { @MainActor in self?.updateMouse(at: NSEvent.mouseLocation) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moved) { [weak self] e in
            self?.updateMouse(at: NSEvent.mouseLocation)
            return e
        } as Any)
        // Event monitors can miss moves (other apps' tracking, cursor warps, Space switches);
        // a cheap position poll keeps hover state honest.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouse(at: NSEvent.mouseLocation) }
        }
        // Click anywhere else closes the panel (except an unseen request; see outsideClick).
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.isExpanded, !self.interactiveRect.contains(NSEvent.mouseLocation) else { return }
                self.model.outsideClick()
            }
        } as Any)
    }

    private func targetScreen() -> NSScreen? {
        switch Prefs.display {
        case .auto: NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        case .main: NSScreen.screens.first ?? NSScreen.main
        }
    }

    private func reposition() {
        guard let screen = targetScreen() else { return }
        model.metrics = NotchMetrics.of(screen)
        let size = Self.canvas
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// Screen-space rect of the black shape (top-centered in the canvas).
    private var interactiveRect: CGRect {
        let f = panel.frame
        let s = model.shapeSize
        return CGRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    private func updateMouse(at point: CGPoint) {
        var rect = interactiveRect
        guard rect.width > 0, rect.height > 0 else { return }
        // Slack around the collapsed tab makes hover less fiddly; the extra top strip covers
        // the cursor pinned at the screen edge, where y == maxY falls outside `contains`.
        let slack: CGFloat = model.isExpanded ? 0 : 6
        rect = rect.insetBy(dx: -slack, dy: -slack)
        rect.size.height += 4
        let inside = rect.contains(point)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        guard inside != mouseInside else { return }
        mouseInside = inside
        if debug { NSLog("Orby hover: inside=\(inside) point=\(point) rect=\(rect) expanded=\(model.isExpanded)") }

        if inside {
            model.mouseEntered()
            guard !model.isExpanded, Prefs.bool(PrefKey.expandOnHover) else { return }
            hoverWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.mouseInside else { return }
                self.model.expand(.hover)
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Prefs.double(PrefKey.hoverDelay), execute: work)
        } else {
            hoverWork?.cancel()
            model.mouseExited()
            if panel.isKeyWindow { panel.resignKey() }
        }
    }
}
