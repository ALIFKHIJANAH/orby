import Foundation
import NotchShared

/// Turns a tool call into a one-line, human summary for the notch.
public enum ToolDescriber {
    public static func describe(tool: String, input: JSONValue) -> String {
        activity(tool: tool, input: input).progressive
    }

    public static func activity(tool: String, input: JSONValue) -> Activity {
        func path(_ key: String) -> String? { input[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        func file(_ key: String = "file_path") -> String { path(key).map { ($0 as NSString).lastPathComponent } ?? "a file" }
        func quoted(_ key: String, max: Int = 50) -> String { "“\(PlainText.truncate(input[key]?.string ?? "", max: max))”" }
        func shell(_ command: String) -> Activity {
            // Claude's Bash tool carries a description written for people; prefer it.
            if let d = input["description"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                return Activity(PlainText.truncate(d, max: 90), detail: command)
            }
            return Activity(CommandHumanizer.describe(command), detail: command)
        }
        func fetch(_ key: String) -> Activity {
            let url = input[key]?.string ?? ""
            return Activity("Reading \(URL(string: url)?.host ?? "a web page")", detail: url)
        }

        switch tool {
        case "Bash", "shell", "exec_command", "local_shell", "container.exec":
            return shell(command(from: input))
        case "Read": return Activity("Reading \(file())", detail: path("file_path").map(abbreviate))
        case "Edit", "MultiEdit": return Activity("Editing \(file())", detail: path("file_path").map(abbreviate))
        case "Write": return Activity("Writing \(file())", detail: path("file_path").map(abbreviate))
        case "NotebookEdit": return Activity("Editing \(file("notebook_path"))", detail: path("notebook_path").map(abbreviate))
        case "Grep": return Activity("Searching for \(quoted("pattern"))", detail: path("path").map(abbreviate))
        case "Glob": return Activity(findPhrase(input["pattern"]?.string ?? ""), detail: input["pattern"]?.string)
        case "WebFetch": return fetch("url")
        case "WebSearch": return Activity("Searching the web for \(quoted("query"))")
        case "Task", "Agent":
            let what = input["description"]?.string ?? input["subagent_type"]?.string ?? "a subtask"
            return Activity("Delegating: \(PlainText.truncate(what, max: 70))")
        case "TodoWrite", "update_plan": return Activity("Updating the to-do list")
        case "AskUserQuestion":
            let q = QuestionParser.parse(input).first?.question
            return Activity(q.map { "Asking: \(PlainText.truncate($0, max: 100))" } ?? "Asking a question")
        case "ExitPlanMode":
            let title = PlainText.title(input["plan"]?.string ?? "", max: 80)
            return Activity(title.isEmpty ? "Plan ready for review" : "Plan ready: \(title)")
        case "apply_patch": return patchActivity(input)
        // Antigravity
        case "run_command": return shell(input["CommandLine"]?.string ?? "")
        case "view_file", "view_file_outline": return Activity("Reading \(file("AbsolutePath"))", detail: path("AbsolutePath").map(abbreviate))
        case "write_to_file": return Activity("Writing \(file("TargetFile"))", detail: path("TargetFile").map(abbreviate))
        case "replace_file_content", "multi_replace_file_content":
            return Activity("Editing \(file("TargetFile"))", detail: path("TargetFile").map(abbreviate))
        case "grep_search": return Activity("Searching for \(quoted("Query"))")
        case "find_by_name": return Activity(findPhrase(input["Pattern"]?.string ?? ""))
        case "list_dir": return Activity("Listing \(file("DirectoryPath"))", detail: path("DirectoryPath").map(abbreviate))
        case "read_url_content": return fetch("Url")
        case "search_web": return Activity("Searching the web for \(quoted("query"))")
        default:
            if tool.hasPrefix("mcp__") { return mcpActivity(tool) }
            return Activity("Using \(words(tool))")
        }
    }

    /// `mcp__github__create_pull_request` → "Using GitHub: create pull request".
    static func mcpActivity(_ tool: String) -> Activity {
        let parts = tool.dropFirst(5).components(separatedBy: "__")
        let server = serverName(parts.first ?? "tool")
        guard parts.count >= 2 else { return Activity("Using \(server)") }
        return Activity("Using \(server): \(words(parts[1...].joined(separator: " ")))")
    }

    private static let knownServers: [String: String] = [
        "github": "GitHub", "gitlab": "GitLab", "slack": "Slack", "linear": "Linear", "notion": "Notion",
        "figma": "Figma", "jira": "Jira", "sentry": "Sentry", "playwright": "Playwright", "puppeteer": "Puppeteer",
        "postgres": "Postgres", "supabase": "Supabase", "stripe": "Stripe", "vercel": "Vercel", "filesystem": "Files",
        "context7": "Context7", "chrome-devtools": "Chrome DevTools", "pencil": "Pencil", "rea": "REA",
    ]

    private static func serverName(_ raw: String) -> String {
        // "claude_ai_Notion" / "plugin_x_github" → last meaningful part.
        let base = raw.components(separatedBy: "_").last { !$0.isEmpty } ?? raw
        if let known = knownServers[base.lowercased()] ?? knownServers[raw.lowercased()] { return known }
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    /// snake_case / kebab-case / camelCase → lowercase words.
    public static func words(_ s: String) -> String {
        var out = ""
        for c in s {
            if c == "_" || c == "-" { out.append(" ") }
            else if c.isUppercase, let last = out.last, last.isLowercase { out.append(" "); out.append(Character(c.lowercased())) }
            else { out.append(c) }
        }
        let acronyms: Set<String> = ["pr", "prs", "url", "api", "id", "ci", "pdf", "ui", "sql", "json", "csv", "html", "db", "ssh"]
        return out.split(separator: " ").map { w in
            let lower = w.lowercased()
            return acronyms.contains(lower) ? lower.uppercased() : lower
        }.joined(separator: " ")
    }

    private static let languages: [String: String] = [
        "swift": "Swift", "ts": "TypeScript", "tsx": "TypeScript", "js": "JavaScript", "jsx": "JavaScript",
        "py": "Python", "go": "Go", "rs": "Rust", "rb": "Ruby", "java": "Java", "kt": "Kotlin", "md": "Markdown",
        "json": "JSON", "yml": "YAML", "yaml": "YAML", "css": "CSS", "scss": "SCSS", "html": "HTML", "sql": "SQL",
        "sh": "shell", "php": "PHP", "c": "C", "cpp": "C++", "h": "header", "vue": "Vue", "svelte": "Svelte",
    ]

    /// `**/*.swift` → "Finding Swift files"; anything else → "Finding “pattern”".
    static func findPhrase(_ pattern: String) -> String {
        if let dot = pattern.lastIndex(of: "."), !pattern[pattern.index(after: dot)...].contains("/") {
            let ext = pattern[pattern.index(after: dot)...].trimmingCharacters(in: CharacterSet(charactersIn: "}{*"))
            if let lang = languages[ext.lowercased()] { return "Finding \(lang) files" }
        }
        return pattern.isEmpty ? "Finding files" : "Finding “\(PlainText.truncate(pattern, max: 40))”"
    }

    /// Codex patches list their files as "*** Update File: path" lines.
    static func patchActivity(_ input: JSONValue) -> Activity {
        var texts: [String] = []
        func collect(_ v: JSONValue) {
            switch v {
            case .string(let s): texts.append(s)
            case .array(let a): a.forEach(collect)
            case .object(let o): o.values.forEach(collect)
            default: break
            }
        }
        collect(input)
        var files: [(verb: String, path: String)] = []
        for line in texts.joined(separator: "\n").split(whereSeparator: \.isNewline) {
            for (prefix, verb) in [("*** Update File: ", "Editing"), ("*** Add File: ", "Creating"), ("*** Delete File: ", "Deleting")]
            where line.hasPrefix(prefix) {
                files.append((verb, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)))
            }
        }
        guard let first = files.first else { return Activity("Editing files") }
        let verb = files.allSatisfy { $0.verb == first.verb } ? first.verb : "Editing"
        let name = (first.path as NSString).lastPathComponent
        let more = files.count - 1
        let phrase = more == 0 ? "\(verb) \(name)" : "\(verb) \(name) and \(more) more file\(more == 1 ? "" : "s")"
        // Names only: the full paths of every patched file are too long for one line.
        return Activity(phrase, detail: files.map { ($0.path as NSString).lastPathComponent }.joined(separator: ", "))
    }

    public static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Codex sends commands as an argv array; Claude sends a string.
    public static func command(from input: JSONValue) -> String {
        if let s = input["command"]?.string { return s }
        if let argv = input["command"]?.array?.compactMap(\.string), !argv.isEmpty {
            // ["bash", "-lc", "real command"] → show the real command.
            if argv.count >= 3, ["-lc", "-c"].contains(argv[argv.count - 2]) { return argv.last! }
            return argv.joined(separator: " ")
        }
        if let s = input["cmd"]?.string { return s }
        return ""
    }

    /// Last non-empty line: the most recent part of a streaming thought.
    public static func lastLine(_ s: String, max: Int) -> String {
        let line = s.split(whereSeparator: \.isNewline).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return firstLine(line.map(String.init) ?? s, max: max)
    }

    public static func firstLine(_ s: String, max: Int) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return PlainText.truncate(line, max: max)
    }
}

public enum QuestionParser {
    public static func parse(_ input: JSONValue) -> [Question] {
        (input["questions"]?.array ?? []).compactMap { q in
            guard let text = q["question"]?.string else { return nil }
            let options = (q["options"]?.array ?? []).compactMap { o -> QuestionOption? in
                if let label = o.string { return QuestionOption(label: label, detail: nil) }
                guard let label = o["label"]?.string else { return nil }
                return QuestionOption(label: label, detail: o["description"]?.string)
            }
            return Question(
                question: text, header: q["header"]?.string, options: options,
                multiSelect: q["multiSelect"]?.bool ?? false)
        }
    }
}
