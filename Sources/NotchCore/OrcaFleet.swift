import Foundation
import NotchShared

/// An Orca orchestration worker, linked to the terminal that dispatched it.
public struct OrcaWorker: Hashable, Sendable {
    /// The worker's own `term_…` handle.
    public var handle: String
    /// Handle of the terminal that created its task (the coordinator, or a worker one level up).
    public var parent: String
    /// The task's display name, e.g. "Review BE PR #146".
    public var task: String?

    public init(handle: String, parent: String, task: String?) {
        self.handle = handle
        self.parent = parent
        self.task = task
    }
}

/// A checkout Orca knows, where it can open a terminal.
public struct OrcaWorktree: Hashable, Sendable {
    public var path: String
    public var branch: String?

    public init(path: String, branch: String?) {
        self.path = path
        self.branch = branch
    }
}

/// Reads `orca orchestration` output and nests worker sessions under the session that started them.
public enum OrcaFleet {
    public struct Dispatch: Hashable, Sendable {
        public var run: String
        public var task: String
    }

    public struct TaskInfo: Hashable, Sendable {
        public var parent: String
        public var title: String?
    }

    /// `worker-list --json`: worker terminal handle → its run and task.
    public static func dispatches(_ json: JSONValue) -> [String: Dispatch] {
        var out: [String: Dispatch] = [:]
        // Newest first: keep a reused terminal's latest dispatch.
        for w in json["result"]?["workers"]?.array ?? [] {
            guard let handle = w["agentTerminalHandle"]?.string, out[handle] == nil,
                let run = w["runId"]?.string, let task = w["taskId"]?.string
            else { continue }
            out[handle] = Dispatch(run: run, task: task)
        }
        return out
    }

    /// `task-list --run <id> --json`: task id → who created it and its name.
    public static func tasks(_ json: JSONValue) -> [String: TaskInfo] {
        var out: [String: TaskInfo] = [:]
        for t in json["result"]?["tasks"]?.array ?? [] {
            guard let id = t["id"]?.string, let parent = t["created_by_terminal_handle"]?.string else { continue }
            let title = [t["display_name"], t["task_title"]].lazy.compactMap { $0?.string }.first { !$0.isEmpty }
            out[id] = TaskInfo(parent: parent, title: title)
        }
        return out
    }

    /// `worktree list --json`, without archived or bare checkouts.
    public static func worktrees(_ json: JSONValue) -> [OrcaWorktree] {
        (json["result"]?["worktrees"]?.array ?? []).compactMap { w in
            guard let path = w["path"]?.string, !path.isEmpty, w["isArchived"]?.bool != true, w["isBare"]?.bool != true else { return nil }
            let branch = w["branch"]?.string.map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst(11)) : $0 }
            return OrcaWorktree(path: path, branch: branch)
        }
    }

    /// The worktree holding `dir`, the innermost when checkouts nest.
    public static func worktree(containing dir: String, in worktrees: [OrcaWorktree]) -> OrcaWorktree? {
        worktrees.filter { dir == $0.path || dir.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }
    }

    /// Splits sessions into top-level rows and the workers listed under each session (by session id).
    /// A worker whose parent has no session here stays top-level. Order is kept.
    public static func nest(_ sessions: [AgentSession], workers: [String: OrcaWorker])
        -> (top: [AgentSession], children: [String: [AgentSession]])
    {
        var byHandle: [String: AgentSession] = [:]
        for s in sessions {
            if let h = s.terminal.orcaTerminal, byHandle[h] == nil { byHandle[h] = s }
        }
        func parent(of s: AgentSession) -> AgentSession? {
            guard let h = s.terminal.orcaTerminal, let p = workers[h].flatMap({ byHandle[$0.parent] }), p.id != s.id else { return nil }
            return p
        }
        // A worker can't nest under its own descendant (a cycle in bad data would hide both).
        func nests(_ s: AgentSession) -> Bool {
            var seen: Set<String> = [s.id]
            var at = s
            while let p = parent(of: at) {
                guard seen.insert(p.id).inserted else { return false }
                at = p
            }
            return seen.count > 1
        }
        var top: [AgentSession] = []
        var children: [String: [AgentSession]] = [:]
        for s in sessions {
            if nests(s), let p = parent(of: s) {
                children[p.id, default: []].append(s)
            } else {
                top.append(s)
            }
        }
        return (top, children)
    }
}
