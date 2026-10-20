import Foundation
import NotchCore
import NotchShared

/// Plan limits + local token history. Codex limits and all token counts come from local logs;
/// Claude limits are opt-in and use the Claude Code sign-in already stored on this Mac.
@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var history = TokenHistory()
    @Published private(set) var codexLimits: RateLimits?
    @Published private(set) var claudeLimits: RateLimits?
    @Published private(set) var claudeError: String?
    @Published private(set) var isScanning = false

    private let index = IndexActor()
    private var timers: [Timer] = []

    var limits: [RateLimits] { [claudeLimits, codexLimits].compactMap { $0 } }

    func start() {
        refreshLocal()
        refreshClaudeIfEnabled()
        timers = [
            Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
                Task { @MainActor [weak self] in self?.refreshLocal() }
            },
            Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
                Task { @MainActor [weak self] in self?.refreshClaudeIfEnabled() }
            },
        ]
    }

    func loadPreview(history: TokenHistory, claude: RateLimits?, codex: RateLimits?) {
        self.history = history
        claudeLimits = claude
        codexLimits = codex
    }

    /// Codex rewrites limits on every turn; take fresher values from a live session's transcript.
    func update(codex limits: RateLimits) {
        if limits.fetchedAt > (codexLimits?.fetchedAt ?? .distantPast) { codexLimits = limits }
    }

    func refreshLocal() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await index.refresh()
            history = result.history
            if let l = result.codexLimits { update(codex: l) }
            isScanning = false
        }
    }

    func refreshClaudeIfEnabled() {
        guard Prefs.bool(PrefKey.claudeUsageEnabled) else {
            claudeLimits = nil
            claudeError = nil
            return
        }
        Task {
            do {
                claudeLimits = try await Self.fetchClaudeLimits()
                claudeError = nil
            } catch {
                claudeError = error.localizedDescription
            }
        }
    }

    enum ClaudeUsageError: LocalizedError {
        case notSignedIn, expired, http(Int), unexpected
        var errorDescription: String? {
            switch self {
            case .notSignedIn: "No Claude Code sign-in found. Run `claude` and log in."
            case .expired: "Claude sign-in expired. Run `claude` once to refresh it."
            case .http(let code): "Anthropic returned HTTP \(code)."
            case .unexpected: "Unrecognized usage response."
            }
        }
    }

    private static func fetchClaudeLimits() async throws -> RateLimits {
        guard let creds = await Task.detached(operation: readClaudeCredentials).value else { throw ClaudeUsageError.notSignedIn }
        if let exp = creds.expiresAt, exp < Date() { throw ClaudeUsageError.expired }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw code == 401 ? ClaudeUsageError.expired : ClaudeUsageError.http(code) }
        guard let limits = RateLimits.claude(try JSONValue.decode(data)) else { throw ClaudeUsageError.unexpected }
        return limits
    }

    /// Claude Code stores its OAuth token in the login keychain (or ~/.claude/.credentials.json on some setups).
    nonisolated private static func readClaudeCredentials() -> (token: String, expiresAt: Date?)? {
        func parse(_ data: Data) -> (String, Date?)? {
            guard let v = try? JSONValue.decode(data), let oauth = v["claudeAiOauth"],
                let token = oauth["accessToken"]?.string
            else { return nil }
            return (token, oauth["expiresAt"]?.double.map { Date(timeIntervalSince1970: $0 / 1000) })
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus == 0, let c = parse(data) { return c }
        }
        let file = NotchPaths.homeDirectory.appendingPathComponent(".claude/.credentials.json")
        return (try? Data(contentsOf: file)).flatMap(parse)
    }
}

private actor IndexActor {
    private let index = UsageIndex()

    func refresh() -> UsageScanner.Result {
        index.refresh(home: NotchPaths.homeDirectory)
    }
}
