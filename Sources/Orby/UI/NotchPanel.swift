import AppKit
import Combine
import NotchCore
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

/// One island's own state: the screen it sits on and the size of its black shape. Several
/// islands share one `IslandModel`; only the active one shows the open panel.
@MainActor
final class IslandScreen: ObservableObject {
    @Published var metrics: NotchMetrics
    @Published var isActive: Bool
    /// Not @Published, like `IslandModel.shapeSize`: it changes on every frame of a spring.
    var shapeSize: CGSize = .zero {
        didSet { if shapeSize != oldValue { shapeSizeChanged.send(shapeSize) } }
    }
    let shapeSizeChanged = PassthroughSubject<CGSize, Never>()

    init(metrics: NotchMetrics, isActive: Bool = true) {
        self.metrics = metrics
        self.isActive = isActive
    }
}

extension NSScreen {
    var displayID: UInt32? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
}

/// Owns the island panels: one on the chosen screen, one per screen, or none (menu bar only).
/// Positions them, picks which one opens, and toggles click-through so only the visible black
/// shape intercepts the mouse.
@MainActor
final class NotchPanelController {
    static let canvas = CGSize(width: 760, height: 760)

    private struct Island {
        var displayID: UInt32
        let panel: NotchPanel
        let screen: IslandScreen
    }

    private let model: IslandModel
    private var islands: [Island] = []
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var hoverWork: DispatchWorkItem?
    private var pollTimer: Timer?
    /// The island under the pointer, if any.
    private var hovered: UInt32?
    private let debug = ProcessInfo.processInfo.environment["ORBY_DEBUG"] != nil

    init(model: IslandModel) {
        self.model = model
    }

    private var active: Island? { islands.first { $0.screen.isActive } }

    func show() {
        layout()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
        model.$expansion.map { $0 != nil }.removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                if expanded { self.pickRevealIsland() }
                // Without an island an open panel would be invisible, yet its ⌘Y/⌘N shortcuts
                // would still answer requests.
                if expanded, Prefs.display == .menuBarOnly {
                    DispatchQueue.main.async { self.model.collapse() }
                }
            }
            .store(in: &cancellables)
        model.$expansion.map { _ in }
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouse(at: NSEvent.mouseLocation) } }
            .store(in: &cancellables)
        // The launcher takes typing straight away, even when opened by its shortcut from another
        // app. The panel doesn't activate Orby, so that app stays in front.
        model.$composing.filter { $0 }
            .sink { [weak self] _ in DispatchQueue.main.async { self?.active?.panel.makeKey() } }
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
        pollTimer?.tolerance = 0.03
        // Click anywhere else closes the panel (except an unseen request; see outsideClick).
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.isExpanded else { return }
                if let island = self.active, self.interactiveRect(island).contains(NSEvent.mouseLocation) { return }
                self.model.outsideClick()
            }
        } as Any)
    }

    private func layoutScreens() -> [(NSScreen, DisplayLayout.Screen)] {
        NSScreen.screens.compactMap { s in
            s.displayID.map { (s, DisplayLayout.Screen(id: $0, frame: s.frame, hasNotch: s.safeAreaInsets.top > 0)) }
        }
    }

    /// Matches islands to the screens that should have one, reusing panels so a single island
    /// that changes screen keeps its view state. Runs on screen add/remove/arrangement changes.
    private func layout() {
        let screens = layoutScreens()
        let wanted = DisplayLayout.islandScreens(
            Prefs.display.placement, screens: screens.map(\.1), main: NSScreen.main?.displayID)
        var spare = islands.filter { !wanted.contains($0.displayID) }
        let kept = islands.filter { wanted.contains($0.displayID) }
        let wasActive = active?.displayID
        islands = wanted.map { id in
            if let island = kept.first(where: { $0.displayID == id }) { return island }
            if !spare.isEmpty {
                var island = spare.removeFirst()
                island.displayID = id
                return island
            }
            return makeIsland(id)
        }
        for island in spare { island.panel.orderOut(nil) }
        if hovered.map({ id in !islands.contains { $0.displayID == id } }) ?? false { hovered = nil }

        let activeID = islands.contains { $0.displayID == wasActive } ? wasActive : islands.first?.displayID
        for island in islands {
            guard let screen = screens.first(where: { $0.1.id == island.displayID })?.0 else { continue }
            let metrics = NotchMetrics.of(screen)
            if island.screen.metrics != metrics { island.screen.metrics = metrics }
            setActive(island, island.displayID == activeID)
            let size = Self.canvas
            let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
            island.panel.setFrame(CGRect(origin: origin, size: size), display: true)
            island.panel.orderFrontRegardless()
        }
        if let active { syncMetrics(active) }
    }

    private func makeIsland(_ id: UInt32) -> Island {
        let screen = IslandScreen(metrics: .fallback, isActive: false)
        let panel = NotchPanel()
        let host = FirstClickHostingView(
            rootView: AnyView(NotchRootView().environmentObject(model).environmentObject(screen)))
        host.frame = CGRect(origin: .zero, size: Self.canvas)
        host.autoresizingMask = [.width, .height]
        // The canvas size is fixed, so skip the size constraints SwiftUI otherwise re-derives on
        // every frame an orb animates.
        host.sizingOptions = []
        panel.contentView = host
        screen.shapeSizeChanged
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouse(at: NSEvent.mouseLocation) } }
            .store(in: &cancellables)
        return Island(displayID: id, panel: panel, screen: screen)
    }

    /// The model's metrics follow the active island; skipping no-op writes spares every island a
    /// re-render on each hover.
    private func syncMetrics(_ island: Island) {
        if model.metrics != island.screen.metrics { model.metrics = island.screen.metrics }
    }

    private func setActive(_ island: Island, _ active: Bool) {
        if island.screen.isActive != active { island.screen.isActive = active }
    }

    /// Only one island opens: the one on the screen with the pointer, else the main screen's.
    private func pickRevealIsland() {
        guard islands.count > 1 else { return }
        let screens = layoutScreens().map(\.1)
        let candidates = islands.compactMap { island in screens.first { $0.id == island.displayID } }
        guard let id = DisplayLayout.revealScreen(
            islands: candidates, mouse: NSEvent.mouseLocation, main: NSScreen.main?.displayID)
        else { return }
        if debug { NSLog("Orby reveal: island=\(id) of \(islands.map(\.displayID))") }
        for island in islands { setActive(island, island.displayID == id) }
        if let active { syncMetrics(active) }
    }

    /// Screen-space rect of an island's black shape (top-centered in the canvas).
    private func interactiveRect(_ island: Island) -> CGRect {
        let f = island.panel.frame
        let s = island.screen.shapeSize
        return CGRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    /// The island the pointer is over. While the panel is open only the active island counts;
    /// the others' tabs wait until it closes.
    private func island(at point: CGPoint) -> Island? {
        islands.first { island in
            if model.isExpanded, !island.screen.isActive { return false }
            var rect = interactiveRect(island)
            guard rect.width > 0, rect.height > 0 else { return false }
            // Slack around the collapsed tab makes hover less fiddly; the extra top strip covers
            // the cursor pinned at the screen edge, where y == maxY falls outside `contains`.
            let slack: CGFloat = model.isExpanded ? 0 : 6
            rect = rect.insetBy(dx: -slack, dy: -slack)
            rect.size.height += 4
            return rect.contains(point)
        }
    }

    private func updateMouse(at point: CGPoint) {
        let target = island(at: point)
        for island in islands {
            let inside = island.displayID == target?.displayID
            if island.panel.ignoresMouseEvents == inside { island.panel.ignoresMouseEvents = !inside }
        }
        guard target?.displayID != hovered else { return }
        if hovered != nil {
            hovered = nil
            hoverWork?.cancel()
            model.mouseExited()
            if let key = islands.first(where: { $0.panel.isKeyWindow }), !model.composing { key.panel.resignKey() }
        }
        guard let target else { return }
        hovered = target.displayID
        if debug { NSLog("Orby hover: island=\(target.displayID) point=\(point) expanded=\(model.isExpanded)") }

        // Only reached collapsed or on the active island, so moving the active one is safe.
        for island in islands { setActive(island, island.displayID == target.displayID) }
        syncMetrics(target)
        model.mouseEntered()
        guard !model.isExpanded, Prefs.bool(PrefKey.expandOnHover) else { return }
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovered == target.displayID else { return }
            self.model.expand(.hover)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Prefs.double(PrefKey.hoverDelay), execute: work)
    }
}
