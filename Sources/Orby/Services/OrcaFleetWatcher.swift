import Foundation
import NotchCore
import NotchShared

/// Asks Orca which terminals are orchestration workers and which terminal dispatched each one.
/// Callers ask only about terminals they haven't checked yet, so nothing polls. Blocks on the CLI.
actor OrcaFleetWatcher {
    /// Task lists by run. A run only gains tasks, so a missing task id refetches its run.
    private var tasks: [String: [String: OrcaFleet.TaskInfo]] = [:]

    func lookup(_ handles: Set<String>, appPath: String?) -> [String: OrcaWorker] {
        guard let cli = TerminalJumper.orcaCLI(appPath: appPath),
            let list = Self.json(cli, ["orchestration", "worker-list", "--json"])
        else { return [:] }
        var out: [String: OrcaWorker] = [:]
        for (handle, d) in OrcaFleet.dispatches(list) where handles.contains(handle) {
            if tasks[d.run]?[d.task] == nil, let json = Self.json(cli, ["orchestration", "task-list", "--run", d.run, "--json"]) {
                tasks[d.run] = OrcaFleet.tasks(json)
            }
            guard let info = tasks[d.run]?[d.task] else { continue }
            out[handle] = OrcaWorker(handle: handle, parent: info.parent, task: info.title)
        }
        return out
    }

    private var worktreeCache: (at: Date, list: [OrcaWorktree])?

    /// Checkouts Orca can open a terminal in, cached for a minute (the launcher asks each time it opens).
    func worktrees(appPath: String?) -> [OrcaWorktree] {
        if let c = worktreeCache, Date().timeIntervalSince(c.at) < 60 { return c.list }
        guard let cli = TerminalJumper.orcaCLI(appPath: appPath), let json = Self.json(cli, ["worktree", "list", "--json"]) else { return [] }
        let list = OrcaFleet.worktrees(json)
        worktreeCache = (Date(), list)
        return list
    }

    private static func json(_ cli: String, _ args: [String]) -> JSONValue? {
        TerminalJumper.run(cli, args).flatMap { try? JSONValue.decode(Data($0.utf8)) }
    }
}
