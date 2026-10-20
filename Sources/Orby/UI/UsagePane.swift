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
                    Text(claudeEnabled ? "Loading…" : "Codex limits appear after your next Codex turn. Turn on Claude limits in Settings → Usage.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                ForEach(usage.limits, id: \.provider) { limits in
                    ProviderLimits(limits: limits)
                }
                if let err = usage.claudeError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.attention)
                }
            }
            section("Tokens · last 7 days") {
                TokenChart(history: usage.history)
            }
        }
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
                HStack(spacing: 8) {
                    Text(w.label).font(.system(size: 11, weight: .medium)).frame(width: 64, alignment: .leading)
                    ProgressBar(value: w.used)
                    Text("\(Int(w.used * 100))%").font(.system(size: 11, weight: .semibold, design: .rounded)).frame(width: 36, alignment: .trailing)
                    Text(w.resetsAt.map { "resets \(Self.relative($0))" } ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 92, alignment: .trailing)
                }
                .foregroundStyle(Theme.secondaryText)
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
        let points = days.flatMap { day in
            AgentKind.allCases.compactMap { agent -> Point? in
                guard let t = day.byAgent[agent], t > 0 else { return nil }
                return Point(day: day.day, label: Self.weekday(day.day), agent: agent, tokens: t)
            }
        }
        let today = days.last.map { history.total(day: $0.day) } ?? 0
        let week = days.reduce(0) { $0 + history.total(day: $1.day) }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                stat("Today", today)
                stat("7 days", week)
                ForEach(AgentKind.allCases.filter { $0 != .unknown }, id: \.self) { agent in
                    let total = days.reduce(0) { $0 + ($1.byAgent[agent] ?? 0) }
                    if total > 0 { stat(agent.displayName, total) }
                }
            }
            Chart(points) { p in
                BarMark(x: .value("Day", p.label), y: .value("Tokens", p.tokens))
                    .foregroundStyle(by: .value("Agent", p.agent.displayName))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(
                domain: AgentKind.allCases.map(\.displayName), range: AgentKind.allCases.map(Theme.color(for:)))
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
            Text("Counted from transcripts on this Mac, including cache reads.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
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
