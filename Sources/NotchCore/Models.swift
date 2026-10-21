import Foundation
import NotchShared

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude, codex, antigravity, opencode, pi, commandcode, qwen, cursor, unknown

    public init(source: String) { self = AgentKind(rawValue: source) ?? .unknown }

    /// Cursor runs the hooks in ~/.claude/settings.json too, so some "claude" envelopes are Cursor's.
    public init(envelope: BridgeEnvelope) {
        self = envelope.source == "claude" && envelope.payload["cursor_version"] != nil ? .cursor : AgentKind(source: envelope.source)
    }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .commandcode: "Command Code"
        case .qwen: "Qwen Code"
        case .cursor: "Cursor"
        case .unknown: "Agent"
        }
    }
}

public enum SessionPhase: String, Codable, Sendable {
    /// `thinking`: the model is reasoning between steps (after a prompt or a finished tool,
    /// before the next tool call). `working`: a tool is running.
    case ready, thinking, working, compacting, waitingInput, needsApproval, needsAnswer, planReview, done, error

    public var needsUser: Bool { [.needsApproval, .needsAnswer, .planReview].contains(self) }

    public var label: String {
        switch self {
        case .ready: "Ready"
        case .thinking: "Thinking"
        case .working: "Working"
        case .compacting: "Compacting"
        case .waitingInput: "Waiting for input"
        case .needsApproval: "Needs approval"
        case .needsAnswer: "Question"
        case .planReview: "Plan ready"
        case .done: "Done"
        case .error: "Error"
        }
    }

    /// AgentNotch-style buckets: Needs you / Working / Finished.
    public var group: StatusGroup {
        switch self {
        case .needsApproval, .needsAnswer, .planReview, .error: .needsYou
        case .thinking, .working, .compacting: .working
        case .ready, .waitingInput, .done: .finished
        }
    }
}

public enum StatusGroup: Int, Comparable, Sendable {
    case needsYou = 0, working, finished
    public static func < (a: StatusGroup, b: StatusGroup) -> Bool { a.rawValue < b.rawValue }
}

/// Everything needed to bring the session's terminal tab back to the front.
public struct TerminalContext: Codable, Hashable, Sendable {
    public var termProgram: String?
    public var appBundlePath: String?
    public var bundleID: String?
    public var tty: String?
    public var itermSessionID: String?
    public var terminalSessionID: String?
    public var tmuxPane: String?
    public var tmuxSocket: String?
    public var kittyWindowID: String?
    public var kittyListenOn: String?
    public var weztermPane: String?
    public var orcaTabID: String?
    /// "<tabId>:<paneId>" from ORCA_AGENT_PANE.
    public var orcaPane: String?
    public var agentPID: Int32?

    public init() {}

    public init(envelope: BridgeEnvelope) {
        let env = envelope.env
        termProgram = env["TERM_PROGRAM"]
        itermSessionID = env["ITERM_SESSION_ID"]
        terminalSessionID = env["TERM_SESSION_ID"]
        tmuxPane = env["TMUX_PANE"]
        // $TMUX is "socket_path,server_pid,session_index".
        tmuxSocket = env["TMUX"].flatMap { $0.split(separator: ",").first.map(String.init) }
        kittyWindowID = env["KITTY_WINDOW_ID"]
        kittyListenOn = env["KITTY_LISTEN_ON"]
        weztermPane = env["WEZTERM_PANE"]
        orcaTabID = env["ORCA_TAB_ID"]
        orcaPane = env["ORCA_AGENT_PANE"]
        tty = envelope.tty
        agentPID = envelope.agentPID
        appBundlePath = envelope.processChain.lazy.compactMap { $0.path.flatMap(ProcessTree.outermostAppBundle) }.first
        bundleID = env["__CFBundleIdentifier"]
        if let path = appBundlePath, let id = Bundle(path: path)?.bundleIdentifier { bundleID = id }
    }

    /// Keep previously learned identifiers when a later event lacks them.
    public func merged(over old: TerminalContext) -> TerminalContext {
        var m = self
        m.termProgram = termProgram ?? old.termProgram
        m.appBundlePath = appBundlePath ?? old.appBundlePath
        m.bundleID = bundleID ?? old.bundleID
        m.tty = tty ?? old.tty
        m.itermSessionID = itermSessionID ?? old.itermSessionID
        m.terminalSessionID = terminalSessionID ?? old.terminalSessionID
        m.tmuxPane = tmuxPane ?? old.tmuxPane
        m.tmuxSocket = tmuxSocket ?? old.tmuxSocket
        m.kittyWindowID = kittyWindowID ?? old.kittyWindowID
        m.kittyListenOn = kittyListenOn ?? old.kittyListenOn
        m.weztermPane = weztermPane ?? old.weztermPane
        m.orcaTabID = orcaTabID ?? old.orcaTabID
        m.orcaPane = orcaPane ?? old.orcaPane
        m.agentPID = agentPID ?? old.agentPID
        return m
    }
}

public struct AgentSession: Identifiable, Hashable, Sendable {
    public var id: String
    public var agent: AgentKind
    public var sessionID: String
    public var cwd: String
    public var git: GitInfo?
    public var title: String?
    public var lastPrompt: String?
    public var lastMessage: String?
    /// The tool call in progress, phrased for people (with the raw command in `detail`).
    public var activity: Activity?
    public var currentTool: String? { activity?.progressive }
    /// What the session needs from the user, e.g. "Wants to install dependencies".
    public var attention: String?
    /// Latest reasoning snippet while `phase == .thinking`, when the transcript exposes it.
    public var thinking: String?
    public var phase: SessionPhase
    public var startedAt: Date
    public var updatedAt: Date
    public var model: String?
    public var contextTokens: Int?
    public var contextLimit: Int?
    public var activeSubagents: Int
    public var terminal: TerminalContext
    public var transcriptPath: String?
    /// Set when a turn finishes and cleared once the user looks at it.
    public var unread: Bool
    /// Last tool call seen in a PreToolUse hook. Antigravity prompts are matched to it by step.
    public var lastToolStep: Int?
    public var lastToolName: String?
    public var lastToolInput: JSONValue?

    public init(agent: AgentKind, sessionID: String, cwd: String, now: Date) {
        self.id = "\(agent.rawValue):\(sessionID)"
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.phase = .ready
        self.startedAt = now
        self.updatedAt = now
        self.activeSubagents = 0
        self.terminal = TerminalContext()
        self.unread = false
    }

    public var projectName: String {
        git?.projectName ?? (cwd as NSString).lastPathComponent
    }

    public var contextPercent: Double? {
        guard let used = contextTokens, let limit = contextLimit, limit > 0 else { return nil }
        return min(1, Double(used) / Double(limit))
    }
}

public enum RequestKind: String, Sendable {
    case permission, question, plan
    /// A prompt the agent shows in its own terminal that Orby can't answer
    /// (Antigravity): the notch alerts and jumps there instead.
    case external
}

public struct QuestionOption: Hashable, Sendable {
    public var label: String
    public var detail: String?
}

public struct Question: Hashable, Sendable {
    public var question: String
    public var header: String?
    public var options: [QuestionOption]
    public var multiSelect: Bool
}

/// A blocked agent waiting for the user to decide something.
public struct PendingRequest: Identifiable, Hashable, Sendable {
    public var id: String
    public var sessionKey: String
    public var kind: RequestKind
    public var toolName: String
    public var toolInput: JSONValue
    public var summary: String
    /// Claude's `permission_suggestions`, replayed as `updatedPermissions` for "Always allow".
    public var suggestions: [JSONValue]
    public var receivedAt: Date
    /// Subagent id when the hook payload carries one; "" for the main agent.
    public var agentScope: String = ""
    /// Agent step index (Antigravity), so a hook for the same step doesn't release it.
    public var step: Int?

    public var questions: [Question] { QuestionParser.parse(toolInput) }
    public var planMarkdown: String? { toolInput["plan"]?.string }
}

public enum SoundCue: String, CaseIterable, Codable, Sendable {
    case approval, question, plan, done, error, start

    public var label: String {
        switch self {
        case .approval: "Permission request"
        case .question: "Question"
        case .plan: "Plan ready"
        case .done: "Task complete"
        case .error: "Error"
        case .start: "Session start"
        }
    }
}

public enum RevealReason: Sendable, Equatable {
    case attention(String)  // session key
    case completed(String)
}
