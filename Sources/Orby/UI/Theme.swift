import NotchCore
import SwiftUI

enum Theme {
    static let surface = Color.black
    static let card = Color.white.opacity(0.07)
    static let cardHover = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.4)

    static let working = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let thinking = Color(red: 0.70, green: 0.56, blue: 1.0)
    static let attention = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let done = Color(red: 0.3, green: 0.85, blue: 0.5)
    static let error = Color(red: 1.0, green: 0.36, blue: 0.36)
    static let idle = Color.white.opacity(0.35)

    static func color(for phase: SessionPhase) -> Color {
        switch phase {
        case .thinking: thinking
        case .working, .compacting: working
        case .needsApproval, .needsAnswer, .planReview: attention
        case .done: done
        case .error: error
        case .ready, .waitingInput: idle
        }
    }

    static func color(for agent: AgentKind) -> Color {
        switch agent {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.9, green: 0.9, blue: 0.95)
        case .antigravity: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .unknown: Color.gray
        }
    }

    static func symbol(for agent: AgentKind) -> String {
        switch agent {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .antigravity: "chevron.up"
        case .unknown: "cpu"
        }
    }
}

/// Notch silhouette: concave flares at the top corners, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = topRadius, b = min(bottomRadius, r.height / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct AgentBadge: View {
    let agent: AgentKind
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: Theme.symbol(for: agent))
            .font(.system(size: size * 0.62, weight: .bold))
            .foregroundStyle(agent == .codex ? Color.black : Color.white)
            .frame(width: size, height: size)
            .background(Theme.color(for: agent), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .help(agent.displayName)
    }
}

/// Status dot that pulses while the agent works and glows when it needs you.
struct StatusDot: View {
    let phase: SessionPhase
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        let color = Theme.color(for: phase)
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: phase.needsUser ? color.opacity(0.9) : .clear, radius: 4)
            .opacity(phase.group == .working && pulse ? 0.35 : 1)
            .animation(
                phase.group == .working || phase.needsUser
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: pulse
            )
            .onAppear { pulse = true }
            .help(phase.label)
    }
}

/// Context-window fill as a small ring with the percentage on hover.
struct ContextRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .help("Context window \(Int(fraction * 100))% used")
    }

    private var color: Color {
        fraction > 0.85 ? Theme.error : fraction > 0.65 ? Theme.attention : Theme.working
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Color.white.opacity(0.14)
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

extension Date {
    var shortAgo: String {
        let s = Int(-timeIntervalSinceNow)
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}

extension Int {
    var compactTokens: String {
        switch self {
        case 1_000_000_000...: String(format: "%.1fB", Double(self) / 1e9)
        case 1_000_000...: String(format: "%.1fM", Double(self) / 1e6)
        case 1_000...: String(format: "%.1fK", Double(self) / 1e3)
        default: "\(self)"
        }
    }
}
