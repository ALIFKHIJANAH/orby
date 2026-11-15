import Foundation
import NotchCore
import NotchShared

/// Asks GitHub once a day whether a newer Orby is out. Nothing is installed: the app isn't
/// notarized, so the user downloads the new DMG from the release page.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var checking = false
    @Published private(set) var status: String?
    private var timer: Timer?

    static let latestURL = URL(string: "https://api.github.com/repos/ALIFKHIJANAH/orby/releases/latest")!
    static let interval: TimeInterval = 86_400

    /// nil in a `swift run` build, which has no version to compare.
    var currentVersion: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    func start() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in UpdateService.shared.checkIfDue() }
        }
        timer?.tolerance = 300
    }

    private func checkIfDue() {
        guard Prefs.bool(PrefKey.checkForUpdates), currentVersion != nil, !PreviewRenderer.active else { return }
        let last = Prefs.defaults.object(forKey: PrefKey.lastUpdateCheck) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.interval { check() }
    }

    func check() {
        guard !checking, let current = currentVersion else {
            if currentVersion == nil { status = "Development build: nothing to compare." }
            return
        }
        checking = true
        Task {
            defer { checking = false }
            var req = URLRequest(url: Self.latestURL)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("Orby", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let release = ReleaseInfo.parse(try JSONValue.decode(data)) else {
                    status = "GitHub returned HTTP \(code)."
                    return
                }
                Prefs.defaults.set(Date(), forKey: PrefKey.lastUpdateCheck)
                available = release.isNewer(than: current) ? release : nil
                status = available == nil ? "Orby \(current) is the latest version." : nil
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
