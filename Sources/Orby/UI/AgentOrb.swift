import NotchCore
import SwiftUI

/// The lead agent as a living orb in its brand color: eyes that wander, blink and react to the session's phase.
struct AgentOrb: View {
    let agent: AgentKind
    let phase: SessionPhase
    var size: CGFloat = 20
    /// Set while chatting with a neighbour orb: faces it and takes turns talking.
    var chat: OrbChat?
    /// What the running tool is doing; while working the orb acts it out with a prop.
    var activity: ActivityKind?
    var subagents = 0
    /// When the session last did anything; an orb left idle long enough dozes off.
    var idleSince: Date?
    /// Stops the clock, e.g. while the orb is scrolled out of view.
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phaseChangedAt = Date.distantPast
    @State private var taskChangedAt = Date.distantPast

    /// Frame interval of lively orbs. Other notch animations reuse it so their ticks land on the
    /// same frames: two timelines at different rates render the whole panel at the union of both.
    static let frameInterval = 1.0 / 30

    var body: some View {
        TimelineView(.animation(minimumInterval: interval, paused: paused)) { context in
            let now = context.date
            let pose = OrbPose(
                phase: phase, task: phase == .working ? activity : nil, t: now.timeIntervalSinceReferenceDate,
                sinceChange: now.timeIntervalSince(phaseChangedAt), sinceTask: now.timeIntervalSince(taskChangedAt),
                idle: idleSince.map { now.timeIntervalSince($0) } ?? 0, subagents: subagents, chat: chat, motion: reduceMotion ? 0 : 1)
            // Oversized canvas so hops, pops and props can leave the orb's frame.
            Canvas { ctx, canvas in
                pose.draw(
                    in: &ctx, size: canvas, radius: size / 2, fill: Theme.color(for: agent), eyes: Theme.isLight(agent) ? .black : .white,
                    accent: Theme.color(for: phase))
            }
            .frame(width: size * 2, height: size * 2)
        }
        .frame(width: size, height: size)
        .onChange(of: phase) { phaseChangedAt = .now }
        .onChange(of: activity) { taskChangedAt = .now }
        .help("\(agent.displayName) · \(phase.label)")
    }

    /// Calm phases still blink and sway, but 15 fps is plenty for that; a dozing orb only
    /// breathes. Re-evaluated with the body, so dozing off may take until the next model update.
    private var interval: Double {
        if chat != nil || phase.isLively { return Self.frameInterval }
        let dozing = (phase == .ready || phase == .waitingInput) && (idleSince.map { -$0.timeIntervalSinceNow > 180 } ?? false)
        return (dozing ? 4 : 2) * Self.frameInterval
    }
}

/// The orb with the agent's logo pinned to its shoulder, for lists where several agents sit side by side.
struct AgentMascot: View {
    let agent: AgentKind
    var phase: SessionPhase = .ready
    var size: CGFloat = 30
    var activity: ActivityKind?
    var subagents = 0
    var idleSince: Date?
    var paused = false

    var body: some View {
        AgentOrb(agent: agent, phase: phase, size: size, activity: activity, subagents: subagents, idleSince: idleSince, paused: paused)
            .overlay(alignment: .topLeading) {
                AgentLogoBadge(agent: agent, size: size * 0.48)
                    .offset(x: -size * 0.22, y: -size * 0.22)
            }
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
    var asleep = false  // both eyes shut into soft arcs
    var sparkle = 0.0  // 0...1 size of the twinkle beside the orb
    var thought: Double?  // time driving the rising thought-bubble dots, nil = none
    var glow = 0.0
    var t = 0.0
    var task: ActivityKind?
    var subagents = 0
    var motion = 1.0

    init(
        phase: SessionPhase, task: ActivityKind? = nil, t: Double, sinceChange: Double, sinceTask: Double = .infinity, idle: Double = 0,
        subagents: Int = 0, chat: OrbChat? = nil, motion: Double
    ) {
        self.t = t
        self.task = chat == nil ? task : nil
        self.subagents = subagents
        self.motion = motion
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
            if let task = self.task { act(task) }
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
            if idle > 180 && chat == nil {
                // Dozing: eyes shut, slow deep breaths, a few z's drifting up.
                asleep = true
                gaze = CGPoint(x: 0, y: 0.2)
                scale = Self.squash(-0.045 * sin(t * 1.1))
                offset.y = 0.04 * sin(t * 1.1)
                tilt = 5
            } else {
                gaze = Self.saccade(t, dwell: 1.9, spread: CGSize(width: 0.6, height: 0.45), bias: .zero)
                scale = Self.squash(-0.025 * sin(t * 1.7))
                offset.y = 0.03 * sin(t * 1.7)
            }
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

        if !asleep { openness *= Self.blink(t) }

        if sinceChange < 0.45 {
            // A startled pop whenever the phase changes.
            let k = sin(.pi * sinceChange / 0.45)
            scale.width *= 1 + 0.16 * k
            scale.height *= 1 + 0.16 * k
            eyeScale *= 1 + 0.2 * k
            openness = max(openness, k)
        } else if sinceTask < 0.3 {
            // A smaller double-take when it picks up a new kind of tool.
            let k = sin(.pi * sinceTask / 0.3)
            scale.width *= 1 + 0.07 * k
            scale.height *= 1 - 0.05 * k
            eyeScale *= 1 + 0.12 * k
        }

        offset = CGPoint(x: offset.x * motion, y: offset.y * motion)
        gaze = CGPoint(x: gaze.x * motion, y: gaze.y * motion)
        tilt *= motion
        scale = CGSize(width: 1 + (scale.width - 1) * motion, height: 1 + (scale.height - 1) * motion)
        let m = hypot(gaze.x, gaze.y)
        if m > 1 { gaze = CGPoint(x: gaze.x / m, y: gaze.y / m) }
    }

    // MARK: Acting out the tool

    /// Body language for each kind of work; the matching prop is drawn in `drawProps`.
    private mutating func act(_ task: ActivityKind) {
        switch task {
        case .read:
            // Eyes run along a line of the page it's holding, snap back, drop a line.
            let (row, u) = Self.cycle(t, 1.2, rows: 3)
            let sweep = u < 0.82 ? u / 0.82 : 1 - (u - 0.82) / 0.18
            gaze = CGPoint(x: -0.6 + 1.2 * sweep, y: 0.55 + 0.12 * Double(row))
            openness = 0.85
            tilt = -3 + 2 * sin(t * 0.8)
            offset.y = -0.02 * sin(t * 2)
        case .edit:
            // Typing: eyes follow the caret, a quick tapping bob, focused squint.
            let (_, u) = Self.cycle(t, 1.6, rows: 3)
            gaze = CGPoint(x: -0.55 + 1.1 * u, y: 0.65)
            openness = 0.7
            let k = abs(sin(t * 10))
            offset.y = 0.03 * k
            scale = Self.squash(0.035 * k)
            tilt = -2
        case .search:
            // Peering through a magnifier that sweeps a figure eight; eyes wide.
            let a = t * 1.7
            let lens = Self.lens(a)
            gaze = CGPoint(x: lens.x * 0.95, y: lens.y * 0.95)
            eyeScale = 1.2
            tilt = 9 * sin(a)
            offset.y = -0.03 * sin(2 * a)
        case .web:
            // Floating, tracking a satellite on its orbit.
            let a = t * 2.1
            gaze = CGPoint(x: 0.8 * cos(a), y: 0.3 * sin(a) - 0.2)
            offset.y = -0.07 * sin(t * 1.3)
            tilt = 5 * cos(a)
        case .run:
            // Jogging on the spot, leaning in, with speed lines behind.
            let u = (t * 2.6).truncatingRemainder(dividingBy: 1)
            let hop = sin(.pi * u)
            offset.y = -0.13 * hop
            scale = Self.squash(u < 0.15 ? 0.09 * sin(.pi * u / 0.15) : -0.05 * hop)
            gaze = CGPoint(x: 0.5, y: 0.05)
            openness = 0.85
            tilt = -7
        case .test:
            // Scrutinising: narrowed eyes, slow scan, a nod each time a check pops.
            gaze = CGPoint(x: 0.6 * sin(t * 0.9), y: 0.15)
            openness = 0.5
            eyeScale = 1.05
            let u = t.truncatingRemainder(dividingBy: 1.4) / 1.4
            offset.y = u < 0.2 ? 0.06 * sin(.pi * u / 0.2) : 0
        case .build:
            // Stomping like a hammer: rises, rocks back, slams down with a squash and dust.
            let u = t.truncatingRemainder(dividingBy: 0.8) / 0.8
            if u < 0.6 {
                let k = sin(.pi / 2 * u / 0.6)
                offset.y = -0.16 * k
                tilt = -8 * k
                scale = Self.squash(-0.05 * k)
            } else if u < 0.7 {
                let k = (u - 0.6) / 0.1
                offset.y = -0.16 * (1 - k)
                tilt = -8 * (1 - k)
            } else {
                scale = Self.squash(0.14 * (1 - (u - 0.7) / 0.3))
            }
            gaze = CGPoint(x: 0.15, y: 0.25)
            openness = 0.6
            eyeScale = 1.05
        case .git:
            // Watches commits light up along a branch, hopping as each lands.
            let (row, u) = Self.cycle(t, 0.55, rows: 3)
            gaze = CGPoint(x: 0.85, y: Self.gitNodes[row] * 0.7)
            offset.y = u < 0.3 ? -0.08 * sin(.pi * u / 0.3) : 0
            tilt = 4
        case .delete:
            // Wincing: squeezed eyes and a nervous shiver in bursts while crumbs fall.
            gaze = CGPoint(x: 0.35, y: 0.45)
            openness = 0.38
            eyeScale = 0.95
            let s = t.truncatingRemainder(dividingBy: 1.2)
            if s < 0.35 { offset.x = 0.05 * sin(s * 60) * (1 - s / 0.35) }
            scale = Self.squash(0.04)
        case .delegate:
            // Keeps an eye on its little helpers as they circle round.
            let a = t * 1.5
            gaze = CGPoint(x: 0.85 * cos(a), y: 0.3 * sin(a))
            offset.y = -0.04 * sin(t * 2)
            eyeScale = 1.05
        case .plan:
            // Looking up and to the side, working through a checklist.
            gaze = CGPoint(x: -0.55 + 0.1 * sin(t * 1.3), y: -0.5)
            openness = 0.85
            tilt = 6 * sin(t * 0.7)
            offset.y = -0.04 * sin(t * 1.4)
        }
    }

    // MARK: Drawing

    func draw(in ctx: inout GraphicsContext, size: CGSize, radius r: CGFloat, fill: Color, eyes: Color, accent: Color) {
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        // World space: centred on the orb's resting spot, unaffected by its tilt and squash.
        let world = ctx
        drawProps(in: world, r: r, fill: fill, eyes: eyes, accent: accent, front: false)

        ctx.translateBy(x: offset.x * r, y: offset.y * r)
        ctx.rotate(by: .degrees(tilt))
        // Squash about the bottom so landings look grounded.
        ctx.translateBy(x: 0, y: r)
        ctx.scaleBy(x: scale.width, y: scale.height)
        ctx.translateBy(x: 0, y: -r)

        // Glow drawn in the canvas: a view-level .shadow on content that changes every frame
        // forces an offscreen render and blur per frame.
        if glow > 0.01 {
            let g = 1.45 * r
            ctx.fill(
                Path(ellipseIn: CGRect(x: -g, y: -g, width: 2 * g, height: 2 * g)),
                with: .radialGradient(
                    Gradient(colors: [accent.opacity(glow * 0.8), accent.opacity(0)]), center: .zero, startRadius: 0.85 * r, endRadius: g))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(fill))
        for side in [-1.0, 1.0] { drawEye(in: ctx, side: side, r: r, color: eyes) }
        drawHeldProps(in: ctx, r: r, accent: accent)
        drawProps(in: world, r: r, fill: fill, eyes: eyes, accent: accent, front: true)
        if sparkle > 0.01 { drawSparkle(in: ctx, at: CGPoint(x: 1.05 * r, y: -0.95 * r), size: 0.32 * r * sparkle, color: fill) }
        if let thought { drawThought(in: ctx, t: thought, r: r, color: Theme.thinking) }
        if asleep { drawSnores(in: world, r: r) }
    }

    /// Props the orb holds, so they move with its tilt and squash.
    private func drawHeldProps(in ctx: GraphicsContext, r: CGFloat, accent: Color) {
        let t = self.t * motion
        switch task {
        case .read:
            let (row, u) = Self.cycle(t, 1.2, rows: 3)
            drawPage(in: ctx, r: r, accent: accent, row: row, progress: u < 0.82 ? u / 0.82 : 1, writing: false)
        case .edit:
            let (row, u) = Self.cycle(t, 1.6, rows: 3)
            drawPage(in: ctx, r: r, accent: accent, row: row, progress: u, writing: true)
        case .search:
            drawLens(in: ctx, at: Self.lens(t * 1.7), r: r)
        default:
            break
        }
    }

    /// Props around the orb. `front: false` draws the parts that pass behind it.
    private func drawProps(in ctx: GraphicsContext, r: CGFloat, fill: Color, eyes: Color, accent: Color, front: Bool) {
        let t = self.t * motion
        switch task {
        case .web:
            // Satellite with a fading trail on a tilted orbit.
            for i in (0..<7).reversed() {
                let a = t * 2.1 - Double(i) * 0.13
                guard (sin(a) >= 0) == front else { continue }
                let p = Self.orbit(a, r: r)
                let s = r * (i == 0 ? 0.17 : 0.11 * (1 - Double(i) / 8)) * (0.85 + 0.15 * sin(a))
                let op = i == 0 ? 1 : 0.5 * (1 - Double(i) / 7)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s)), with: .color(Theme.working.opacity(op)))
            }
        case .delegate:
            let n = min(3, max(1, subagents))
            for i in 0..<n {
                let a = t * 1.5 + Double(i) * 2 * .pi / Double(n)
                guard (sin(a) >= 0) == front else { continue }
                drawHelper(in: ctx, at: Self.orbit(a, r: r), r: r * 0.3 * (0.85 + 0.15 * sin(a)), fill: fill, eyes: eyes, t: t + Double(i))
            }
        case .run where !front:
            for (i, y) in [-0.35, 0.05, 0.45].enumerated() {
                let k = 0.5 + 0.5 * sin(t * 9 + Double(i) * 1.7)
                let x0 = -1.2 * r, len = r * (0.3 + 0.35 * k)
                var line = Path()
                line.move(to: CGPoint(x: x0, y: y * r))
                line.addLine(to: CGPoint(x: x0 - len, y: y * r))
                ctx.stroke(line, with: .color(.white.opacity(0.25 + 0.3 * k)), style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round))
            }
        case .build where front:
            let u = t.truncatingRemainder(dividingBy: 0.8) / 0.8
            guard u >= 0.7 else { break }
            let k = (u - 0.7) / 0.3
            for side in [-1.0, 1.0] {
                for j in 0..<2 {
                    let s = r * (0.15 - 0.04 * Double(j)) * (1 - 0.4 * k)
                    let c = CGPoint(x: side * r * (0.75 + 0.55 * k + 0.2 * Double(j)), y: r * (0.95 - 0.25 * k - 0.1 * Double(j)))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s)), with: .color(.white.opacity(0.55 * (1 - k))))
                }
            }
        case .git where front:
            let (row, u) = Self.cycle(t, 0.55, rows: 3)
            let x = 1.45 * r
            var line = Path()
            line.move(to: CGPoint(x: x, y: Self.gitNodes[0] * r))
            line.addLine(to: CGPoint(x: x, y: Self.gitNodes[2] * r))
            ctx.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: r * 0.07)
            for (i, y) in Self.gitNodes.enumerated() {
                let lit = i == row
                let s = r * (lit ? 0.14 + 0.04 * sin(.pi * min(1, u * 3)) : 0.11)
                let c = CGPoint(x: x, y: y * r)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s)), with: .color(lit ? accent : .white.opacity(0.45)))
                if lit && u < 0.6 {
                    let ring = s + r * 0.25 * u / 0.6
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: 2 * ring, height: 2 * ring)),
                        with: .color(accent.opacity(0.6 * (1 - u / 0.6))), lineWidth: r * 0.05)
                }
            }
        case .test where front:
            // A check mark pops up, holds, and fades.
            let u = t.truncatingRemainder(dividingBy: 1.4) / 1.4
            let pop = u < 0.2 ? Self.overshoot(u / 0.2) : 1
            let op = u < 0.75 ? 1 : 1 - (u - 0.75) / 0.25
            drawCheck(in: ctx, at: CGPoint(x: 1.2 * r, y: -0.95 * r), size: r * 0.32 * pop, color: Theme.done.opacity(op), width: r * 0.12)
        case .plan where front:
            // A three-item checklist ticking off one by one.
            let u = t.truncatingRemainder(dividingBy: 3) / 3
            for (i, y) in [-0.6, 0.0, 0.6].enumerated() {
                let box = CGRect(x: 1.25 * r, y: (y - 0.14) * r, width: 0.28 * r, height: 0.28 * r)
                ctx.stroke(Path(roundedRect: box, cornerRadius: r * 0.06), with: .color(.white.opacity(0.5)), lineWidth: r * 0.05)
                let at = 0.15 + Double(i) * 0.22
                guard u > at else { continue }
                let pop = Self.overshoot(min(1, (u - at) / 0.08))
                drawCheck(in: ctx, at: CGPoint(x: box.midX, y: box.midY), size: r * 0.2 * pop, color: Theme.done, width: r * 0.08)
            }
        case .delete where front:
            // Crumbs tumbling off the bottom.
            for i in 0..<3 {
                let p = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let c = CGPoint(x: r * (0.35 + 0.25 * Double(i) + 0.2 * p), y: r * (0.8 + 0.9 * p * p))
                let s = r * 0.1 * (1 - 0.4 * p)
                var crumb = ctx
                crumb.translateBy(x: c.x, y: c.y)
                crumb.rotate(by: .radians(p * 5 + Double(i)))
                crumb.fill(Path(CGRect(x: -s, y: -s, width: 2 * s, height: 2 * s)), with: .color(.white.opacity(0.75 * (1 - p))))
            }
        default:
            break
        }
    }

    /// A little page held in front of the body; the line being read or written is lit.
    private func drawPage(in ctx: GraphicsContext, r: CGFloat, accent: Color, row: Int, progress: Double, writing: Bool) {
        var page = ctx
        page.translateBy(x: 0, y: 0.82 * r)
        page.rotate(by: .degrees(-6))
        let rect = CGRect(x: -0.62 * r, y: -0.38 * r, width: 1.24 * r, height: 0.76 * r)
        page.fill(Path(roundedRect: rect, cornerRadius: r * 0.1), with: .color(Color(white: 0.97)))
        page.stroke(Path(roundedRect: rect, cornerRadius: r * 0.1), with: .color(.black.opacity(0.18)), lineWidth: r * 0.04)
        let x0 = -0.46 * r, full = 0.92 * r
        for i in 0..<3 {
            let y = (-0.18 + 0.18 * Double(i)) * r
            let len = full * (i == 2 ? 0.62 : 1)
            func bar(_ to: CGFloat, _ color: Color) {
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x0 + max(0.01, to), y: y))
                page.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round))
            }
            if writing {
                // Earlier lines are written, the current one grows behind a blinking caret.
                if i < row { bar(len, Color(white: 0.55)) }
                if i == row {
                    let end = len * progress
                    bar(end, accent)
                    if sin(t * 12) > -0.2 {
                        var caret = Path()
                        caret.move(to: CGPoint(x: x0 + end + r * 0.07, y: y - r * 0.09))
                        caret.addLine(to: CGPoint(x: x0 + end + r * 0.07, y: y + r * 0.09))
                        page.stroke(caret, with: .color(.black.opacity(0.7)), lineWidth: r * 0.045)
                    }
                }
            } else {
                bar(len, Color(white: 0.78))
                if i == row { bar(len * progress, accent) }
            }
        }
    }

    private func drawLens(in ctx: GraphicsContext, at c: CGPoint, r: CGFloat) {
        let center = CGPoint(x: c.x * r, y: c.y * r - 0.05 * r), rr = 0.34 * r
        var handle = Path()
        handle.move(to: CGPoint(x: center.x + rr * 0.72, y: center.y + rr * 0.72))
        handle.addLine(to: CGPoint(x: center.x + rr * 1.55, y: center.y + rr * 1.55))
        ctx.stroke(handle, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: r * 0.14, lineCap: .round))
        let ring = Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr))
        ctx.fill(ring, with: .color(.white.opacity(0.22)))
        ctx.stroke(ring, with: .color(Color(white: 0.95)), lineWidth: r * 0.09)
        // Glint
        var glint = Path()
        glint.addArc(center: center, radius: rr * 0.62, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        ctx.stroke(glint, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: r * 0.06, lineCap: .round))
    }

    /// A mini orb with dot eyes, for subagents.
    private func drawHelper(in ctx: GraphicsContext, at c: CGPoint, r s: CGFloat, fill: Color, eyes: Color, t: Double) {
        let bob = 0.15 * s * sin(t * 6)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - s, y: c.y - s + bob, width: 2 * s, height: 2 * s)), with: .color(fill))
        let open = Self.blink(t * 1.3)
        for side in [-1.0, 1.0] {
            let w = s * 0.26, h = max(w * 0.5, s * 0.55 * open)
            let e = CGRect(x: c.x + side * s * 0.32 - w / 2, y: c.y - s * 0.12 - h / 2 + bob, width: w, height: h)
            ctx.fill(Path(roundedRect: e, cornerRadius: w / 2), with: .color(eyes))
        }
    }

    private func drawCheck(in ctx: GraphicsContext, at c: CGPoint, size s: CGFloat, color: Color, width: CGFloat) {
        guard s > 0.1 else { return }
        var p = Path()
        p.move(to: CGPoint(x: c.x - s, y: c.y))
        p.addLine(to: CGPoint(x: c.x - s * 0.3, y: c.y + s * 0.7))
        p.addLine(to: CGPoint(x: c.x + s, y: c.y - s * 0.75))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// Three z's drifting up and growing as they fade.
    private func drawSnores(in ctx: GraphicsContext, r: CGFloat) {
        // Lay the glyph out once and scale it, rather than resolving three Texts every frame.
        let z = ctx.resolve(Text("z").font(.system(size: r, weight: .heavy, design: .rounded)).foregroundColor(.white))
        for i in 0..<3 {
            let p = (t * 0.45 * motion + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var c = ctx
            c.translateBy(x: r * (0.85 + 0.5 * p + 0.12 * sin(p * 6)), y: -r * (0.65 + 0.85 * p))
            c.scaleBy(x: 0.45 + 0.35 * p, y: 0.45 + 0.35 * p)
            c.opacity = 0.8 * sin(.pi * p)
            c.draw(z, at: .zero)
        }
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

        if asleep {
            // Shut: a soft downward curve.
            var lid = Path()
            lid.move(to: CGPoint(x: -wid * 0.75, y: 0))
            lid.addQuadCurve(to: CGPoint(x: wid * 0.75, y: 0), control: CGPoint(x: 0, y: len * 0.32))
            e.stroke(lid, with: .color(color), style: StrokeStyle(lineWidth: wid * 0.5, lineCap: .round))
            return
        }
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

    // MARK: Motion helpers

    private static let gitNodes: [Double] = [-0.6, 0, 0.6]

    /// Which of `rows` steps a repeating `period` is on, and how far through it (0...1).
    private static func cycle(_ t: Double, _ period: Double, rows: Int) -> (Int, Double) {
        let n = floor(t / period)
        return (Int(n.truncatingRemainder(dividingBy: Double(rows))), t / period - n)
    }

    /// Magnifier centre (in radii) sweeping a figure eight across the face.
    private static func lens(_ a: Double) -> CGPoint { CGPoint(x: 0.8 * sin(a), y: 0.3 * sin(2 * a) + 0.1) }

    /// Point on a tilted orbit around the orb; `sin(a) > 0` is the near side.
    private static func orbit(_ a: Double, r: CGFloat) -> CGPoint {
        let x = 1.45 * r * cos(a), y = 0.42 * r * sin(a) - 0.15 * r
        let tilt = -0.26
        return CGPoint(x: x * cos(tilt) - y * sin(tilt), y: x * sin(tilt) + y * cos(tilt))
    }

    /// 0→1 with a little overshoot, for things popping in.
    private static func overshoot(_ x: Double) -> Double {
        let c = 2.2
        let u = x - 1
        return 1 + (c + 1) * u * u * u + c * u * u
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
