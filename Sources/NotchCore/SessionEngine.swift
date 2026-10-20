import Foundation
import NotchShared

/// Pure state machine: hook envelopes in, sessions + pending requests out.
/// The app wraps it in an ObservableObject; tests drive it directly.
public struct SessionEngine: Sendable {
    public private(set) var sessions: [String: AgentSession] = [:]
    public private(set) var pending: [PendingRequest] = []

    /// Antigravity prompt seen in its log before any hook told us which session it belongs to.
    private struct ParkedPrompt: Hashable, Sendable {
        var tool: String
        var step: Int
        var logID: String
        var at: Date
    }
    private var parkedPrompts: [ParkedPrompt] = []
    /// Antigravity log file → session key, learned from earlier matches in that log.
    private var logSessions: [String: String] = [:]

    public struct Outcome: Equatable, Sendable {
        public var sessionKey: String?
        public var cue: SoundCue?
        public var reveal: RevealReason?
        /// Requests that were answered elsewhere (terminal) and whose bridge should be released.
        public var cancelledRequests: [String] = []
        /// Transcript tail worth re-reading (turn ended, compaction finished, ...).
        public var refreshTranscript = false
    }

    public init() {}

    public static func sessionKey(source: String, sessionID: String) -> String { "\(source):\(sessionID)" }

    public mutating func handle(_ env: BridgeEnvelope, now: Date = Date()) -> Outcome {
        var out = Outcome()
        guard let sid = env.sessionID else { return out }
        let agent = AgentKind(source: env.source)
        let p = agent == .antigravity ? AntigravityPayload.normalized(env.payload) : env.payload
        let key = Self.sessionKey(source: agent.rawValue, sessionID: sid)
        out.sessionKey = key
        let event = p["hook_event_name"]?.string ?? env.eventName

        if event == "SessionEnd" {
            out.cancelledRequests = remove(sessionKey: key)
            return out
        }

        var s = sessions[key] ?? AgentSession(agent: agent, sessionID: sid, cwd: p["cwd"]?.string ?? "", now: now)
        if let cwd = p["cwd"]?.string, !cwd.isEmpty, cwd != s.cwd || s.git == nil {
            s.cwd = cwd
            s.git = GitInfo.resolve(cwd: cwd)
        }
        if let t = p["transcript_path"]?.string { s.transcriptPath = t }
        if let m = p["model"]?.string { s.model = m }
        s.terminal = TerminalContext(envelope: env).merged(over: s.terminal)
        s.updatedAt = now

        switch event {
        case "SessionStart":
            if sessions[key] == nil { out.cue = .start }
            s.phase = .ready

        case "UserPromptSubmit":
            let prompt = p["prompt"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prompt, !prompt.isEmpty {
                s.lastPrompt = prompt
                if s.title == nil { s.title = ToolDescriber.firstLine(prompt, max: 80) }
            }
            s.phase = .thinking
            s.activity = nil
            s.attention = nil
            s.thinking = nil
            s.unread = false
            out.cancelledRequests = cancelPending { $0.sessionKey == key }

        case "PreToolUse":
            // A new tool only starts once the previous permission was settled (in the notch or
            // the terminal), so older requests from this agent are stale.
            // Antigravity's hook and its prompt for the same step can arrive in either order.
            let scope = p["agent_id"]?.string ?? ""
            let step = p["step_idx"]?.int
            out.cancelledRequests = cancelPending {
                $0.sessionKey == key && $0.agentScope == scope && $0.receivedAt < now && (step == nil || $0.step != step)
            }
            s.phase = .working
            s.activity = activity(p)
            s.attention = nil
            s.thinking = nil
            s.lastToolStep = step
            s.lastToolName = p["tool_name"]?.string
            s.lastToolInput = p["tool_input"]
            if let step { attachExternalPrompt(step: step, to: &s, now: now, out: &out) }

        case "PostToolUse", "PostToolUseFailure":
            // Same tool + same input finished → its permission was settled in the terminal.
            let tool = p["tool_name"]?.string
            let input = p["tool_input"]
            out.cancelledRequests = cancelPending {
                $0.sessionKey == key && $0.toolName == tool && (input == nil || $0.toolInput == input)
            }
            if !hasPending(key) {
                // Tool finished; the model is reasoning about the result until its next call.
                s.phase = .thinking
                s.activity = nil
                s.attention = nil
                s.thinking = nil
            }

        case "PermissionRequest":
            let tool = p["tool_name"]?.string ?? "Tool"
            let input = p["tool_input"] ?? .object([:])
            let kind: RequestKind =
                switch tool {
                case "AskUserQuestion": .question
                case "ExitPlanMode": .plan
                default: .permission
                }
            if env.expectsReply {
                // An agent shows one permission prompt at a time: a new request supersedes any
                // older one still listed, which would otherwise take clicks meant for this one.
                let scope = p["agent_id"]?.string ?? ""
                out.cancelledRequests = cancelPending { $0.sessionKey == key && $0.agentScope == scope }
                var request = PendingRequest(
                    id: env.id, sessionKey: key, kind: kind, toolName: tool, toolInput: input,
                    summary: ToolDescriber.describe(tool: tool, input: input),
                    suggestions: p["permission_suggestions"]?.array ?? [], receivedAt: now)
                request.agentScope = scope
                // Newest first: the request that just appeared is the one on screen.
                pending.insert(request, at: 0)
            }
            s.phase =
                switch kind {
                case .question: .needsAnswer
                case .plan: .planReview
                case .permission, .external: .needsApproval
                }
            let activity = ToolDescriber.activity(tool: tool, input: input)
            s.activity = activity
            s.attention = kind == .permission ? "Wants to \(activity.intent)" : activity.progressive
            out.cue =
                switch kind {
                case .question: .question
                case .plan: .plan
                case .permission, .external: .approval
                }
            out.reveal = .attention(key)

        case "Notification":
            switch p["notification_type"]?.string {
            case "permission_prompt" where !hasPending(key):
                // Agent is asking in the terminal (e.g. we weren't running when it started).
                s.phase = .needsApproval
                s.attention = p["message"]?.string.map { PlainText.summary($0, max: 120) } ?? s.attention
                out.cue = .approval
                out.reveal = .attention(key)
            case "idle_prompt":
                if s.phase != .done { s.phase = .waitingInput }
            default:
                break
            }

        case "Stop", "Interrupt":
            s.phase = .done
            s.activity = nil
            s.attention = nil
            s.thinking = nil
            s.activeSubagents = 0
            s.unread = true
            out.cancelledRequests = cancelPending { $0.sessionKey == key }
            out.cue = .done
            out.reveal = .completed(key)
            out.refreshTranscript = true

        case "StopFailure":
            s.phase = .error
            s.lastMessage = (p["error"]?.string ?? p["message"]?.string).map { PlainText.summary($0, max: 160) } ?? "Turn failed"
            out.cue = .error
            out.reveal = .attention(key)

        case "SubagentStart":
            s.activeSubagents += 1
        case "SubagentStop":
            s.activeSubagents = max(0, s.activeSubagents - 1)

        case "PreCompact":
            s.phase = .compacting
        case "PostCompact":
            s.phase = .thinking
            out.refreshTranscript = true

        default:
            break
        }

        sessions[key] = s
        return out
    }

    private func activity(_ p: JSONValue) -> Activity? {
        guard let tool = p["tool_name"]?.string else { return nil }
        return ToolDescriber.activity(tool: tool, input: p["tool_input"] ?? .object([:]))
    }

    // MARK: External prompts (Antigravity)

    /// Antigravity's log says it is showing a permission prompt for `step`.
    public mutating func externalPromptShown(tool: String, step: Int, logID: String, now: Date = Date()) -> Outcome {
        var out = Outcome()
        let candidates = sessions.values.filter { $0.agent == .antigravity }
        let exact = candidates.filter { $0.lastToolStep == step && AntigravityLog.toolMatches(tool, $0.lastToolName) }
            .max { $0.updatedAt < $1.updatedAt }
        let sameLog = logSessions[logID].flatMap { sessions[$0] }
        let recent = candidates.filter { now.timeIntervalSince($0.updatedAt) < 120 }.max { $0.updatedAt < $1.updatedAt }
        guard var s = exact ?? sameLog ?? recent else {
            // No hook seen yet (e.g. the app started mid-conversation): wait for one.
            parkedPrompts.append(ParkedPrompt(tool: tool, step: step, logID: logID, at: now))
            return out
        }
        logSessions[logID] = s.id
        addExternalPrompt(tool: tool, step: step, logID: logID, to: &s, now: now, out: &out)
        sessions[s.id] = s
        return out
    }

    /// Antigravity's log says the prompt for `step` was answered in its terminal.
    public mutating func externalPromptAnswered(
        conversationID: String, step: Int, approved: Bool, logID: String, now: Date = Date()
    ) -> Outcome {
        var out = Outcome()
        let key = Self.sessionKey(source: AgentKind.antigravity.rawValue, sessionID: conversationID)
        if sessions[key] != nil { logSessions[logID] = key }
        let id = Self.externalID(logID: logID, step: step)
        out.cancelledRequests = cancelPending { $0.id == id || ($0.kind == .external && $0.sessionKey == key && $0.step == step) }
        parkedPrompts.removeAll { $0.logID == logID && $0.step == step }
        if var s = sessions[key], !hasPending(key) {
            s.phase = approved ? .working : .thinking
            s.attention = nil
            s.updatedAt = now
            sessions[key] = s
        }
        out.sessionKey = sessions[key] != nil ? key : nil
        return out
    }

    static func externalID(logID: String, step: Int) -> String { "agy:\(logID):\(step)" }

    /// A PreToolUse arrived: attach a parked prompt for this step, or refresh one already shown.
    private mutating func attachExternalPrompt(step: Int, to s: inout AgentSession, now: Date, out: inout Outcome) {
        guard s.agent == .antigravity else { return }
        parkedPrompts.removeAll { now.timeIntervalSince($0.at) > 120 }
        if let i = parkedPrompts.firstIndex(where: { $0.step == step && AntigravityLog.toolMatches($0.tool, s.lastToolName) }) {
            let parked = parkedPrompts.remove(at: i)
            logSessions[parked.logID] = s.id
            addExternalPrompt(tool: parked.tool, step: step, logID: parked.logID, to: &s, now: now, out: &out)
        } else if let i = pending.firstIndex(where: { $0.sessionKey == s.id && $0.kind == .external && $0.step == step }) {
            // The prompt surfaced before its hook: fill in the real command now.
            let tool = s.lastToolName ?? pending[i].toolName
            let input = s.lastToolInput ?? pending[i].toolInput
            pending[i].toolName = tool
            pending[i].toolInput = input
            pending[i].summary = ToolDescriber.describe(tool: tool, input: input)
            let activity = ToolDescriber.activity(tool: tool, input: input)
            s.activity = activity
            s.phase = .needsApproval
            s.attention = "Wants to \(activity.intent)"
        }
    }

    private mutating func addExternalPrompt(
        tool: String, step: Int, logID: String, to s: inout AgentSession, now: Date, out: inout Outcome
    ) {
        let id = Self.externalID(logID: logID, step: step)
        guard !pending.contains(where: { $0.id == id }) else { return }
        let matched = s.lastToolStep == step && AntigravityLog.toolMatches(tool, s.lastToolName)
        let toolName = matched ? (s.lastToolName ?? tool) : AntigravityLog.hookToolName(tool)
        let input = matched ? (s.lastToolInput ?? .object([:])) : .object([:])
        var request = PendingRequest(
            id: id, sessionKey: s.id, kind: .external, toolName: toolName, toolInput: input,
            summary: ToolDescriber.describe(tool: toolName, input: input), suggestions: [], receivedAt: now)
        request.step = step
        pending.insert(request, at: 0)
        let activity = ToolDescriber.activity(tool: toolName, input: input)
        s.phase = .needsApproval
        s.activity = activity
        s.attention = "Wants to \(activity.intent)"
        s.updatedAt = now
        out.sessionKey = s.id
        out.cue = .approval
        out.reveal = .attention(s.id)
    }

    public func hasPending(_ sessionKey: String) -> Bool { pending.contains { $0.sessionKey == sessionKey } }

    private mutating func cancelPending(where match: (PendingRequest) -> Bool) -> [String] {
        let ids = pending.filter(match).map(\.id)
        pending.removeAll(where: match)
        return ids
    }

    /// The user decided in the notch. Returns the request so the caller can reply to its bridge.
    public mutating func resolve(requestID: String, now: Date = Date()) -> PendingRequest? {
        guard let i = pending.firstIndex(where: { $0.id == requestID }) else { return nil }
        let req = pending.remove(at: i)
        if var s = sessions[req.sessionKey], !hasPending(req.sessionKey) {
            s.phase = .working
            s.attention = nil
            s.updatedAt = now
            sessions[req.sessionKey] = s
        }
        return req
    }

    /// The bridge disconnected (agent killed the hook because the user answered in the terminal).
    public mutating func bridgeClosed(requestID: String) {
        _ = resolve(requestID: requestID)
    }

    @discardableResult
    public mutating func remove(sessionKey: String) -> [String] {
        sessions[sessionKey] = nil
        return cancelPending { $0.sessionKey == sessionKey }
    }

    public mutating func markRead(sessionKey: String) {
        sessions[sessionKey]?.unread = false
    }

    public mutating func apply(_ info: TranscriptInfo, to sessionKey: String) {
        guard var s = sessions[sessionKey] else { return }
        if let m = info.model { s.model = m }
        if let t = info.contextTokens { s.contextTokens = t }
        if let l = info.contextLimit { s.contextLimit = l }
        if let text = info.lastAssistantText {
            let summary = PlainText.summary(text, max: 160)
            if !summary.isEmpty { s.lastMessage = summary }
        }
        if let b = info.gitBranch, s.git != nil, s.git?.branch == nil { s.git?.branch = b }
        s.thinking = s.phase == .thinking
            ? info.latestThinking.map { PlainText.latest($0, max: 140) }.flatMap { $0.isEmpty ? nil : $0 }
            : nil
        sessions[sessionKey] = s
    }

    /// Drop sessions whose agent process exited, and finished sessions older than `doneTTL`.
    public mutating func prune(now: Date = Date(), doneTTL: TimeInterval, isAlive: (Int32) -> Bool) -> [String] {
        var cancelled: [String] = []
        for (key, s) in sessions {
            let dead = s.terminal.agentPID.map { !isAlive($0) } ?? false
            let stale = !s.phase.needsUser && s.phase.group != .working && now.timeIntervalSince(s.updatedAt) > doneTTL
            if dead || stale { cancelled += remove(sessionKey: key) }
        }
        return cancelled
    }

    /// Sorted for display: needs-you first, then working, then finished; newest first within a group.
    public var orderedSessions: [AgentSession] {
        sessions.values.sorted {
            ($0.phase.group, $1.updatedAt) < ($1.phase.group, $0.updatedAt)
        }
    }
}
