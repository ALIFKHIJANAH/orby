import NotchCore
import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var model: IslandModel
    @AppStorage(PrefKey.panelWidth) private var panelWidth = 560.0
    @AppStorage(PrefKey.hideWhenIdle) private var hideWhenIdle = true

    private let wing: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            island
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { model.shapeSize = $0 }
            Spacer(minLength: 0)
        }
        .frame(width: NotchPanelController.canvas.width, height: NotchPanelController.canvas.height, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: collapsedWidth)
        .environment(\.colorScheme, .dark)
    }

    private var flare: CGFloat { model.metrics.hasNotch ? (model.isExpanded ? 14 : 6) : 0 }

    @ViewBuilder private var island: some View {
        let shape = NotchShape(topRadius: flare, bottomRadius: model.isExpanded ? 22 : (model.metrics.hasNotch ? 10 : 13))
        Group {
            if model.isExpanded {
                ExpandedView()
                    .padding(.top, model.metrics.notchHeight)
                    .frame(width: panelWidth)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                CollapsedView(wing: wing, showsContent: hasActivity)
                    .frame(width: max(0, collapsedWidth - 2 * flare), height: collapsedHeight)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, flare)
        .clipShape(shape)
        // Shadow on the static backdrop only: on the whole island it re-rendered and blurred
        // everything offscreen on every orb frame, even while collapsed with the shadow invisible.
        .background(shape.fill(Theme.surface).shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 18, y: 8))
        .contentShape(shape)
        .onTapGesture { if !model.isExpanded { model.expand(.click) } }
    }

    /// Visible only when there is something worth showing: once everything has been finished or
    /// idle for a while (`idleHideSeconds`), the tab shrinks back to the plain notch. Hovering
    /// still opens the full list.
    private var hasActivity: Bool {
        guard !model.sessions.isEmpty else { return false }
        return !(hideWhenIdle && model.idleTab)
    }

    private var collapsedHeight: CGFloat { model.metrics.notchHeight }

    private var collapsedWidth: CGFloat {
        let m = model.metrics
        if m.hasNotch { return m.notchWidth + (hasActivity ? 2 * wing : 0) + 2 * flare }
        return hasActivity ? 2 * wing + 96 : 0
    }
}

struct CollapsedView: View {
    @EnvironmentObject var model: IslandModel
    let wing: CGFloat
    /// False while the tab has shrunk back to the plain notch: the orb would still animate,
    /// unseen, under the hardware notch.
    var showsContent = true

    var body: some View {
        HStack(spacing: 0) {
            Group { if showsContent { leading } }.frame(width: wing)
            Spacer(minLength: 0)
            if !model.metrics.hasNotch {
                Text(summary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Group { if showsContent { trailing } }.frame(width: wing)
        }
        .opacity(model.sessions.isEmpty ? 0 : 1)
    }

    @ViewBuilder private var leading: some View {
        let concurrent = model.concurrentAgents
        if !concurrent.isEmpty {
            AgentCarousel(sessions: concurrent)
        } else if let lead = model.leadSession {
            AgentOrb(agent: lead.agent, phase: lead.phase, size: 20)
        }
    }

    @ViewBuilder private var trailing: some View {
        if model.attentionCount > 0 {
            Label("\(model.attentionCount)", systemImage: "exclamationmark")
                .labelStyle(CompactLabel(color: Theme.attention))
        } else if model.workingCount > 0 {
            WorkingIndicator(count: model.workingCount)
        } else if model.unreadCount > 0 {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.done)
        } else {
            Text("\(model.sessions.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var summary: String {
        if model.attentionCount > 0 { return "Needs you" }
        let concurrent = model.concurrentAgents
        if !concurrent.isEmpty { return concurrent.map(\.agent.displayName).joined(separator: " + ") }
        if model.workingCount > 0 { return "\(model.workingCount) working" }
        if model.unreadCount > 0 { return "Done" }
        return "\(model.sessions.count) idle"
    }
}

/// Takes turns showing each busy agent's orb. At every handoff the next one slides in beside the
/// current one, they face each other and chat for a moment, then the current one steps out.
private struct AgentCarousel: View {
    let sessions: [AgentSession]
    @State private var index = 0
    @State private var chatting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = sessions[index % sessions.count]
        let next = sessions[(index + 1) % sessions.count]
        let visible = chatting ? [current, next] : [current]
        ZStack {
            ForEach(visible, id: \.agent) { session in
                let isCurrent = session.agent == current.agent
                AgentOrb(
                    agent: session.agent, phase: session.phase, size: 20,
                    chat: chatting ? OrbChat(facing: isCurrent ? 1 : -1, turn: isCurrent ? 0 : 1) : nil)
                    .scaleEffect(chatting ? 0.8 : 1)
                    .offset(x: chatting ? (isCurrent ? -10 : 10) : 0)
                    .transition(transition)
            }
        }
        .frame(width: 20, height: 20)
        .task(id: sessions.map(\.agent)) {
            guard !PreviewRenderer.active else { return }
            while !Task.isCancelled {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { chatting = true }
                try? await Task.sleep(for: .seconds(2.4))
                if Task.isCancelled { break }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    chatting = false
                    index += 1
                }
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    /// Newcomers walk in from the right, the one leaving walks off to the left.
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: 18).combined(with: .opacity).combined(with: .scale(scale: 0.5)),
            removal: .offset(x: -18).combined(with: .opacity).combined(with: .scale(scale: 0.5)))
    }
}

private struct CompactLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon.font(.system(size: 10, weight: .black))
            configuration.title.font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color, in: Capsule())
    }
}

/// Three bouncing dots + count while agents work.
struct WorkingIndicator: View {
    let count: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: AgentOrb.frameInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Theme.working)
                        .frame(width: 4, height: 4)
                        .offset(y: -2.5 * max(0, sin(t * 6 - Double(i) * 0.7)))
                }
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.working)
                        .padding(.leading, 2)
                }
            }
        }
    }
}

struct ExpandedView: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            if model.tab == .sessions, let request = model.currentRequest, let session = model.session(for: request.sessionKey) {
                // Focus mode: the request owns the panel; other sessions wait in the strip.
                RequestFocusView(request: request, session: session)
                    .id(request.id)
                    .transition(.opacity)
                SessionStrip(requestSessionKey: session.id)
                if model.peekSessions { SessionsPane(maxHeight: 220) }
            } else {
                HeaderView()
                switch model.tab {
                case .sessions: SessionsPane()
                case .usage: UsagePane()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

struct HeaderView: View {
    @EnvironmentObject var model: IslandModel
    @AppStorage(PrefKey.showUsageInHeader) private var showUsage = true

    var body: some View {
        HStack(spacing: 8) {
            Text(statusLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            if showUsage { HeaderUsageChips(usage: model.usage) }
            tabButton(.sessions, "list.bullet")
            tabButton(.usage, "chart.bar.fill")
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(IconButtonStyle(active: false))
            .help("Settings")
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if model.attentionCount > 0 { parts.append("\(model.attentionCount) need you") }
        if model.workingCount > 0 { parts.append("\(model.workingCount) working") }
        let finished = model.sessions.count - model.attentionCount - model.workingCount
        if finished > 0 { parts.append("\(finished) finished") }
        return parts.isEmpty ? "No active agents" : parts.joined(separator: " · ")
    }

    private func tabButton(_ tab: IslandTab, _ symbol: String) -> some View {
        Button {
            model.tab = tab
        } label: {
            Image(systemName: symbol)
        }
        .buttonStyle(IconButtonStyle(active: model.tab == tab))
        .help(tab == .sessions ? "Sessions" : "Usage")
    }
}

private struct HeaderUsageChips: View {
    @ObservedObject var usage: UsageService
    @AppStorage(PrefKey.pickHeaderLimits) private var pick = false
    @AppStorage(PrefKey.headerLimits) private var picked = ""

    var body: some View {
        // Picking nothing shows nothing, rather than silently falling back to the automatic pair.
        let shown = pick ? (picked.isEmpty ? [] : RateLimits.headerWindows(usage.limits, picked: Prefs.lines(picked))) : RateLimits.headerWindows(usage.limits)
        ForEach(shown, id: \.id) { item in
            UsageChip(agent: item.agent, window: item.window)
        }
    }
}

struct UsageChip: View {
    let agent: AgentKind
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 4) {
            AgentBadge(agent: agent, size: 12)
            Text("\(window.label) \(Int((window.used * 100).rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(window.used > 0.85 ? Theme.error : Theme.secondaryText)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.card, in: Capsule())
        .help("\(agent.displayName) \(window.label) window: \(Int((window.used * 100).rounded()))% used")
    }
}

struct IconButtonStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Color.white : Theme.secondaryText)
            .frame(width: 26, height: 24)
            .background(active ? Theme.cardHover : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Only as tall as its content, scrolling once it would exceed `maxHeight`. Single layout pass.
struct FittedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        // CappedHeight proposes min(ideal, max); ViewThatFits then only picks the
        // ScrollView when the content really overflows.
        CappedHeight(maxHeight: maxHeight) {
            ViewThatFits(in: .vertical) {
                content
                ScrollView(.vertical) { content }
            }
        }
    }
}

/// Sizes its child to the child's ideal height, clamped to `maxHeight`.
private struct CappedHeight: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
