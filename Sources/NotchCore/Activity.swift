import Foundation

/// What an agent is doing, phrased for people.
public struct Activity: Hashable, Sendable {
    /// Status form: "Running the auth tests".
    public var progressive: String
    /// Follows "wants to": "run the auth tests".
    public var intent: String
    /// The exact command, path or URL behind the phrase.
    public var detail: String?

    public init(_ progressive: String, detail: String? = nil) {
        self.progressive = progressive
        self.intent = Self.baseForm(of: progressive)
        self.detail = detail.flatMap { $0.isEmpty || $0 == progressive ? nil : $0 }
    }

    private static let verbs: [String: String] = [
        "Adding": "add", "Asking": "ask", "Building": "build", "Calling": "call", "Changing": "change",
        "Checking": "check", "Cleaning": "clean", "Cloning": "clone", "Committing": "commit", "Connecting": "connect", "Copying": "copy",
        "Counting": "count", "Creating": "create", "Delegating": "delegate", "Deleting": "delete", "Deploying": "deploy",
        "Editing": "edit", "Fetching": "fetch", "Finding": "find", "Formatting": "format", "Installing": "install",
        "Linking": "link", "Linting": "lint", "Listing": "list", "Merging": "merge", "Moving": "move",
        "Opening": "open", "Printing": "print", "Pulling": "pull", "Pushing": "push", "Reading": "read",
        "Rebasing": "rebase", "Removing": "remove", "Resolving": "resolve", "Restoring": "restore",
        "Reviewing": "review", "Running": "run", "Searching": "search", "Staging": "stage", "Starting": "start",
        "Stashing": "stash", "Stopping": "stop", "Switching": "switch", "Syncing": "sync", "Tidying": "tidy",
        "Type-checking": "type-check", "Updating": "update", "Using": "use", "Waiting": "wait", "Writing": "write",
    ]

    /// "Editing App.swift" → "edit App.swift"; an imperative like "Run tests" → "run tests".
    static func baseForm(of phrase: String) -> String {
        let parts = phrase.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return phrase }
        let rest = parts.count > 1 ? " " + parts[1] : ""
        let word = String(first).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        if let base = verbs[word] { return base + rest }
        // Keep proper nouns and acronyms ("GitHub", "CI", "iOS") as written.
        if first.dropFirst().contains(where: \.isUppercase) { return phrase }
        return first.prefix(1).lowercased() + first.dropFirst() + rest
    }
}

/// The kind of work behind an activity, so the orb can act it out.
public enum ActivityKind: String, CaseIterable, Sendable {
    case read, edit, search, web, run, test, build, git, delete, delegate, plan

    private static let verbs: [String: ActivityKind] = [
        "Reading": .read, "Listing": .read, "Opening": .read, "Printing": .read, "Reviewing": .read, "Comparing": .read,
        "Querying": .read,
        "Editing": .edit, "Writing": .edit, "Changing": .edit, "Updating": .edit, "Creating": .edit, "Adding": .edit,
        "Formatting": .edit, "Moving": .edit, "Copying": .edit, "Processing": .edit,
        "Searching": .search, "Finding": .search, "Counting": .search, "Resolving": .search,
        "Committing": .git, "Pushing": .git, "Pulling": .git, "Merging": .git, "Rebasing": .git, "Stashing": .git,
        "Cloning": .git, "Staging": .git, "Switching": .git, "Restoring": .git, "Syncing": .git, "Tagging": .git,
        "Cherry-picking": .git, "Fetching": .git,
        "Deleting": .delete, "Removing": .delete, "Cleaning": .delete, "Tidying": .delete,
        "Building": .build, "Installing": .build, "Deploying": .build, "Publishing": .build, "Packing": .build, "Linking": .build,
        "Checking": .test, "Linting": .test, "Type-checking": .test,
        "Delegating": .delegate,
        "Asking": .plan, "Plan": .plan,
    ]

    public init(_ activity: Activity) {
        let phrase = activity.progressive
        let verb = phrase.split(separator: " ", maxSplits: 1).first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":")) } ?? ""
        let lower = phrase.lowercased()
        if activity.detail?.hasPrefix("http") == true || lower.hasPrefix("searching the web") {
            self = .web
        } else if lower.hasPrefix("updating the to-do") {
            self = .plan
        } else if lower.split(separator: " ").contains(where: { $0 == "git" || $0 == "branch" }) {
            self = .git
        } else if let kind = Self.verbs[verb] {
            self = kind
        } else if lower.contains("test") || lower.contains("lint") {
            self = .test
        } else if lower.contains("build") || lower.contains("compil") {
            self = .build
        } else {
            self = .run
        }
    }
}

extension Activity {
    public var kind: ActivityKind { ActivityKind(self) }
}
