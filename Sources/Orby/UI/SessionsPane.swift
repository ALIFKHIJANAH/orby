import AppKit
import NotchCore
import SwiftUI

struct SessionsPane: View {
    @EnvironmentObject var model: IslandModel
    var maxHeight: CGFloat = 440

    var body: some View {
        if model.sessions.isEmpty {
            EmptyState()
        } else {
            FittedScroll(maxHeight: maxHeight) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.name) { group in
                        ProjectGroup(name: group.name, sessions: group.sessions)
                    }
                }
            }
        }
    }

    /// Group by project (main repo for worktrees), keeping the engine's priority order.
    private var groups: [(name: String, sessions: [AgentSession])] {
        var order: [String] = []
        var map: [String: [AgentSession]] = [:]
        for s in model.sessions {
            if map[s.projectName] == nil { order.append(s.projectName) }
            map[s.projectName, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }
}

/// Focus mode footer: what the other agents are doing, one click from the full list.
struct SessionStrip: View {
    @EnvironmentObject var model: IslandModel
    let requestSessionKey: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.peekSessions.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(summary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(model.peekSessions ? 90 : 0))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering ? Theme.primaryText : Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .disabled(others.isEmpty)
            Spacer()
            Button { model.tab = .usage } label: { Image(systemName: "chart.bar.fill") }
                .buttonStyle(IconButtonStyle(active: false))
                .help("Usage")
            Button { SettingsWindowController.shared.show() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(IconButtonStyle(active: false))
                .help("Settings")
        }
        .padding(.horizontal, 4)
    }

    private var others: [AgentSession] { model.sessions.filter { $0.id != requestSessionKey } }

    private var summary: String {
        let waiting = Set(model.pending.map(\.sessionKey)).subtracting([requestSessionKey]).count
        let working = others.filter { $0.phase.group == .working }.count
        let done = others.filter { $0.phase.group == .finished }.count
        let parts = [
            waiting > 0 ? "\(waiting) more waiting" : nil,
            working > 0 ? "\(working) working" : nil,
            done > 0 ? "\(done) done" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "No other sessions" : parts.joined(separator: " · ")
    }
}

private struct ProjectGroup: View {
    let name: String
    let sessions: [AgentSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill").font(.system(size: 9))
                Text(name).font(.system(size: 11, weight: .bold))
                if sessions.count > 1 { Text("\(sessions.count)").font(.system(size: 10, weight: .semibold)) }
            }
            .foregroundStyle(Theme.tertiaryText)
            .padding(.leading, 4)
            ForEach(sessions) { SessionRow(session: $0) }
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject var model: IslandModel
    let session: AgentSession
    @State private var hovering = false
    @State private var offscreen = false
    @State private var typingReply = false
    @State private var replyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row
                .contentShape(Rectangle())
                .onTapGesture { model.jump(to: session) }
            if typingReply {
                ReplyField(text: $replyText, agent: session.agent.displayName) {
                    model.reply(to: session, text: replyText)
                    replyText = ""
                    typingReply = false
                } cancel: {
                    typingReply = false
                }
            }
            if model.replying.contains(session.id) {
                Text("Sending your reply…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
            if let error = model.replyErrors[session.id] {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.attention)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovering ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(highlight, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .onScrollVisibility { offscreen = !$0 }
        .help("Click to jump to \(terminalName)")
        .contextMenu {
            Button("Jump to \(terminalName)") { model.jump(to: session) }
            if canReply { Button("Reply…") { typingReply = true } }
            if canStop { Button("Stop Agent (Esc)") { model.interrupt(session) } }
            if model.trusted[session.id] != nil {
                Button("Stop Trusting This Session") { model.untrust(sessionKey: session.id) }
            } else {
                Button("Trust Safe Requests for \(Int(Prefs.double(PrefKey.trustMinutes))) min") { model.trust(sessionKey: session.id) }
            }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.cwd, forType: .string)
            }
            Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd) }
            if let model = session.model { Text("Model: \(model)") }
            Divider()
            Button("Dismiss") { self.model.dismiss(session) }
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                AgentMascot(
                    agent: session.agent, phase: session.phase, size: 30, activity: session.activity?.kind,
                    subagents: session.activeSubagents, idleSince: session.updatedAt, paused: offscreen)
                StatusDot(phase: session.phase, size: 8, paused: offscreen)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
            .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title ?? session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let branch = session.git?.branch {
                        BranchChip(branch: branch, worktree: session.git?.isWorktree ?? false)
                    }
                    if let until = model.trusted[session.id] {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.done)
                            .help("Allowing safe requests without asking until \(until.formatted(date: .omitted, time: .shortened))")
                    }
                    if session.activeSubagents > 0 {
                        Label("\(session.activeSubagents)", systemImage: "person.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .help("\(session.activeSubagents) subagents running")
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        // A working session that has been quiet this long may be stuck, or just running a long build.
                        let quiet = session.phase.group == .working && context.date.timeIntervalSince(session.updatedAt) > 600
                        Text(session.updatedAt.shortAgo)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(quiet ? Theme.attention : Theme.tertiaryText)
                            .help(quiet ? "No new activity for \(session.updatedAt.shortAgo)" : "Last activity")
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .italic(session.phase == .thinking)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(detail)
                }
                if let tasks = session.tasks, tasks.total > 0 { TaskProgressLine(tasks: tasks) }
            }
            if hovering && canStop {
                Button { model.interrupt(session) } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(IconButtonStyle(active: false))
                    .help("Stop the agent's turn (presses Esc in its terminal)")
            } else if hovering && canReply && !typingReply {
                Button { typingReply = true } label: { Image(systemName: "arrowshape.turn.up.left.fill") }
                    .buttonStyle(IconButtonStyle(active: false))
                    .help("Reply to \(session.agent.displayName)")
            }
            if let ctx = session.contextPercent { ContextRing(fraction: ctx) }
        }
    }

    /// The agent sits at its prompt and its pane can be typed into.
    private var canReply: Bool {
        [.done, .waitingInput, .ready].contains(session.phase) && TerminalController.reach(session.terminal).type
    }

    private var canStop: Bool {
        session.phase.group == .working && TerminalController.reach(session.terminal).interrupt
    }

    private var highlight: Color {
        if model.highlightedSession == session.id { return Theme.done.opacity(0.8) }
        if session.phase.needsUser { return Theme.attention.opacity(0.6) }
        return Theme.stroke.opacity(0.5)
    }

    private var subtitle: String {
        switch session.phase {
        case .thinking:
            return session.thinking.map { "Thinking: " + $0 } ?? "Thinking…"
        case .working:
            return session.currentTool ?? (session.lastPrompt.map { "Working on: " + PlainText.summary($0, max: 120) } ?? "Working…")
        case .compacting: return "Compacting the conversation to free up context…"
        case .needsApproval, .needsAnswer, .planReview:
            return session.attention ?? session.phase.label
        case .done:
            return session.lastMessage ?? "Done. Click to jump back."
        case .error:
            return session.lastMessage ?? "Turn failed"
        case .ready, .waitingInput:
            return session.lastMessage ?? session.phase.label
        }
    }

    /// Raw command/path under the sentence, only while a tool is running or waiting on you.
    private var detail: String? {
        guard session.phase == .working || session.phase == .needsApproval else { return nil }
        return session.activity?.detail.map { ToolDescriber.firstLine($0, max: 300) }
    }

    private var subtitleColor: Color {
        switch session.phase {
        case .needsApproval, .needsAnswer, .planReview: Theme.attention
        case .error: Theme.error
        case .thinking: Theme.thinking.opacity(0.9)
        default: Theme.secondaryText
        }
    }

    private var terminalName: String {
        if let path = session.terminal.appBundlePath {
            return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        return session.terminal.termProgram ?? "terminal"
    }
}

/// The agent's to-do list as a bar and "3/7 · what it's on now".
private struct TaskProgressLine: View {
    let tasks: TaskList

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tasks.isFinished ? Theme.done : Theme.working)
                        .frame(width: g.size.width * tasks.fraction)
                }
            }
            .frame(width: 44, height: 3)
            Text("\(tasks.done)/\(tasks.total)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let current = tasks.current {
                Text(current).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.secondaryText)
        .padding(.top, 2)
        .help(tasks.items.map { ($0.status == .completed ? "✓ " : $0.status == .inProgress ? "▸ " : "· ") + $0.title }.joined(separator: "\n"))
    }
}

/// Inline prompt typed into the agent's terminal on Return.
private struct ReplyField: View {
    @Binding var text: String
    let agent: String
    let submit: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(Theme.tertiaryText)
            TextField("Reply to \(agent) and press Return", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: cancel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.working.opacity(0.5), lineWidth: 1))
        .onAppear { focused = true }
    }
}

struct BranchChip: View {
    let branch: String
    let worktree: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: worktree ? "arrow.triangle.branch" : "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 8, weight: .bold))
            Text(branch).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        .help(worktree ? "Worktree on \(branch)" : "Branch \(branch)")
    }
}

private struct EmptyState: View {
    @State private var integrations = IntegrationStatus.current()

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.tertiaryText)
            Text("No agents running")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(integrations.anyInstalled
                ? "Start Claude Code or Codex in any terminal. Sessions appear here."
                : "Connect your agents in Settings → Integrations to get started.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
            if !integrations.anyInstalled {
                Button("Open Settings") { SettingsWindowController.shared.show(tab: .integrations) }
                    .buttonStyle(PillButtonStyle(tint: Theme.working))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .onAppear { integrations = IntegrationStatus.current() }
    }
}

extension View {
    /// Reports when the view scrolls in or out of sight, so off-screen orbs can stop animating.
    /// A no-op before macOS 15, where the rows simply keep animating.
    @ViewBuilder func onScrollVisibility(_ action: @escaping (Bool) -> Void) -> some View {
        if #available(macOS 15, *) {
            onScrollVisibilityChange(threshold: 0.01, action)
        } else {
            self
        }
    }
}
