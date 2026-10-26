import Foundation
import NotchShared

/// The agent's own to-do list, as last written by TodoWrite (Claude, and agents aliased to it)
/// or `update_plan` (Codex).
public struct TaskList: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public enum Status: String, Sendable { case pending, inProgress, completed }
        public var title: String
        public var status: Status
        /// Present-tense phrasing for the item in progress ("Running the tests"), when the agent gives one.
        public var activeTitle: String?
    }

    public var items: [Item]

    public var total: Int { items.count }
    public var done: Int { items.filter { $0.status == .completed }.count }
    public var isFinished: Bool { !items.isEmpty && done == total }
    /// What the agent is on right now: the first item in progress.
    public var current: String? {
        items.first { $0.status == .inProgress }.map { $0.activeTitle ?? $0.title }
    }
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

public enum TaskProgress {
    /// The list a tool call writes, or nil when the call isn't a to-do update.
    public static func parse(tool: String, input: JSONValue) -> TaskList? {
        let entries: [JSONValue]
        let titleKey: String
        switch ToolAliases.claudeName(tool) {
        case "TodoWrite":
            guard let todos = input["todos"]?.array else { return nil }
            (entries, titleKey) = (todos, "content")
        case "update_plan":
            guard let plan = input["plan"]?.array else { return nil }
            (entries, titleKey) = (plan, "step")
        default:
            return nil
        }
        let items = entries.compactMap { e -> TaskList.Item? in
            guard let title = e[titleKey]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let active = e["activeForm"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            return TaskList.Item(title: title, status: status(e["status"]?.string), activeTitle: active)
        }
        return TaskList(items: items)
    }

    private static func status(_ raw: String?) -> TaskList.Item.Status {
        switch raw?.lowercased() {
        case "completed", "complete", "done": .completed
        case "in_progress", "inprogress", "in-progress", "active": .inProgress
        default: .pending
        }
    }
}
