import NotchCore
import SwiftUI

/// ⌃⌥S: type to narrow, arrows to move, Return to go, Esc to close. The keys are handled by the
/// panel (see NotchPanelController) so they work whether or not the field has focus.
struct SessionSwitcherView: View {
    @EnvironmentObject var model: IslandModel
    @FocusState private var focused: Bool
    static let maxRows = 8

    var body: some View {
        let entries = model.switcherEntries
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiaryText)
                field.font(.system(size: 12.5))
                Button { model.closeSwitcher() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(active: false))
                    .help("Close (Esc)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.working.opacity(0.5), lineWidth: 1))

            if entries.isEmpty {
                Text(model.sessions.isEmpty ? "No sessions" : "No session matches")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(visible(entries).enumerated()), id: \.element.id) { offset, s in
                        let index = firstVisible(entries.count) + offset
                        row(s, selected: index == model.switcherSelection)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.switcherSelection = index
                                model.switchToSelected()
                            }
                    }
                }
            }
            Text("↑↓ to move · ⏎ to jump · esc to close")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke.opacity(0.5), lineWidth: 1))
        .onAppear { focused = true }
    }

    /// ImageRenderer can't draw an AppKit text field, so previews show the text instead.
    @ViewBuilder private var field: some View {
        if PreviewRenderer.active {
            Text(model.switcherQuery.isEmpty ? "Switch to session…" : model.switcherQuery)
                .foregroundStyle(model.switcherQuery.isEmpty ? Theme.tertiaryText : Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("Switch to session…", text: $model.switcherQuery)
                .textFieldStyle(.plain)
                .focused($focused)
        }
    }

    /// A window of rows that keeps the selection on screen without a scroll view.
    private func firstVisible(_ count: Int) -> Int {
        guard count > Self.maxRows else { return 0 }
        return min(max(0, model.switcherSelection - Self.maxRows / 2), count - Self.maxRows)
    }

    private func visible(_ entries: [AgentSession]) -> ArraySlice<AgentSession> {
        let start = firstVisible(entries.count)
        return entries[start..<min(entries.count, start + Self.maxRows)]
    }

    private func row(_ s: AgentSession, selected: Bool) -> some View {
        HStack(spacing: 10) {
            AgentBadge(agent: s.agent, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(s.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                    if let branch = s.git?.branch {
                        Text(branch)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                .lineLimit(1)
                if let title = s.title {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(s.phase.label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.color(for: s.phase))
            StatusDot(phase: s.phase, size: 7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selected ? Theme.cardHover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? Theme.working.opacity(0.6) : .clear, lineWidth: 1))
    }
}
