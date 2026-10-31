import Foundation

/// One hook invocation, sent by the bridge to the app as a single JSON line.
public struct BridgeEnvelope: Codable, Sendable {
    public var version: Int
    public var id: String
    /// Which agent ran the hook: "claude", "codex", ...
    public var source: String
    /// The raw hook input the agent wrote to the bridge's stdin.
    public var payload: JSONValue
    /// Terminal-identifying environment variables (TERM_PROGRAM, ITERM_SESSION_ID, TMUX_PANE, ...).
    public var env: [String: String]
    /// PID of the agent process (first non-shell ancestor of the bridge).
    public var agentPID: Int32?
    public var tty: String?
    /// Ancestors of the bridge, nearest first. Used to find the hosting terminal/IDE app.
    public var processChain: [ProcessEntry]
    /// True when the bridge is blocking for a decision (PermissionRequest).
    public var expectsReply: Bool
    public var sentAt: Date

    public init(
        id: String = UUID().uuidString, source: String, payload: JSONValue, env: [String: String] = [:],
        agentPID: Int32? = nil, tty: String? = nil, processChain: [ProcessEntry] = [], expectsReply: Bool = false,
        sentAt: Date = Date()
    ) {
        self.version = 1
        self.id = id
        self.source = source
        self.payload = payload
        self.env = env
        self.agentPID = agentPID
        self.tty = tty
        self.processChain = processChain
        self.expectsReply = expectsReply
        self.sentAt = sentAt
    }

    public var eventName: String { payload["hook_event_name"]?.string ?? payload["hookEventName"]?.string ?? "" }
    public var sessionID: String? {
        // Cursor's payloads also carry a session_id, but only on session start and end.
        payload["conversation_id"]?.string ?? payload["session_id"]?.string ?? payload["sessionId"]?.string
            ?? payload["conversationId"]?.string
    }
}

public struct ProcessEntry: Codable, Sendable, Hashable {
    public var pid: Int32
    public var name: String
    public var path: String?

    public init(pid: Int32, name: String, path: String?) {
        self.pid = pid
        self.name = name
        self.path = path
    }
}

/// The app's answer to a blocking envelope. `stdout` is printed verbatim by the bridge;
/// nil means "no opinion" and the agent falls back to its own terminal prompt.
public struct BridgeReply: Codable, Sendable {
    public var stdout: JSONValue?

    public init(stdout: JSONValue?) { self.stdout = stdout }
}

/// Events for which the agent waits on hook stdout for a decision.
public let blockingEvents: Set<String> = ["PermissionRequest"]

/// What an Antigravity hook prints when Orby has no opinion. Antigravity requires a
/// `decision` from PreToolUse; "allow" defers to the next hook or the user's own policy.
public func antigravityPassthrough(event: String) -> JSONValue {
    event == "PreToolUse" ? ["decision": "allow"] : .object([:])
}

/// Environment variables the bridge forwards so the app can jump to the right tab/pane.
public let terminalEnvKeys: [String] = [
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ITERM_SESSION_ID",
    "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "WEZTERM_PANE", "WEZTERM_UNIX_SOCKET",
    "GHOSTTY_RESOURCES_DIR", "WARP_TERMINAL_SESSION_UUID", "ZELLIJ", "ZELLIJ_SESSION_NAME",
    "__CFBundleIdentifier", "VSCODE_PID", "CURSOR_TRACE_ID",
    // Orca: which tab/pane hosts the agent, for `orca terminal switch`; the handle links orchestration workers.
    "ORCA_TAB_ID", "ORCA_AGENT_PANE", "ORCA_TERMINAL_HANDLE",
]

public let wireJSONEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .secondsSince1970
    e.outputFormatting = [.withoutEscapingSlashes]
    return e
}()

public let wireJSONDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .secondsSince1970
    return d
}()
