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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AgentBadge(agent: session.agent, size: 22)
                StatusDot(phase: session.phase, size: 8)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title ?? session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let branch = session.git?.branch {
                        BranchChip(branch: branch, worktree: session.git?.isWorktree ?? false)
                    }
                    if session.activeSubagents > 0 {
                        Label("\(session.activeSubagents)", systemImage: "person.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .help("\(session.activeSubagents) subagents running")
                    }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(session.updatedAt.shortAgo)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.tertiaryText)
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
            }
            if let ctx = session.contextPercent { ContextRing(fraction: ctx) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovering ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(highlight, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.jump(to: session) }
        .help("Click to jump to \(terminalName)")
        .contextMenu {
            Button("Jump to \(terminalName)") { model.jump(to: session) }
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
