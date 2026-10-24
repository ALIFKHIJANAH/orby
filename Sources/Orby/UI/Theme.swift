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
        case .opencode: Color(red: 0.16, green: 0.74, blue: 0.68)
        case .pi: Color(red: 0.93, green: 0.36, blue: 0.62)
        case .commandcode: Color(red: 0.64, green: 0.86, blue: 0.30)
        case .qwen: Color(red: 0.48, green: 0.40, blue: 0.96)
        case .cursor: Color(red: 0.62, green: 0.66, blue: 0.74)
        case .unknown: Color.gray
        }
    }

    /// Light brand colors get dark eyes and glyphs.
    static func isLight(_ agent: AgentKind) -> Bool { [.codex, .commandcode, .cursor].contains(agent) }

    static func symbol(for agent: AgentKind) -> String {
        switch agent {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .antigravity: "chevron.up"
        case .opencode: "curlybraces"
        case .pi: "function"
        case .commandcode: "command"
        case .qwen: "sparkle"
        case .cursor: "cursorarrow"
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
        AgentLogo(agent: agent, size: size * 0.62)
            .frame(width: size, height: size)
            .background(Theme.color(for: agent), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .help(agent.displayName)
    }
}

/// The agent's logo in a round chip, cut out of whatever sits behind it by a dark ring.
struct AgentLogoBadge: View {
    let agent: AgentKind
    var size: CGFloat = 16

    var body: some View {
        AgentLogo(agent: agent, size: size * 0.6)
            .frame(width: size, height: size)
            .background(Theme.color(for: agent), in: Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(0.85), lineWidth: max(1.5, size * 0.09)).padding(-max(1.5, size * 0.09)))
            .shadow(color: .black.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// The agent's brand mark, falling back to its SF Symbol when there is none.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 12

    var body: some View {
        let ink = Theme.isLight(agent) ? Color.black : Color.white
        if let path = LogoShape.paths[agent] {
            LogoShape(path: path).fill(ink, style: FillStyle(eoFill: true)).frame(width: size, height: size)
        } else {
            Image(systemName: Theme.symbol(for: agent))
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(ink)
        }
    }
}

/// A logo path scaled to fit its frame, centred, keeping its aspect ratio.
private struct LogoShape: Shape {
    static let paths: [AgentKind: Path] = Dictionary(
        uniqueKeysWithValues: AgentKind.allCases.compactMap { a in AgentLogos.pathData(for: a).map { (a, Path(SVGPath.parse($0))) } })

    let path: Path

    func path(in rect: CGRect) -> Path {
        let box = path.boundingRect
        guard box.width > 0, box.height > 0 else { return Path() }
        let k = min(rect.width / box.width, rect.height / box.height)
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: k, y: k).translatedBy(x: -box.midX, y: -box.midY)
        return path.applying(t)
    }
}

/// Status dot that pulses while the agent works and glows when it needs you.
struct StatusDot: View {
    let phase: SessionPhase
    var size: CGFloat = 8
    var paused = false

    var body: some View {
        let color = Theme.color(for: phase)
        // Driven by the orbs' clock: a repeatForever animation would re-render the panel at the
        // display's full refresh rate.
        TimelineView(.animation(minimumInterval: AgentOrb.frameInterval, paused: paused || phase.group != .working)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .opacity(phase.group == .working ? 0.675 + 0.325 * cos(t * .pi / 0.8) : 1)
        }
        .shadow(color: phase.needsUser ? color.opacity(0.9) : .clear, radius: 4)
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
