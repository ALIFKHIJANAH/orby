import NotchCore
import SwiftUI

/// The lead agent as a living orb in its brand color: eyes that wander, blink and react to the session's phase.
struct AgentOrb: View {
    let agent: AgentKind
    let phase: SessionPhase
    var size: CGFloat = 20
    /// Set while chatting with a neighbour orb: faces it and takes turns talking.
    var chat: OrbChat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phaseChangedAt = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let pose = OrbPose(
                phase: phase, t: context.date.timeIntervalSinceReferenceDate,
                sinceChange: context.date.timeIntervalSince(phaseChangedAt), chat: chat, motion: reduceMotion ? 0 : 1)
            // Oversized canvas so hops and pops can leave the orb's frame.
            Canvas { ctx, canvas in
                pose.draw(in: &ctx, size: canvas, radius: size / 2, fill: Theme.color(for: agent), eyes: agent == .codex ? .black : .white)
            }
            .frame(width: size * 2, height: size * 2)
            .shadow(color: Theme.color(for: phase).opacity(pose.glow), radius: size * 0.22)
        }
        .frame(width: size, height: size)
        .onChange(of: phase) { phaseChangedAt = .now }
        .help("\(agent.displayName) · \(phase.label)")
    }
}

struct OrbChat: Equatable {
    var facing: Double  // -1 = partner on the left, 1 = on the right
    var turn: Int  // 0 or 1; partners get different turns so they alternate
}

/// One frame of the orb, computed procedurally from time so it never needs state of its own.
private struct OrbPose {
    var offset = CGPoint.zero  // in radii
    var scale = CGSize(width: 1, height: 1)
    var tilt = 0.0  // degrees
    var gaze = CGPoint.zero  // -1...1, +y looks down
    var openness = 1.0
    var eyeScale = 1.0
    var wink = false  // right eye closes into a happy arch
    var sparkle = 0.0  // 0...1 size of the twinkle beside the orb
    var thought: Double?  // time driving the rising thought-bubble dots, nil = none
    var glow = 0.0

    init(phase: SessionPhase, t: Double, sinceChange: Double, chat: OrbChat? = nil, motion: Double) {
        switch phase {
        case .thinking:
            // Pondering: eyes roll slowly along the top, a little narrowed, head tilting
            // toward the gaze, floating; a thought bubble puffs up beside it.
            gaze = CGPoint(x: 0.7 * sin(t * 0.9), y: -0.6 + 0.08 * sin(t * 1.8))
            openness = 0.8
            eyeScale = 0.92
            tilt = -7 * sin(t * 0.9)
            offset.y = -0.05 * sin(t * 1.5)
            thought = t
            glow = 0.35 + 0.2 * sin(t * 1.8)
        case .working, .compacting:
            // Thinking: quick glances around the upper half, a restless bob.
            gaze = Self.saccade(t, dwell: 0.55, spread: CGSize(width: 0.75, height: 0.3), bias: CGPoint(x: 0, y: -0.25))
            offset.y = -0.06 * sin(t * 3)
            tilt = 6 * sin(t * 1.4)
            if phase == .compacting {
                openness = 0.3
                scale = Self.squash(0.06 * sin(t * 2.4))
            }
            glow = 0.45 + 0.3 * sin(t * 3.2)
        case .needsApproval, .needsAnswer, .planReview:
            // Looks down at you and hops for attention.
            gaze = CGPoint(x: 0.1 * sin(t * 1.3), y: 0.55)
            eyeScale = 1.15
            let u = t.truncatingRemainder(dividingBy: 1.6) / 1.6
            if u < 0.3 {
                let h = sin(.pi * u / 0.3)
                offset.y = -0.22 * h
                scale = Self.squash(-0.08 * h)
            } else if u < 0.4 {
                scale = Self.squash(0.1 * sin(.pi * (u - 0.3) / 0.1))
            }
            glow = 0.75 + 0.2 * sin(t * 5)
        case .done:
            // Pleased with itself: glances up-right, nods, winks now and then, a sparkle twinkles.
            gaze = CGPoint(x: 0.4, y: -0.4)
            tilt = 4 * sin(t * 1.2)
            offset.y = -0.04 * sin(t * 2.4)
            let u = t.truncatingRemainder(dividingBy: 3.2)
            wink = u > 0.5 && u < 0.9
            sparkle = pow(max(0, sin(.pi * t.truncatingRemainder(dividingBy: 1.6) / 1.6)), 2)
            glow = 0.35
        case .error:
            // Droopy and downcast, with a small head shake now and then.
            gaze = CGPoint(x: 0, y: 0.45)
            openness = 0.45
            let s = t.truncatingRemainder(dividingBy: 3.2)
            if s < 0.5 { offset.x = 0.08 * sin(s * 40) * (1 - s / 0.5) }
            glow = 0.55
        case .ready, .waitingInput:
            gaze = Self.saccade(t, dwell: 1.9, spread: CGSize(width: 0.6, height: 0.45), bias: .zero)
            scale = Self.squash(-0.025 * sin(t * 1.7))
            offset.y = 0.03 * sin(t * 1.7)
        }

        if let chat {
            // Holds still facing its partner; only the eyes talk: the speaker's widen and squint
            // in a chatty rhythm, the listener's stay on the speaker.
            gaze = CGPoint(x: 0.8 * chat.facing, y: -0.1)
            offset = .zero
            scale = CGSize(width: 1, height: 1)
            tilt = 0
            thought = nil
            sparkle = 0
            openness = 1
            eyeScale = 1
            if Int(floor(t / 0.6)) % 2 == chat.turn {
                let flap = abs(sin(t * 11))
                openness = 1 - 0.35 * flap * motion
                eyeScale = 1 + 0.12 * flap * motion
                gaze.y -= 0.15 * flap * motion
            }
        }

        openness *= Self.blink(t)

        if sinceChange < 0.45 {
            // A startled pop whenever the phase changes.
            let k = sin(.pi * sinceChange / 0.45)
            scale.width *= 1 + 0.16 * k
            scale.height *= 1 + 0.16 * k
            eyeScale *= 1 + 0.2 * k
            openness = max(openness, k)
        }

        offset = CGPoint(x: offset.x * motion, y: offset.y * motion)
        gaze = CGPoint(x: gaze.x * motion, y: gaze.y * motion)
        tilt *= motion
        scale = CGSize(width: 1 + (scale.width - 1) * motion, height: 1 + (scale.height - 1) * motion)
        let m = hypot(gaze.x, gaze.y)
        if m > 1 { gaze = CGPoint(x: gaze.x / m, y: gaze.y / m) }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize, radius r: CGFloat, fill: Color, eyes: Color) {
        ctx.translateBy(x: size.width / 2 + offset.x * r, y: size.height / 2 + offset.y * r)
        ctx.rotate(by: .degrees(tilt))
        // Squash about the bottom so landings look grounded.
        ctx.translateBy(x: 0, y: r)
        ctx.scaleBy(x: scale.width, y: scale.height)
        ctx.translateBy(x: 0, y: -r)

        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(fill))
        for side in [-1.0, 1.0] { drawEye(in: ctx, side: side, r: r, color: eyes) }
        if sparkle > 0.01 { drawSparkle(in: ctx, at: CGPoint(x: 1.05 * r, y: -0.95 * r), size: 0.32 * r * sparkle, color: fill) }
        if let thought { drawThought(in: ctx, t: thought, r: r, color: Theme.thinking) }
    }

    /// Three dots rising up-right, lighting one after another like "…".
    private func drawThought(in ctx: GraphicsContext, t: Double, r: CGFloat, color: Color) {
        let dots: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 0.95 * r, y: -0.75 * r), 0.11 * r),
            (CGPoint(x: 1.2 * r, y: -1.05 * r), 0.15 * r),
            (CGPoint(x: 1.5 * r, y: -1.32 * r), 0.19 * r),
        ]
        for (i, (c, size)) in dots.enumerated() {
            let phase = (t * 1.6 - Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let lit = 0.35 + 0.65 * pow(max(0, sin(.pi * phase)), 2)
            let s = size * (0.85 + 0.15 * lit)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s)), with: .color(color.opacity(lit)))
        }
    }

    /// Four-point star with pinched sides.
    private func drawSparkle(in ctx: GraphicsContext, at c: CGPoint, size s: CGFloat, color: Color) {
        let pinch = s * 0.18
        var star = Path()
        star.move(to: CGPoint(x: c.x, y: c.y - s))
        star.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
        star.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
        star.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
        star.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
        ctx.fill(star, with: .color(color))
    }

    private func drawEye(in ctx: GraphicsContext, side: Double, r: CGFloat, color: Color) {
        // The eye on the side being looked toward is foreshortened, and both lean
        // along the sphere's meridians.
        let far = side * gaze.x > 0
        let persp = far ? 1 - 0.28 * abs(gaze.x) : 1
        let len = 0.56 * r * eyeScale * persp
        let wid = 0.28 * r * eyeScale * (far ? 0.85 : 1)

        var e = ctx
        e.translateBy(x: side * 0.3 * r * (1 - 0.2 * abs(gaze.x)) + gaze.x * 0.42 * r, y: -0.1 * r + gaze.y * 0.38 * r)
        e.rotate(by: .degrees(55 * gaze.x * gaze.y))

        if wink && side > 0 {
            var arch = Path()
            arch.move(to: CGPoint(x: -wid * 0.6, y: len * 0.15))
            arch.addQuadCurve(to: CGPoint(x: wid * 0.6, y: len * 0.15), control: CGPoint(x: 0, y: -len * 0.45))
            e.stroke(arch, with: .color(color), style: StrokeStyle(lineWidth: wid * 0.6, lineCap: .round))
            return
        }
        let h = max(len * openness, wid * 0.5)
        let w = openness < 0.3 ? wid * 1.2 : wid
        e.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: min(w, h) / 2), with: .color(color))
    }

    private static func squash(_ k: Double) -> CGSize { CGSize(width: 1 + k, height: 1 - k) }

    /// Holds a gaze target, then darts to the next one, like real eye saccades.
    private static func saccade(_ t: Double, dwell: Double, spread: CGSize, bias: CGPoint) -> CGPoint {
        let n = floor(t / dwell)
        func target(_ i: Double) -> CGPoint {
            CGPoint(x: bias.x + (rand(i, 3) * 2 - 1) * spread.width, y: bias.y + (rand(i, 4) * 2 - 1) * spread.height)
        }
        let x = min(1, (t - n * dwell) / 0.14)
        let k = x * x * (3 - 2 * x)
        let a = target(n - 1), b = target(n)
        return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    /// 1 = open. One blink at a random moment every ~4s, sometimes a double blink.
    private static func blink(_ t: Double) -> Double {
        let period = 4.2
        let n = floor(t / period)
        let at = n * period + rand(n, 1) * (period - 0.4)
        var closed = max(0, 1 - abs(t - at) / 0.08)
        if rand(n, 2) < 0.25 { closed = max(closed, 1 - abs(t - at - 0.22) / 0.08) }
        return 1 - closed
    }

    private static func rand(_ i: Double, _ salt: UInt64) -> Double {
        var x = UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15 ^ salt &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 31
        x &*= 0x94D0_49BB_1331_11EB
        x ^= x >> 29
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}
