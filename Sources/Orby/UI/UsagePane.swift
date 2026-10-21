import Charts
import NotchCore
import SwiftUI

struct UsagePane: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        UsageContent(usage: model.usage)
    }
}

private struct UsageContent: View {
    @ObservedObject var usage: UsageService
    @AppStorage(PrefKey.claudeUsageEnabled) private var claudeEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Plan limits") {
                if usage.limits.isEmpty {
                    Text(claudeEnabled ? "Loading…" : "Codex limits appear after your next Codex turn. Turn on Claude and Antigravity limits in Settings → Usage.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                ForEach(usage.limits, id: \.provider) { limits in
                    ProviderLimits(limits: limits)
                }
                ForEach([usage.claudeError, usage.antigravityError].compactMap { $0 }, id: \.self) { err in
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.attention)
                }
            }
            section("Tokens · last 7 days") {
                TokenChart(history: usage.history)
            }
        }
        .onAppear { usage.refreshAntigravityIfEnabled() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ProviderLimits: View {
    let limits: RateLimits

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AgentBadge(agent: limits.provider, size: 14)
                Text(limits.provider.displayName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.primaryText)
                if let plan = limits.plan {
                    Text(plan.capitalized).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
                Text("updated \(limits.fetchedAt.shortAgo)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            ForEach(limits.windows, id: \.label) { w in
                // Past its reset: the reading is old until the agent reports again.
                let stale = w.isStale()
                HStack(spacing: 8) {
                    Text(w.label).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 84, alignment: .leading)
                    ProgressBar(value: w.used).opacity(stale ? 0.35 : 1)
                    Text("\(Int((w.used * 100).rounded()))%").font(.system(size: 11, weight: .semibold, design: .rounded)).frame(width: 36, alignment: .trailing)
                        .opacity(stale ? 0.5 : 1)
                    Text(stale ? "already reset" : w.resetsAt.map { "resets \(Self.relative($0))" } ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 92, alignment: .trailing)
                }
                .foregroundStyle(Theme.secondaryText)
                .help(stale ? "This window has reset since it was read; it updates on the agent's next report." : "")
            }
        }
    }

    static func relative(_ d: Date) -> String {
        let s = Int(d.timeIntervalSinceNow)
        if s <= 0 { return "now" }
        if s < 3600 { return "in \(s / 60)m" }
        if s < 86400 { return "in \(s / 3600)h \((s % 3600) / 60)m" }
        return "in \(s / 86400)d \((s % 86400) / 3600)h"
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: max(3, g.size.width * min(1, value)))
                // Final 15% of a window is the danger zone.
                Rectangle().fill(Theme.error.opacity(0.6)).frame(width: 1).offset(x: g.size.width * 0.85)
            }
        }
        .frame(height: 6)
    }

    private var color: Color { value > 0.85 ? Theme.error : value > 0.6 ? Theme.attention : Theme.done }
}

private struct TokenChart: View {
    let history: TokenHistory

    struct Point: Identifiable {
        var id: String { day + agent.rawValue }
        var day: String
        var label: String
        var agent: AgentKind
        var tokens: Int
    }

    var body: some View {
        let days = history.lastDays(7)
        // Most tokens first: stacked at the bottom of each bar and leading the legend.
        let totals = history.agentTotals(lastDays: 7)
        let agents = totals.map(\.agent)
        let points = days.flatMap { day in
            agents.compactMap { agent -> Point? in
                guard let t = day.byAgent[agent], t > 0 else { return nil }
                return Point(day: day.day, label: Self.weekday(day.day), agent: agent, tokens: t)
            }
        }
        let today = days.last.map { history.total(day: $0.day) } ?? 0
        let week = totals.reduce(0) { $0 + $1.tokens }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                stat("Today", today)
                stat("7 days", week)
            }
            if !totals.isEmpty {
                FlowLayout(spacing: 12, lineSpacing: 4) {
                    ForEach(totals, id: \.agent) { t in
                        HStack(spacing: 5) {
                            Circle().fill(Theme.color(for: t.agent)).frame(width: 7, height: 7)
                            Text(t.agent.displayName).foregroundStyle(Theme.secondaryText)
                            Text(t.tokens.compactTokens).fontWeight(.semibold).foregroundStyle(Theme.primaryText)
                        }
                        .font(.system(size: 11, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }
            Chart(points) { p in
                BarMark(x: .value("Day", p.label), y: .value("Tokens", p.tokens))
                    .foregroundStyle(by: .value("Agent", p.agent.displayName))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: agents.map(\.displayName), range: agents.map(Theme.color(for:)))
            .chartXScale(domain: days.map { Self.weekday($0.day) })
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel {
                        if let n = v.as(Int.self) { Text(n.compactTokens).foregroundStyle(Theme.tertiaryText) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel { if let s = v.as(String.self) { Text(s).foregroundStyle(Theme.tertiaryText) } }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 110)
            Text("Counted from transcripts and databases on this Mac, including cache reads. Cursor keeps no token counts locally.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
            Text(value.compactTokens).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.primaryText)
        }
    }

    static func weekday(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return day }
        f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

/// Left-aligned rows that wrap, so the legend stays readable however many agents report usage.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
