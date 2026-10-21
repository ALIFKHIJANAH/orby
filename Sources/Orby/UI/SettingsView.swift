import AppKit
import NotchCore
import NotchShared
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, integrations, sounds, usage, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .integrations: "puzzlepiece.extension"
        case .sounds: "speaker.wave.2"
        case .usage: "chart.bar"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let selection = SettingsSelection()
    var sound: SoundPlayer?
    var usage: UsageService?

    func show(tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(selection: selection, sound: sound, usage: usage))
            let w = NSWindow(contentViewController: host)
            w.title = "Orby Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 640, height: 500))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection
    let sound: SoundPlayer?
    let usage: UsageService?

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { selection.tab }, set: { if let t = $0 { selection.tab = t } })) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            Form {
                switch selection.tab {
                case .general: GeneralSettings()
                case .integrations: IntegrationSettings()
                case .sounds: SoundSettings(sound: sound)
                case .usage: UsageSettings(usage: usage)
                case .about: AboutSettings()
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 640, minHeight: 500)
    }
}

private struct GeneralSettings: View {
    @AppStorage(PrefKey.expandOnHover) private var expandOnHover = true
    @AppStorage(PrefKey.hoverDelay) private var hoverDelay = 0.15
    @AppStorage(PrefKey.autoExpandAttention) private var autoExpandAttention = true
    @AppStorage(PrefKey.autoExpandCompletion) private var autoExpandCompletion = true
    @AppStorage(PrefKey.completionRevealSeconds) private var revealSeconds = 4.0
    @AppStorage(PrefKey.quietWhenTerminalFocused) private var quietWhenFocused = true
    @AppStorage(PrefKey.clickToJump) private var clickToJump = true
    @AppStorage(PrefKey.hideWhenIdle) private var hideWhenIdle = true
    @AppStorage(PrefKey.idleHideSeconds) private var idleHideSeconds = 10.0
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(PrefKey.finishedSessionTTLMinutes) private var ttl = 60.0
    @AppStorage(PrefKey.display) private var display = DisplayChoice.auto.rawValue
    @AppStorage(PrefKey.notchWidthOverride) private var notchWidth = 0.0
    @AppStorage(PrefKey.notchHeightOverride) private var notchHeight = 0.0
    @AppStorage(PrefKey.panelWidth) private var panelWidth = 560.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Section("Startup") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
        }
        Section("Behaviour") {
            Toggle("Expand when hovering the notch", isOn: $expandOnHover)
            if expandOnHover {
                Slider(value: $hoverDelay, in: 0...1, step: 0.05) { Text("Hover delay \(hoverDelay, specifier: "%.2f")s") }
            }
            Toggle("Expand for approvals, questions and plans", isOn: $autoExpandAttention)
            Toggle("Expand briefly when a task completes", isOn: $autoExpandCompletion)
            if autoExpandCompletion {
                Slider(value: $revealSeconds, in: 1...15, step: 1) { Text("Stay open \(Int(revealSeconds))s") }
            }
            Toggle("Don't pop up finished tasks when the agent's terminal is in front", isOn: $quietWhenFocused)
                .help("Approvals and questions always open the notch.")
            Toggle("Click a session to jump to its terminal", isOn: $clickToJump)
            Toggle("Hide the notch tab when agents are done or idle", isOn: $hideWhenIdle)
            if hideWhenIdle {
                Picker("Hide after", selection: $idleHideSeconds) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }
            }
            Picker("Clear finished sessions after", selection: $ttl) {
                Text("10 minutes").tag(10.0)
                Text("30 minutes").tag(30.0)
                Text("1 hour").tag(60.0)
                Text("4 hours").tag(240.0)
                Text("24 hours").tag(1440.0)
            }
        }
        Section("Display") {
            Picker("Show on", selection: $display) {
                ForEach(DisplayChoice.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Slider(value: $panelWidth, in: 440...720, step: 10) { Text("Panel width \(Int(panelWidth))") }
            Stepper("Notch width: \(notchWidth == 0 ? "auto" : "\(Int(notchWidth))")", value: $notchWidth, in: 0...400, step: 2)
            Stepper("Notch height: \(notchHeight == 0 ? "auto" : "\(Int(notchHeight))")", value: $notchHeight, in: 0...60, step: 1)
            Text("Fine-tune if the island doesn't line up with your notch. 0 uses the value macOS reports.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Shortcuts") {
            LabeledContent("Allow request", value: "⌘Y")
            LabeledContent("Deny request", value: "⌘N")
            Text("Active only while a permission request is open in the notch.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct IntegrationSettings: View {
    @State private var status = IntegrationStatus.current()
    @State private var message: String?
    @State private var bridgeInstalled = BridgeSetup.isInstalled
    @AppStorage(PrefKey.autoConfigureAgents) private var autoConfigure = false
    @AppStorage(PrefKey.antigravityAnswerFromNotch) private var answerAntigravity = true
    @AppStorage(PrefKey.antigravityStatusLine) private var statusLineWanted = false
    @State private var statusLine = StatusLineInstaller.status()

    var body: some View {
        Section {
            ForEach(HookTarget.allCases, id: \.self) { target in
                row(target)
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("Orby adds a small hook or plugin to each agent's own config. Other tools' hooks and plugins are left alone, and a backup is saved to ~/.orby/backups before every change. Restart running sessions afterwards.")
        }
        ForEach([HookTarget.claude, .codex, .qwen], id: \.self) { target in
            let others = HookInstaller.foreignBlockingHooks(target)
            if status.statuses[target] == .installed, !others.isEmpty {
                Section("Other apps answering \(target.agent.displayName) prompts") {
                    Label(
                        "\(others.joined(separator: " and ")) also handle\(others.count == 1 ? "s" : "") permission prompts and can delay or override the answers you give in the notch. Turn \(others.count == 1 ? "it" : "them") off there, or remove \(others.count == 1 ? "its" : "their") hooks from \(target.configURL().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }
        }
        if status.statuses[.codex] == .installed {
            Section("Codex") {
                Label("Codex asks you to trust new hooks once: run /hooks in Codex and trust Orby.", systemImage: "checkmark.shield")
                    .font(.callout)
            }
        }
        ForEach(HookTarget.allCases.filter { $0.setupNote != nil && status.statuses[$0] == .installed }, id: \.self) { target in
            Section(target.agent.displayName) {
                Label(target.setupNote ?? "", systemImage: "info.circle").font(.callout)
            }
        }
        if status.statuses[.antigravity] == .installed || statusLine != .agentMissing {
            Section("Antigravity") {
                if status.statuses[.antigravity] == .installed {
                    Toggle("Answer Antigravity prompts from the notch", isOn: $answerAntigravity)
                    Text(
                        answerAntigravity
                            ? "Approve and Deny type the option into Antigravity's terminal, after checking its prompt is on screen there. Works in Orca, Terminal, iTerm2 and tmux; other terminals get “Go to terminal”."
                            : "When Antigravity asks, the notch opens with the command and jumps you to its terminal (⌘Y)."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if statusLine != .agentMissing {
                    Toggle(
                        "Plan limits from the agy status line",
                        isOn: Binding(get: { statusLine == .installed }, set: { setStatusLine($0) })
                    )
                    .disabled({ if case .unreadable = statusLine { return true } else { return false } }())
                    if case .unreadable(let why) = statusLine {
                        Text(why).font(.caption).foregroundStyle(.red)
                    }
                    Text(
                        "agy hands its plan quota to its status line command on every update. Orby sets that command in ~/.gemini/antigravity-cli/settings.json to its bridge, which passes the quota to Orby on this Mac and prints your own status line if you had one, or a short one. Turning it off restores your previous status line. Restart agy to pick up the change."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        Section("Bridge") {
            LabeledContent("Hook binary", value: bridgeInstalled ? NotchPaths.installedBridge.path : "Not installed")
            Button("Reinstall bridge") {
                bridgeInstalled = BridgeSetup.installIfNeeded()
            }
            Toggle("Automatically configure newly detected agents at launch", isOn: $autoConfigure)
        }
        if let message {
            Section { Text(message).font(.callout) }
        }
    }

    @ViewBuilder private func row(_ target: HookTarget) -> some View {
        let s = status.statuses[target] ?? .notInstalled
        HStack {
            AgentMascot(agent: target.agent, phase: s == .installed ? .done : .ready, size: 30)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.agent.displayName).font(.headline)
                Text(target.configURL().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch s {
            case .agentMissing:
                Text("Not found").foregroundStyle(.secondary)
            case .unreadable(let why):
                Text(why).foregroundStyle(.red).font(.caption)
            case .installed:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Remove") { apply(target, install: false) }
            case .partial:
                Button("Repair") { apply(target, install: true) }
            case .notInstalled:
                Button("Connect") { apply(target, install: true) }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func apply(_ target: HookTarget, install: Bool) {
        if install { bridgeInstalled = BridgeSetup.installIfNeeded() }
        do {
            let backup = try HookInstaller.apply(target, install: install)
            let verb = install ? "Connected \(target.agent.displayName)." : "Removed Orby hooks from \(target.agent.displayName)."
            message = verb + (backup.map { " Backup: \($0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))" } ?? "")
                + (install ? " Restart running sessions to pick it up." : "")
        } catch {
            message = error.localizedDescription
        }
        status = IntegrationStatus.current()
    }

    private func setStatusLine(_ on: Bool) {
        if on { bridgeInstalled = BridgeSetup.installIfNeeded() }
        do {
            let backup = try StatusLineInstaller.apply(install: on)
            statusLineWanted = on
            message = (on ? "Antigravity's status line now reports plan limits to Orby." : "Restored Antigravity's previous status line.")
                + (backup.map { " Backup: \($0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))" } ?? "")
                + " Restart agy to pick it up."
        } catch {
            message = error.localizedDescription
        }
        statusLine = StatusLineInstaller.status()
    }
}

private struct SoundSettings: View {
    let sound: SoundPlayer?
    @AppStorage(PrefKey.soundTheme) private var theme = SoundTheme.chiptune.rawValue
    @AppStorage(PrefKey.soundVolume) private var volume = 0.5
    @AppStorage(PrefKey.customSoundFolder) private var folder = ""

    var body: some View {
        Section("Theme") {
            Picker("Sounds", selection: $theme) {
                ForEach(SoundTheme.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Slider(value: $volume, in: 0...1) { Text("Volume") }
            if theme == SoundTheme.custom.rawValue {
                HStack {
                    Text(folder.isEmpty ? "No folder selected" : folder).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose Folder…") { chooseFolder() }
                }
                Text("Name files after events: approval, question, plan, done, error, start (.wav/.mp3/.m4a/.aiff). Missing files fall back to 8-bit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Events") {
            ForEach(SoundCue.allCases, id: \.self) { cue in
                CueRow(cue: cue, sound: sound)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}

private struct CueRow: View {
    let cue: SoundCue
    let sound: SoundPlayer?
    @AppStorage private var enabled: Bool

    init(cue: SoundCue, sound: SoundPlayer?) {
        self.cue = cue
        self.sound = sound
        _enabled = AppStorage(wrappedValue: cue != .start, PrefKey.soundEnabled(cue))
    }

    var body: some View {
        HStack {
            Toggle(cue.label, isOn: $enabled)
            Spacer()
            Button { sound?.play(cue, preview: true) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
        }
    }
}

private struct UsageSettings: View {
    let usage: UsageService?
    @AppStorage(PrefKey.claudeUsageEnabled) private var claudeEnabled = false
    @AppStorage(PrefKey.showUsageInHeader) private var showInHeader = true
    @AppStorage(PrefKey.antigravityUsageEnabled) private var antigravityEnabled = false

    var body: some View {
        Section {
            Toggle("Show Claude plan limits", isOn: $claudeEnabled)
                .onChange(of: claudeEnabled) { _, _ in usage?.refreshClaudeIfEnabled() }
        } header: {
            Text("Claude")
        } footer: {
            Text("Reads the Claude Code sign-in already stored in your keychain and asks Anthropic for your 5-hour and weekly usage. macOS may ask you to allow keychain access. Nothing else leaves your Mac.")
        }
        Section {
            Toggle("Fetch Antigravity quota (runs `agy /usage`)", isOn: $antigravityEnabled)
                .onChange(of: antigravityEnabled) { _, _ in usage?.refreshAntigravityIfEnabled(force: true) }
            LabeledContent(
                "Status line relay", value: StatusLineInstaller.status() == .installed ? "On" : "Off (Settings → Integrations)")
        } header: {
            Text("Antigravity")
        } footer: {
            Text(
                "Every 5 minutes, and when you open the Usage tab, Orby runs `agy -p \"/usage\" --output-format json`. agy answers it without starting a model turn, so it spends no quota and saves no conversation, but agy does ask Google for your quota using your own Antigravity sign-in. Needs agy 1.1.11 or later. The status line relay needs no network at all."
            )
        }
        Section {
            LabeledContent("Codex limits", value: "Read from ~/.codex/sessions")
            LabeledContent("Token history", value: "Read from local transcripts and databases")
            Toggle("Show plan limits in the panel header", isOn: $showInHeader)
            if showInHeader, let usage { HeaderLimitPicker(usage: usage) }
            Button("Refresh now") {
                usage?.refreshLocal()
                usage?.refreshClaudeIfEnabled()
                usage?.refreshAntigravityIfEnabled(force: true)
            }
        } header: {
            Text("Local")
        } footer: {
            Text("Counts tokens for Claude Code, Codex, OpenCode, Antigravity, Qwen Code, Pi and Command Code from their files on this Mac, read-only. Cursor keeps no token counts locally, so it isn't listed.")
        }
    }
}

/// Lets the user choose which limits sit in the panel header (up to three fit next to the tabs).
private struct HeaderLimitPicker: View {
    @ObservedObject var usage: UsageService
    @AppStorage(PrefKey.pickHeaderLimits) private var pick = false
    @AppStorage(PrefKey.headerLimits) private var stored = ""
    static let maxPicked = 3

    var body: some View {
        Picker("Header shows", selection: $pick) {
            Text("The 2 closest to running out").tag(false)
            Text("Limits I pick").tag(true)
        }
        if pick {
            let picked = Prefs.lines(stored)
            ForEach(choices, id: \.id) { choice in
                Toggle(isOn: binding(choice.id, picked)) {
                    HStack(spacing: 6) {
                        AgentBadge(agent: choice.agent, size: 14)
                        Text("\(choice.agent.displayName) \(choice.label)")
                    }
                }
                .disabled(!picked.contains(choice.id) && picked.count >= Self.maxPicked)
            }
            if choices.isEmpty { Text("No plan limits yet. Turn on a limit source above.").foregroundStyle(.secondary) }
        }
    }

    /// Windows with data now, plus picked ones still waiting for data (so they can be unpicked).
    private var choices: [(id: String, agent: AgentKind, label: String)] {
        var out = usage.limits.flatMap { l in l.windows.map { (RateLimits.windowID(l.provider, $0.label), l.provider, $0.label) } }
        for id in Prefs.lines(stored) where !out.contains(where: { $0.0 == id }) {
            let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2, let agent = AgentKind(rawValue: parts[0]) { out.append((id, agent, "\(parts[1]) (no data yet)")) }
        }
        return out.map { (id: $0.0, agent: $0.1, label: $0.2) }
    }

    private func binding(_ id: String, _ picked: [String]) -> Binding<Bool> {
        Binding(
            get: { picked.contains(id) },
            set: { on in stored = (on ? picked + [id] : picked.filter { $0 != id }).joined(separator: "\n") })
    }
}

private struct AboutSettings: View {
    var body: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            LabeledContent("Socket", value: NotchPaths.socket.path)
            Text("Orby shows your AI coding agents in the notch: live status, approvals, questions, plan review and jump-back. Everything stays on this Mac.")
                .font(.callout)
        }
        Section("Uninstall") {
            Button("Remove all agent hooks", role: .destructive) {
                for t in HookTarget.allCases where HookInstaller.status(t) == .installed || HookInstaller.status(t) == .partial {
                    _ = try? HookInstaller.apply(t, install: false)
                }
                _ = try? StatusLineInstaller.apply(install: false)
                Prefs.defaults.set(false, forKey: PrefKey.antigravityStatusLine)
            }
            Text("Run this before deleting the app. Hooks are guarded and do nothing if the bridge is missing.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
