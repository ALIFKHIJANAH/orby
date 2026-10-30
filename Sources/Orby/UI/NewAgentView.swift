import AppKit
import NotchCore
import SwiftUI

/// Starts an agent in a new terminal: pick the agent, folder and terminal, type a first message.
struct NewAgentView: View {
    @EnvironmentObject var model: IslandModel
    @AppStorage(PrefKey.launchFolder) private var defaultFolder = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New agent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button { model.cancelCompose() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(active: false))
                    .help("Back to sessions")
            }
            HStack(spacing: 6) {
                ForEach(AgentLaunch.agents, id: \.self) { agent in
                    Chip(selected: draft.agent == agent) { draft.agent = agent } label: {
                        AgentBadge(agent: agent, size: 16)
                        Text(agent.displayName)
                    }
                }
            }
            HStack(spacing: 8) {
                folderMenu
                Spacer(minLength: 4)
                ForEach(LaunchTerminal.available) { terminal in
                    Chip(selected: draft.terminal == terminal) { draft.terminal = terminal } label: { Text(terminal.label) }
                }
            }
            if draft.terminal == .orca, worktree == nil {
                Text("Orca doesn't know this folder, so it opens in Terminal.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
            HStack(alignment: .bottom, spacing: 8) {
                promptField
                    .font(.system(size: 12.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.working.opacity(0.5), lineWidth: 1))
                Button(action: model.launch) {
                    Label(model.launching ? "Starting…" : "Start", systemImage: "return")
                }
                .buttonStyle(PillButtonStyle(tint: Theme.working))
                .disabled(model.launching)
                .help("Start \(draft.agent.displayName) in \(launchTerminal.label)")
            }
            if let error = model.launchError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.attention)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke.opacity(0.5), lineWidth: 1))
        .onAppear { focused = true }
    }

    /// ImageRenderer can't draw an AppKit text field, so previews show the text instead.
    @ViewBuilder private var promptField: some View {
        if PreviewRenderer.active {
            Text(draft.prompt).foregroundStyle(Theme.primaryText)
        } else {
            TextField("First message (optional)", text: $model.launchDraft.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(model.launch)
                .onExitCommand { model.cancelCompose(close: true) }
        }
    }

    private var draft: LaunchDraft {
        get { model.launchDraft }
        nonmutating set { model.launchDraft = newValue }
    }

    private var worktree: OrcaWorktree? { OrcaFleet.worktree(containing: draft.folder, in: model.orcaWorktrees) }

    private var launchTerminal: LaunchTerminal { draft.terminal == .orca && worktree == nil ? .terminal : draft.terminal }

    private var folderMenu: some View {
        let recent = model.launchFolders.filter { $0 != defaultFolder }
        let orca = model.orcaWorktrees.filter { $0.path != defaultFolder && !recent.contains($0.path) }
        return Menu {
            if !defaultFolder.isEmpty {
                Section("Default") { folderButton(defaultFolder) }
            }
            if !recent.isEmpty {
                Section("Recent") { ForEach(recent.prefix(8), id: \.self) { folderButton($0) } }
            }
            if !orca.isEmpty {
                Section("Orca") { ForEach(orca, id: \.path) { folderButton($0.path, branch: $0.branch) } }
            }
            Divider()
            Button("Choose Folder…") {
                if let path = FolderPicker.choose(from: draft.folder) { draft.folder = path }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill").font(.system(size: 10))
                Text((draft.folder as NSString).lastPathComponent)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(FolderPicker.abbreviate((draft.folder as NSString).deletingLastPathComponent))
                    .font(.system(size: 10.5))
                    .truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .lineLimit(1)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(draft.folder)
    }

    private func folderButton(_ path: String, branch: String? = nil) -> some View {
        let name = (path as NSString).lastPathComponent
        return Button(branch.map { "\(name) · \($0)" } ?? name) { draft.folder = path }
    }
}

/// A selectable capsule, for the launcher's agent and terminal choices.
private struct Chip<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { label }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.primaryText : Theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(selected || hovering ? Theme.cardHover : Color.white.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.working.opacity(0.7) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Floating compose button over the session list, like starting a new chat.
struct NewAgentButton: View {
    @EnvironmentObject var model: IslandModel
    @AppStorage(PrefKey.newAgentShortcut) private var shortcut = true
    @State private var hovering = false

    var body: some View {
        Button(action: model.startNewAgent) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.working, in: Circle())
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .help(shortcut ? "New agent (⌥⌘N)" : "New agent")
        .accessibilityLabel("New agent")
    }
}

enum FolderPicker {
    /// Asks for a folder. Orby comes to the front for the dialog; the window that had the keyboard
    /// (the notch's launcher, or Settings) gets it back after.
    @MainActor
    static func choose(from start: String) -> String? {
        let previous = NSApp.keyWindow
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !start.isEmpty { panel.directoryURL = URL(fileURLWithPath: start) }
        NSApp.activate()
        let path = panel.runModal() == .OK ? panel.url?.path : nil
        previous?.makeKey()
        return path
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
