import Foundation

/// Shell command → plain English: `cd app && pnpm test auth` → "Running tests".
public enum CommandHumanizer {
    public static func describe(_ command: String) -> String {
        let segment = mainSegment(of: command)
        var words = tokenize(segment)
        stripPrefixes(&words)
        guard let program = words.first.map(basename) else { return "Running a command" }
        let args = Array(words.dropFirst())

        if ["bash", "sh", "zsh"].contains(program), let i = args.firstIndex(where: { $0 == "-c" || $0 == "-lc" }),
            i + 1 < args.count
        {
            return describe(args[i + 1])
        }
        return phrase(program: program, args: args)
    }

    // MARK: Normalization

    /// The command that matters in `a && b; c | d`: the last segment that isn't setup
    /// (cd/export/source), then the first stage of its pipeline.
    static func mainSegment(of command: String) -> String {
        let firstLine = command.split(whereSeparator: \.isNewline).first.map(String.init) ?? command
        let segments = splitOutsideQuotes(firstLine, separators: ["&&", "||", ";"])
        let setup: Set<String> = ["cd", "export", "source", ".", "set", "unset", "pushd", "popd"]
        let main = segments.last { seg in
            let first = tokenize(seg).first.map(basename) ?? ""
            return !first.isEmpty && !setup.contains(first)
        } ?? segments.last ?? firstLine
        return splitOutsideQuotes(main, separators: ["|"]).first ?? main
    }

    private static func stripPrefixes(_ words: inout [String]) {
        let wrappers: Set<String> = ["sudo", "time", "nohup", "command", "exec", "env", "caffeinate", "nice"]
        while let w = words.first {
            if wrappers.contains(basename(w)) || isAssignment(w) || (words.count > 1 && w.hasPrefix("-") && w.count <= 3) {
                words.removeFirst()
            } else {
                break
            }
        }
    }

    private static func isAssignment(_ w: String) -> Bool {
        guard let eq = w.firstIndex(of: "="), eq != w.startIndex else { return false }
        return w[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func tokenize(_ s: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        for c in s {
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == " " || c == "\t" {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func splitOutsideQuotes(_ s: String, separators: [String]) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var i = s.startIndex
        outer: while i < s.endIndex {
            let c = s[i]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else {
                for sep in separators where s[i...].hasPrefix(sep) {
                    parts.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    i = s.index(i, offsetBy: sep.count)
                    continue outer
                }
            }
            current.append(c)
            i = s.index(after: i)
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts.filter { !$0.isEmpty }
    }

    private static func basename(_ s: String) -> String { (s as NSString).lastPathComponent }

    /// First argument that isn't a flag.
    private static func operand(_ args: [String], after index: Int = 0) -> String? {
        args.dropFirst(index).first { !$0.hasPrefix("-") }
    }

    private static func fileName(_ args: [String], after index: Int = 0) -> String? {
        operand(args, after: index).map(basename)
    }

    // MARK: Phrases

    private static func phrase(program: String, args: [String]) -> String {
        let sub = args.first { !$0.hasPrefix("-") } ?? ""
        switch program {
        case "npm", "pnpm", "yarn", "bun":
            return packageManager(program, args)
        case "npx", "bunx", "pnpx":
            guard let tool = operand(args) else { return "Running a package" }
            return phrase(program: tool, args: Array(args.drop { $0 != tool }.dropFirst()))
        case "node", "deno", "ts-node", "tsx":
            return fileName(args).map { "Running \($0)" } ?? "Running Node"
        case "python", "python3":
            if let m = args.firstIndex(of: "-m"), m + 1 < args.count {
                return phrase(program: args[m + 1], args: Array(args[(m + 2)...]))
            }
            return fileName(args).map { "Running \($0)" } ?? "Running Python"
        case "pytest", "jest", "vitest", "mocha", "rspec", "phpunit", "ava", "playwright":
            return sub == "install" ? "Installing browsers" : "Running tests"
        case "go":
            return ["test": "Running tests", "build": "Building", "run": "Running the Go program", "vet": "Checking the code",
                "get": "Installing dependencies", "mod": "Tidying Go modules", "fmt": "Formatting"][sub] ?? "Running go \(sub)"
        case "cargo":
            return ["test": "Running tests", "build": "Building", "run": "Running the program", "check": "Checking the build",
                "clippy": "Linting", "fmt": "Formatting", "add": "Adding \(operand(args, after: 1) ?? "a crate")",
                "install": "Installing \(operand(args, after: 1) ?? "a crate")"][sub] ?? "Running cargo \(sub)"
        case "swift":
            if sub == "package" { return "Resolving Swift packages" }
            return ["test": "Running tests", "build": "Building", "run": "Running the program"][sub] ?? "Running Swift"
        case "flutter", "dart":
            return ["build": "Building", "test": "Running tests", "pub": "Installing dependencies", "run": "Running the app",
                "analyze": "Linting", "format": "Formatting", "clean": "Cleaning the build"][sub] ?? "Running \(program) \(sub)"
        case "xcodebuild":
            return args.contains("test") ? "Running tests" : "Building"
        case "make", "just", "rake", "gradle", "./gradlew", "gradlew", "mvn":
            if args.contains(where: { $0.contains("test") }) { return "Running tests" }
            if sub.isEmpty || sub == "build" || sub == "all" || sub == "assemble" { return "Building" }
            return "Running \(program) \(sub)"
        case "pip", "pip3", "uv", "poetry", "pipx":
            if sub == "install" || sub == "add" || sub == "sync" { return "Installing dependencies" }
            if sub == "run", let tool = operand(args, after: 1) { return phrase(program: tool, args: Array(args.drop { $0 != tool }.dropFirst())) }
            return "Running \(program) \(sub)"
        case "brew":
            return sub == "install" ? "Installing \(operand(args, after: 1) ?? "a package")" : "Running brew \(sub)"
        case "pod", "bundle", "composer":
            return sub == "install" || sub == "update" ? "Installing dependencies" : "Running \(program) \(sub)"
        case "tsc": return "Type-checking"
        case "eslint", "biome", "swiftlint", "flake8", "pylint", "rubocop", "golangci-lint", "stylelint":
            return args.contains("--fix") || sub == "format" ? "Formatting" : "Linting"
        case "prettier", "black", "swiftformat", "gofmt", "rustfmt", "isort":
            return "Formatting"
        case "ruff":
            return sub == "format" ? "Formatting" : "Linting"
        case "git":
            return git(args)
        case "gh":
            return gh(args)
        case "cat", "head", "tail", "less", "more", "bat", "nl":
            return fileName(args).map { "Reading \($0)" } ?? "Reading a file"
        case "sed", "awk":
            if args.contains("-i") || args.contains(where: { $0.hasPrefix("-i") }) {
                return args.last.map { "Editing \(basename($0))" } ?? "Editing a file"
            }
            return args.last.map { "Reading \(basename($0))" } ?? "Processing text"
        case "ls", "tree", "exa", "eza":
            return "Listing files"
        case "find", "fd":
            return "Finding files"
        case "grep", "rg", "ag", "ack", "egrep":
            return operand(args).map { "Searching for “\(PlainText.truncate($0, max: 40))”" } ?? "Searching code"
        case "wc": return "Counting lines"
        case "diff": return "Comparing files"
        case "mkdir": return fileName(args).map { "Creating \($0)" } ?? "Creating a folder"
        case "touch": return fileName(args).map { "Creating \($0)" } ?? "Creating a file"
        case "rm", "rmdir", "trash": return fileName(args).map { "Deleting \($0)" } ?? "Deleting files"
        case "mv": return fileName(args).map { "Moving \($0)" } ?? "Moving files"
        case "cp": return fileName(args).map { "Copying \($0)" } ?? "Copying files"
        case "chmod", "chown": return "Changing permissions"
        case "ln": return "Linking files"
        case "tar", "zip", "unzip", "gzip", "gunzip": return "Packing files"
        case "curl", "wget", "http", "xh":
            let url = args.first { $0.hasPrefix("http") } ?? operand(args)
            return url.flatMap { URL(string: $0)?.host }.map { "Fetching \($0)" } ?? "Fetching a URL"
        case "docker", "podman":
            return docker(args)
        case "kubectl", "helm":
            return ["get": "Checking the cluster", "describe": "Checking the cluster", "apply": "Deploying",
                "install": "Deploying", "upgrade": "Deploying", "logs": "Reading logs"][sub] ?? "Running \(program) \(sub)"
        case "ssh": return operand(args).map { "Connecting to \($0)" } ?? "Connecting to a server"
        case "scp", "rsync": return "Syncing files"
        case "echo", "printf": return "Printing output"
        case "pwd", "which", "whoami", "printenv", "uname", "type": return "Checking the environment"
        case "ps", "lsof", "top": return "Checking processes"
        case "kill", "pkill", "killall": return "Stopping a process"
        case "sleep": return "Waiting"
        case "open": return fileName(args).map { "Opening \($0)" } ?? "Opening an app"
        case "osascript": return "Running AppleScript"
        case "jq": return "Reading JSON"
        case "sqlite3", "psql", "mysql": return "Querying the database"
        default:
            return "Running \(program)"
        }
    }

    private static func packageManager(_ pm: String, _ args: [String]) -> String {
        let sub = args.first { !$0.hasPrefix("-") } ?? ""
        let installs: Set<String> = ["install", "i", "ci", "add"]
        if sub.isEmpty || installs.contains(sub) {
            if sub == "add", let pkg = operand(args, after: 1) { return "Adding \(pkg)" }
            return "Installing dependencies"
        }
        if ["remove", "uninstall", "rm"].contains(sub) { return "Removing \(operand(args, after: 1) ?? "a package")" }
        if ["exec", "dlx", "x"].contains(sub), let tool = operand(args, after: 1) {
            return phrase(program: tool, args: Array(args.drop { $0 != tool }.dropFirst()))
        }
        // `npm run build`, `pnpm build`, `yarn test`
        let script = ["run", "run-script"].contains(sub) ? (operand(args, after: 1) ?? "") : sub
        return scriptPhrase(script)
    }

    private static func scriptPhrase(_ script: String) -> String {
        let s = script.lowercased()
        if s == "t" || s.contains("test") || s.contains("spec") || s == "e2e" { return "Running tests" }
        if s.contains("build") || s == "compile" { return "Building" }
        if ["dev", "start", "serve", "preview", "watch"].contains(s) { return "Starting the dev server" }
        if s.contains("lint") { return "Linting" }
        if s.contains("format") || s == "fmt" || s.contains("prettier") { return "Formatting" }
        if s.contains("typecheck") || s.contains("type-check") || s == "tsc" || s == "check" { return "Type-checking" }
        if s.contains("deploy") || s.contains("release") { return "Deploying" }
        return "Running the \(script) script"
    }

    private static func git(_ args: [String]) -> String {
        let sub = args.first { !$0.hasPrefix("-") } ?? ""
        let rest = Array(args.drop { $0 != sub }.dropFirst())
        switch sub {
        case "status": return "Checking git status"
        case "diff": return "Reviewing changes"
        case "log", "show", "blame", "reflog", "shortlog": return "Reading git history"
        case "add": return "Staging changes"
        case "commit":
            if let m = rest.firstIndex(where: { $0 == "-m" || $0 == "--message" }), m + 1 < rest.count {
                return "Committing “\(PlainText.truncate(rest[m + 1], max: 60))”"
            }
            return "Committing changes"
        case "push": return "Pushing to \(operand(rest) ?? "the remote")"
        case "pull", "fetch": return "Pulling latest changes"
        case "checkout", "switch":
            if let b = rest.firstIndex(where: { $0 == "-b" || $0 == "-c" || $0 == "-B" }), b + 1 < rest.count {
                return "Creating branch \(rest[b + 1])"
            }
            return operand(rest).map { $0 == "--" ? "Restoring files" : "Switching to \($0)" } ?? "Switching branch"
        case "branch": return "Listing branches"
        case "merge": return operand(rest).map { "Merging \($0)" } ?? "Merging"
        case "rebase": return "Rebasing"
        case "stash": return "Stashing changes"
        case "clone":
            let repo = operand(rest).map { basename($0).replacingOccurrences(of: ".git", with: "") }
            return repo.map { "Cloning \($0)" } ?? "Cloning a repository"
        case "reset", "restore", "revert": return "Restoring files"
        case "worktree": return "Managing worktrees"
        case "tag": return "Tagging a release"
        case "cherry-pick": return "Cherry-picking a commit"
        default: return sub.isEmpty ? "Running git" : "Running git \(sub)"
        }
    }

    private static func gh(_ args: [String]) -> String {
        let words = args.filter { !$0.hasPrefix("-") }
        let sub = words.first ?? "", action = words.dropFirst().first ?? ""
        switch (sub, action) {
        case ("pr", "create"): return "Opening a pull request"
        case ("pr", "merge"): return "Merging the pull request"
        case ("pr", "checkout"): return "Checking out a pull request"
        case ("pr", _): return "Checking pull requests"
        case ("issue", "create"): return "Opening an issue"
        case ("issue", _): return "Checking issues"
        case ("run", _), ("workflow", _): return "Checking CI runs"
        case ("release", _): return "Publishing a release"
        case ("api", _): return "Calling the GitHub API"
        default: return "Using GitHub"
        }
    }

    private static func docker(_ args: [String]) -> String {
        let words = args.filter { !$0.hasPrefix("-") }
        let sub = words.first ?? ""
        if sub == "compose" || sub == "docker-compose" {
            let action = words.dropFirst().first ?? ""
            return ["up": "Starting containers", "down": "Stopping containers", "build": "Building containers",
                "logs": "Reading container logs", "ps": "Checking containers"][action] ?? "Running Docker Compose"
        }
        return ["build": "Building the Docker image", "run": "Running a container", "exec": "Running in a container",
            "ps": "Checking containers", "logs": "Reading container logs", "pull": "Pulling an image",
            "push": "Pushing an image", "stop": "Stopping a container"][sub] ?? "Running Docker"
    }
}
