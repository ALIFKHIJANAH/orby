import AppKit
import Combine
import NotchCore
import NotchShared

/// Why the panel is open; decides when it may close on its own.
enum ExpansionReason: Equatable {
    case hover, click, attention, completion
}

enum IslandTab: String {
    case sessions, usage
}

@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var pending: [PendingRequest] = []
    @Published private(set) var expansion: ExpansionReason?
    @Published var tab: IslandTab = .sessions
    @Published var metrics = NotchMetrics.fallback
    /// Size of the visible black shape, reported by the view, used for mouse hit-testing. Not
    /// @Published: it changes on every frame of an expand/collapse spring, and no view reads it.
    var shapeSize: CGSize = .zero {
        didSet { if shapeSize != oldValue { shapeSizeChanged.send(shapeSize) } }
    }
    let shapeSizeChanged = PassthroughSubject<CGSize, Never>()
    @Published private(set) var highlightedSession: String?
    @Published var selectedRequestIndex = 0 {
        didSet { if oldValue != selectedRequestIndex { updateHotKeys() } }
    }
    /// Focus mode: show the session list under the open request.
    @Published var peekSessions = false
    /// Nothing working or waiting for `idleHideSeconds`: the collapsed tab shrinks back to the plain notch.
    @Published private(set) var idleTab = false
    private var idleWork: DispatchWorkItem?
    private var prefsObserver: AnyCancellable?
    /// Antigravity menus read back from the agent's pane, by request id (nil: can't answer here).
    @Published private(set) var externalMenus: [String: AntigravityMenu] = [:]
    /// External requests being answered from the notch, and why an answer didn't take.
    @Published private(set) var answering: [String: AntigravityMenu.Kind] = [:]
    @Published private(set) var answerErrors: [String: String] = [:]
    /// ⌘1…⌘9 presses while a question is open, as zero-based option indexes.
    let optionShortcut = PassthroughSubject<Int, Never>()

    let usage = UsageService()
    let sound = SoundPlayer()

    private var engine = SessionEngine()
    private var connections: [String: BridgeConnection] = [:]
    private var lastTranscriptRead: [String: Date] = [:]
    private var transcripts: [String: TranscriptRead] = [:]
    private var collapseWork: DispatchWorkItem?
    private var pruneTimer: Timer?
    private var thinkingTimer: Timer?
    var mouseHasEntered = false

    var isExpanded: Bool { expansion != nil }
    var currentRequest: PendingRequest? {
        pending.isEmpty ? nil : pending[min(selectedRequestIndex, pending.count - 1)]
    }

    func start() {
        usage.start()
        // Settings such as the idle-hide delay apply right away, not on the next agent event.
        prefsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateIdleTab() }
        // No hooks fire while the model reasons, so poll the transcript for its thoughts.
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for s in self.sessions where s.phase == .thinking { self.refreshTranscript(s.id, force: true) }
            }
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.prune() }
        }
    }

    // MARK: Bridge events

    func receive(_ envelope: BridgeEnvelope, connection: BridgeConnection?) {
        if envelope.eventName == AntigravityStatusLine.eventName {
            if AgentKind(envelope: envelope) == .antigravity, let quota = AntigravityQuota.statusLine(envelope.payload) {
                usage.update(antigravity: quota)
            }
            return
        }
        let before = Set(engine.pending.map(\.id))
        let outcome = engine.handle(envelope)
        logNewExternalPrompts(since: before)

        if let connection {
            if let request = engine.pending.first(where: { $0.id == envelope.id }) {
                RequestLog.write("received", id: request.id, session: request.sessionKey, tool: request.toolName, pid: envelope.agentPID)
                connections[envelope.id] = connection
                let id = envelope.id
                connection.watch { [weak self] in
                    Task { @MainActor in self?.bridgeClosed(id) }
                }
            } else {
                RequestLog.write("ignored", id: envelope.id, session: envelope.sessionID, tool: envelope.payload["tool_name"]?.string)
                connection.reply(BridgeReply(stdout: nil))
            }
        }
        release(outcome.cancelledRequests, reason: RequestLog.releaseReason(for: envelope.eventName))

        if let key = outcome.sessionKey { refreshTranscript(key, force: outcome.refreshTranscript) }
        if let cue = outcome.cue { sound.play(cue) }
        if let reveal = outcome.reveal { handleReveal(reveal) }
        publish()
    }

    /// A permission prompt line from Antigravity's CLI log (it has no hook for prompts).
    func antigravityLog(_ event: AntigravityLog.Event, logID: String) {
        let before = Set(engine.pending.map(\.id))
        let outcome: SessionEngine.Outcome
        switch event {
        case .confirmationShown(let tool, let step):
            outcome = engine.externalPromptShown(tool: tool, step: step, logID: logID)
            if outcome.reveal == nil { RequestLog.write("parked(external)", id: "agy:\(logID):\(step)", tool: tool) }
        case .confirmationAnswered(let conv, let step, let approved):
            outcome = engine.externalPromptAnswered(conversationID: conv, step: step, approved: approved, logID: logID)
            release(outcome.cancelledRequests, reason: approved ? "approved-in-terminal" : "denied-in-terminal")
        }
        logNewExternalPrompts(since: before)
        if let cue = outcome.cue { sound.play(cue) }
        if let reveal = outcome.reveal { handleReveal(reveal) }
        publish()
        collapseIfIdle()
    }

    // MARK: Answering external prompts

    /// Read the agent's menu back from its pane. A menu means the card can offer answers;
    /// none (unsupported terminal, prompt not visible) leaves just "Go to terminal".
    func loadExternalMenu(_ request: PendingRequest) {
        guard request.kind == .external, Prefs.bool(PrefKey.antigravityAnswerFromNotch), answering[request.id] == nil,
            let session = session(for: request.sessionKey)
        else { return }
        let terminal = session.terminal
        let id = request.id
        Task.detached(priority: .userInitiated) {
            let menu = TerminalController.for(terminal)?.readScreen().flatMap(AntigravityMenu.parse)
            await MainActor.run { [weak self] in
                guard let self, self.engine.pending.contains(where: { $0.id == id }), self.externalMenus[id] != menu else { return }
                self.externalMenus[id] = menu
                self.updateHotKeys()
            }
        }
    }

    /// Answer by typing the option's number into the agent's terminal. The request is only
    /// cleared by the agent's own log confirming the answer, never optimistically.
    func answerExternal(_ request: PendingRequest, kind: AntigravityMenu.Kind) {
        guard answering[request.id] == nil, let session = session(for: request.sessionKey) else { return }
        answering[request.id] = kind
        answerErrors[request.id] = nil
        let terminal = session.terminal
        let id = request.id
        let label = "\(kind)"
        let model = self  // lives as long as the app; the task ends within ~3 s
        Task.detached(priority: .userInitiated) {
            func stillPending() async -> Bool {
                await MainActor.run { model.engine.pending.contains { $0.id == id } }
            }
            func fail(_ reason: String) async {
                await MainActor.run { model.externalAnswerFailed(id, reason: reason) }
            }
            guard let controller = TerminalController.for(terminal) else { return await fail("can't reach that terminal") }
            // Re-read right before typing: the menu must still be the newest thing on screen.
            guard let menu = controller.readScreen().flatMap(AntigravityMenu.parse) else {
                return await fail("its prompt isn't on screen")
            }
            let option: AntigravityMenu.Option? =
                switch kind {
                case .approve: menu.approve ?? menu.approveAlways
                case .approveAlways: menu.approveAlways
                case .deny, .other: menu.deny
                }
            guard let option else { return await fail("that choice isn't offered") }
            guard await stillPending() else { return }

            controller.type("\(option.number)")
            try? await Task.sleep(for: .milliseconds(800))
            // Some menus move the cursor on a digit and wait for Return.
            if await stillPending(), !controller.appendsReturn { controller.pressReturn() }
            for _ in 0..<11 where await stillPending() { try? await Task.sleep(for: .milliseconds(200)) }

            if await stillPending() {
                await fail("Antigravity didn't take the answer")
            } else {
                RequestLog.write("answered-from-notch(\(label))", id: id)
            }
        }
    }

    /// Preview renderer only.
    func previewSetMenu(_ menu: AntigravityMenu, for requestID: String) {
        externalMenus[requestID] = menu
    }

    private func externalAnswerFailed(_ id: String, reason: String) {
        RequestLog.write("answer-failed(\(reason))", id: id)
        answering[id] = nil
        guard let request = engine.pending.first(where: { $0.id == id }), let session = session(for: request.sessionKey) else { return }
        answerErrors[id] = "Couldn't answer from here: \(reason). Opened its terminal."
        externalMenus[id] = nil
        TerminalJumper.jump(to: session)
        updateHotKeys()
    }

    private func logNewExternalPrompts(since before: Set<String>) {
        for r in engine.pending where r.kind == .external && !before.contains(r.id) {
            RequestLog.write("received(external)", id: r.id, session: r.sessionKey, tool: r.toolName)
        }
    }

    private func bridgeClosed(_ id: String) {
        // Already answered or released: the connection closing is expected.
        guard connections.removeValue(forKey: id) != nil else { return }
        RequestLog.write("released(eof)", id: id)
        engine.bridgeClosed(requestID: id)
        publish()
        collapseIfIdle()
    }

    /// Release bridges whose request was settled somewhere else.
    private func release(_ ids: [String], reason: String) {
        for id in ids {
            RequestLog.write("released(\(reason))", id: id)
            connections.removeValue(forKey: id)?.reply(BridgeReply(stdout: nil))
        }
    }

    // MARK: Decisions

    func decide(_ request: PendingRequest, _ decision: PermissionDecision) {
        guard engine.resolve(requestID: request.id) != nil else {
            RequestLog.write("decided-too-late(\(RequestLog.label(decision)))", id: request.id, session: request.sessionKey)
            return
        }
        let connection = connections.removeValue(forKey: request.id)
        RequestLog.write(
            connection == nil ? "decided-no-bridge(\(RequestLog.label(decision)))" : "decided(\(RequestLog.label(decision)))",
            id: request.id, session: request.sessionKey, tool: request.toolName)
        connection?.reply(BridgeReply(stdout: decision.hookOutput()))
        publish()
        collapseIfIdle()
    }

    func allowCurrent() {
        guard let r = currentRequest, r.kind == .permission else { return }
        decide(r, .allow())
    }

    func denyCurrent() {
        guard let r = currentRequest, r.kind == .permission else { return }
        decide(r, .deny(message: "The user denied this from Orby."))
    }

    // MARK: Sessions

    func session(for key: String) -> AgentSession? { engine.sessions[key] }

    /// Preview renderer only: inject transcript-derived state without reading a file.
    func previewApply(_ info: TranscriptInfo, to key: String) {
        engine.apply(info, to: key)
        publish()
    }

    func jump(to session: AgentSession) {
        engine.markRead(sessionKey: session.id)
        publish()
        if Prefs.bool(PrefKey.clickToJump) { TerminalJumper.jump(to: session) }
        collapse()
    }

    func dismiss(_ session: AgentSession) {
        release(engine.remove(sessionKey: session.id), reason: "dismissed")
        publish()
    }

    private func prune() {
        let ttl = Prefs.double(PrefKey.finishedSessionTTLMinutes) * 60
        let before = engine.sessions.count
        release(engine.prune(doneTTL: ttl, isAlive: ProcessTree.isAlive), reason: "pruned")
        guard engine.sessions.count != before else { return }
        lastTranscriptRead = lastTranscriptRead.filter { engine.sessions[$0.key] != nil }
        transcripts = transcripts.filter { engine.sessions[$0.key] != nil }
        publish()
    }

    private func refreshTranscript(_ key: String, force: Bool) {
        guard let s = engine.sessions[key], let path = s.transcriptPath else { return }
        let now = Date()
        if !force, let last = lastTranscriptRead[key], now.timeIntervalSince(last) < 5 { return }
        lastTranscriptRead[key] = now
        let agent = s.agent
        let cached = transcripts[key]
        Task.detached(priority: .utility) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
            let mtime = attributes?[.modificationDate] as? Date ?? .distantPast
            // Nothing appended since the last read: reuse it instead of parsing the tail again.
            let info = cached.flatMap { $0.size == size && $0.mtime == mtime ? $0.info : nil }
                ?? TranscriptReader.read(path: path, agent: agent)
            await MainActor.run { [weak self] in
                guard let self, let phase = self.engine.sessions[key]?.phase else { return }
                let previous = self.transcripts[key]
                self.transcripts[key] = TranscriptRead(size: size, mtime: mtime, info: info, phase: phase)
                // The same reading in the same phase would change nothing; skip the re-publish.
                if let previous, previous.info == info, previous.phase == phase { return }
                self.engine.apply(info, to: key)
                if let limits = info.codexLimits { self.usage.update(codex: limits) }
                self.publish()
            }
        }
    }

    private func publish() {
        // Assigning an equal value still fires objectWillChange and re-renders every observer.
        let ordered = engine.orderedSessions
        if ordered != sessions { sessions = ordered }
        if engine.pending != pending { pending = engine.pending }
        updateIdleTab()
        let live = Set(pending.map(\.id))
        if externalMenus.keys.contains(where: { !live.contains($0) }) { externalMenus = externalMenus.filter { live.contains($0.key) } }
        if answering.keys.contains(where: { !live.contains($0) }) { answering = answering.filter { live.contains($0.key) } }
        if selectedRequestIndex >= pending.count { selectedRequestIndex = max(0, pending.count - 1) }
        updateHotKeys()
    }

    // MARK: Expansion

    private let debug = ProcessInfo.processInfo.environment["ORBY_DEBUG"] != nil

    func expand(_ reason: ExpansionReason) {
        if debug { NSLog("Orby: expand(\(reason))") }
        collapseWork?.cancel()
        if expansion == nil || reason == .attention { expansion = reason }
        if reason == .hover || reason == .click { mouseHasEntered = true }
        updateHotKeys()
    }

    func collapse() {
        if debug, expansion != nil { NSLog("Orby: collapse") }
        collapseWork?.cancel()
        expansion = nil
        highlightedSession = nil
        peekSessions = false
        mouseHasEntered = false
        tab = .sessions
        updateHotKeys()
    }

    func toggle() { isExpanded ? collapse() : expand(.click) }

    /// Mouse left the panel. Hover/click panels close; attention panels close only once seen.
    func mouseExited() {
        guard let reason = expansion else { return }
        if reason == .attention && !mouseHasEntered { return }
        scheduleCollapse(after: 0.35)
    }

    func mouseEntered() {
        collapseWork?.cancel()
        mouseHasEntered = true
    }

    /// A click somewhere else on screen. A request you haven't looked at yet stays open, since
    /// clicking into the terminal or editor right after it appears is the common case.
    func outsideClick() {
        guard let reason = expansion else { return }
        if reason == .attention, !pending.isEmpty, !mouseHasEntered { return }
        collapse()
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func collapseIfIdle() {
        if expansion == .attention, pending.isEmpty, !mouseHasEntered { scheduleCollapse(after: 0.6) }
    }

    private func handleReveal(_ reveal: RevealReason) {
        switch reveal {
        case .attention(let key):
            // Approvals always open the notch. "Terminal in front" can only be judged per app,
            // and one terminal app (Orca, iTerm) usually hosts many agents, so using it here
            // hid requests from every other tab.
            guard Prefs.bool(PrefKey.autoExpandAttention) else {
                RequestLog.write("reveal-off(attention)", id: "-", session: key)
                return
            }
            if let i = pending.firstIndex(where: { $0.sessionKey == key }) ?? engine.pending.firstIndex(where: { $0.sessionKey == key }) {
                selectedRequestIndex = i
            }
            tab = .sessions
            RequestLog.write("reveal(attention)", id: "-", session: key)
            expand(.attention)
        case .completed(let key):
            guard Prefs.bool(PrefKey.autoExpandCompletion), !terminalIsFrontmost(for: key), expansion == nil else { return }
            highlightedSession = key
            tab = .sessions
            expand(.completion)
            mouseHasEntered = false
            let seconds = max(1, Prefs.double(PrefKey.completionRevealSeconds))
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.expansion == .completion, !self.mouseHasEntered else { return }
                self.collapse()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }

    /// Don't pop over the very terminal the user is already looking at.
    private func terminalIsFrontmost(for key: String) -> Bool {
        guard Prefs.bool(PrefKey.quietWhenTerminalFocused),
            let bundleID = engine.sessions[key]?.terminal.bundleID,
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return false }
        return front == bundleID
    }

    // MARK: Shortcuts

    private func updateHotKeys() {
        let hk = HotKeyCenter.shared
        if isExpanded, currentRequest?.kind == .permission {
            hk.register(id: HotKeyID.allow, keyCode: KeyCodes.y, modifiers: KeyCodes.command) { [weak self] in self?.allowCurrent() }
            hk.register(id: HotKeyID.deny, keyCode: KeyCodes.n, modifiers: KeyCodes.command) { [weak self] in self?.denyCurrent() }
        } else if isExpanded, let r = currentRequest, r.kind == .external {
            if externalMenus[r.id] != nil {
                // Antigravity's menu is on screen: answer it like any other request.
                hk.register(id: HotKeyID.allow, keyCode: KeyCodes.y, modifiers: KeyCodes.command) { [weak self] in
                    guard let self, let r = self.currentRequest, r.kind == .external else { return }
                    self.answerExternal(r, kind: .approve)
                }
                hk.register(id: HotKeyID.deny, keyCode: KeyCodes.n, modifiers: KeyCodes.command) { [weak self] in
                    guard let self, let r = self.currentRequest, r.kind == .external else { return }
                    self.answerExternal(r, kind: .deny)
                }
            } else {
                // Can't be answered from here: ⌘Y takes you to the terminal that can.
                hk.register(id: HotKeyID.allow, keyCode: KeyCodes.y, modifiers: KeyCodes.command) { [weak self] in
                    guard let self, let r = self.currentRequest, let s = self.session(for: r.sessionKey) else { return }
                    self.jump(to: s)
                }
                hk.unregister(id: HotKeyID.deny)
            }
        } else {
            hk.unregister(id: HotKeyID.allow)
            hk.unregister(id: HotKeyID.deny)
        }

        let optionCount = isExpanded && currentRequest?.kind == .question
            ? min(9, currentRequest?.questions.map(\.options.count).max() ?? 0) : 0
        for i in 0..<9 {
            if i < optionCount {
                hk.register(id: HotKeyID.option(i), keyCode: KeyCodes.digits[i], modifiers: KeyCodes.command) { [weak self] in
                    self?.optionShortcut.send(i)
                }
            } else {
                hk.unregister(id: HotKeyID.option(i))
            }
        }
    }

    // MARK: Collapsed tab summary

    /// Finished/idle sessions stop showing in the collapsed notch once the last activity is
    /// `idleHideSeconds` old; anything working or waiting keeps it visible.
    private func updateIdleTab() {
        idleWork?.cancel()
        let busy = sessions.contains { $0.phase.group == .working || $0.phase.needsUser } || !pending.isEmpty
        guard !busy, let last = sessions.map(\.updatedAt).max() else {
            if idleTab { idleTab = false }
            return
        }
        let delay = max(1, Prefs.double(PrefKey.idleHideSeconds))
        let remaining = delay - Date().timeIntervalSince(last)
        if remaining <= 0 {
            if !idleTab { idleTab = true }
        } else {
            if idleTab { idleTab = false }
            let work = DispatchWorkItem { [weak self] in self?.updateIdleTab() }
            idleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.05, execute: work)
        }
    }

    var attentionCount: Int { sessions.filter { $0.phase.needsUser }.count }
    var workingCount: Int { sessions.filter { $0.phase.group == .working }.count }
    var unreadCount: Int { sessions.filter(\.unread).count }
    var leadSession: AgentSession? { sessions.first }

    /// One working session per agent kind, when several different agents are busy at once.
    /// Empty while something needs you, so the attention orb stays put.
    var concurrentAgents: [AgentSession] {
        guard leadSession?.phase.group != .needsYou else { return [] }
        var seen = Set<AgentKind>()
        let pool = sessions.filter { $0.phase.group == .working && seen.insert($0.agent).inserted }
        return pool.count > 1 ? pool : []
    }
}

struct NotchMetrics: Equatable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var screenFrame: CGRect

    static let fallback = NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 32, screenFrame: .zero)

    static func of(_ screen: NSScreen) -> NotchMetrics {
        let widthOverride = CGFloat(Prefs.double(PrefKey.notchWidthOverride))
        let heightOverride = CGFloat(Prefs.double(PrefKey.notchHeightOverride))
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchMetrics(
                hasNotch: true,
                notchWidth: widthOverride > 0 ? widthOverride : screen.frame.width - left.width - right.width,
                notchHeight: heightOverride > 0 ? heightOverride : top,
                screenFrame: screen.frame)
        }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchMetrics(
            hasNotch: false, notchWidth: widthOverride > 0 ? widthOverride : 0,
            notchHeight: heightOverride > 0 ? heightOverride : menuBar, screenFrame: screen.frame)
    }
}

/// The last transcript reading of a session, and the file state and phase it was taken at.
private struct TranscriptRead: Sendable {
    var size: UInt64
    var mtime: Date
    var info: TranscriptInfo
    var phase: SessionPhase
}
