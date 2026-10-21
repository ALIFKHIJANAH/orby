import CoreGraphics
import Foundation

/// Parses SVG path data (`d` attribute) into a CGPath: M L H V C S Q T A Z, absolute and relative.
public enum SVGPath {
    public static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var s = Scanner(Array(d.utf8))
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCubic: CGPoint?, lastQuad: CGPoint?
        var cmd: UInt8 = 0

        while true {
            s.skipSeparators()
            guard let c = s.peek else { break }
            if Scanner.isCommand(c) {
                cmd = c
                s.i += 1
            } else if cmd == 0 {
                break
            }
            let rel = cmd >= 97  // lowercase
            func pt(_ x: Double, _ y: Double) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }

            switch cmd | 0x20 {
            case UInt8(ascii: "m"):
                guard let x = s.number(), let y = s.number() else { return path }
                cur = pt(x, y)
                start = cur
                path.move(to: cur)
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")  // extra pairs are line-tos
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "l"):
                guard let x = s.number(), let y = s.number() else { return path }
                cur = pt(x, y)
                path.addLine(to: cur)
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "h"):
                guard let x = s.number() else { return path }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "v"):
                guard let y = s.number() else { return path }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "c"):
                guard let x1 = s.number(), let y1 = s.number(), let x2 = s.number(), let y2 = s.number(),
                    let x = s.number(), let y = s.number()
                else { return path }
                let c1 = pt(x1, y1), c2 = pt(x2, y2), end = pt(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                cur = end; lastCubic = c2; lastQuad = nil
            case UInt8(ascii: "s"):
                guard let x2 = s.number(), let y2 = s.number(), let x = s.number(), let y = s.number() else { return path }
                let c1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = pt(x2, y2), end = pt(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                cur = end; lastCubic = c2; lastQuad = nil
            case UInt8(ascii: "q"):
                guard let x1 = s.number(), let y1 = s.number(), let x = s.number(), let y = s.number() else { return path }
                let c = pt(x1, y1), end = pt(x, y)
                path.addQuadCurve(to: end, control: c)
                cur = end; lastQuad = c; lastCubic = nil
            case UInt8(ascii: "t"):
                guard let x = s.number(), let y = s.number() else { return path }
                let c = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let end = pt(x, y)
                path.addQuadCurve(to: end, control: c)
                cur = end; lastQuad = c; lastCubic = nil
            case UInt8(ascii: "a"):
                guard let rx = s.number(), let ry = s.number(), let rot = s.number(), let large = s.flag(), let sweep = s.flag(),
                    let x = s.number(), let y = s.number()
                else { return path }
                let end = pt(x, y)
                addArc(path, from: cur, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = end; lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "z"):
                path.closeSubpath()
                cur = start
                lastCubic = nil; lastQuad = nil
                cmd = 0
            default:
                return path
            }
        }
        return path
    }

    /// SVG endpoint arc → center parameterisation → cubic segments of at most 90°.
    private static func addArc(
        _ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rx0: Double, ry ry0: Double, rotation: Double, large: Bool, sweep: Bool
    ) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var k = (max(0, num) / den).squareRoot()
        if large == sweep { k = -k }
        let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / Double(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        func point(_ a: Double) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosP - ry * sin(a) * sinP, y: cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
        }
        func derivative(_ a: Double) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosP - ry * cos(a) * sinP, y: -rx * sin(a) * sinP + ry * cos(a) * cosP)
        }
        var a = theta1
        for i in 0..<segments {
            let b = a + step
            let pa = point(a), pb = i == segments - 1 ? p1 : point(b)
            let da = derivative(a), db = derivative(b)
            path.addCurve(
                to: pb, control1: CGPoint(x: pa.x + t * da.x, y: pa.y + t * da.y), control2: CGPoint(x: pb.x - t * db.x, y: pb.y - t * db.y))
            a = b
        }
    }

    private struct Scanner {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        var peek: UInt8? { i < b.count ? b[i] : nil }

        static func isCommand(_ c: UInt8) -> Bool { "MmLlHhVvCcSsQqTtAaZz".utf8.contains(c) }

        mutating func skipSeparators() {
            while let c = peek, c == 32 || c == 44 || c == 9 || c == 10 || c == 13 { i += 1 }
        }

        /// Arc flags are a single 0/1 that may touch the next number ("01-.104").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard let c = peek, c == 48 || c == 49 else { return nil }
            i += 1
            return c == 49
        }

        /// One number; a second "." or a sign starts the next one ("1.5.5", ".08-.23").
        mutating func number() -> Double? {
            skipSeparators()
            let from = i
            if let c = peek, c == 43 || c == 45 { i += 1 }
            var dot = false, exp = false, digits = false
            while let c = peek {
                if c >= 48 && c <= 57 {
                    digits = true
                } else if c == 46 && !dot && !exp {
                    dot = true
                } else if (c == 101 || c == 69) && digits && !exp {
                    exp = true
                    if i + 1 < b.count, b[i + 1] == 43 || b[i + 1] == 45 { i += 1 }
                } else {
                    break
                }
                i += 1
            }
            guard digits, let s = String(bytes: b[from..<i], encoding: .ascii) else {
                i = from
                return nil
            }
            return Double(s)
        }
    }
}
