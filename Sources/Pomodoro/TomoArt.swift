import SwiftUI
import PomodoroCore

/// Everything the drawing needs for one frame. Built by the app model, or by hand in `--sheet`.
struct TomoScene: Equatable {
    enum Mode: String, CaseIterable {
        case idle, focus, nudge, hmmph, simmer, boil, siren, splash, breathe, rest, entrance, ready, paused, celebrate, dayDone
    }
    enum Reaction: Equatable { case none, hop, wobble, puff, stretch }
    var mode: Mode = .idle
    var progress: Double = 0     // through focus or break, 0...1
    var phaseT: Double = 9       // seconds since a timed mode began (splash, rest grow-in, entrance, celebrate)
    var app: String?
    var harvested = 0
    var hold: Double = 0         // press-and-hold ring, 0...1
    var dark = false
    var look = CGVector.zero     // where the eyes look, each axis -1...1
    var react: Reaction = .none
    var reactT: Double = 9       // seconds since the reaction began
    var reduceMotion = false     // macOS Reduce Motion: crossfades instead of hops
    var harvestFraction: Double? // tomatoes in the crate by active minutes (2.67 = two full, one two-thirds)
    var breathing = "cyclic"     // cyclic sighing (default) or box
    var update = false           // a newer version is out: a seed packet with a sprout beside Tomo
}

extension Color {
    init(hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255, opacity: a)
    }
}

/// Tomo, drawn entirely in code. Face rules (DESIGN.md section 2): the resting face is built from the baby schema,
/// big round eyes set low with two catchlights, no brows, a small soft smile, cheeks under and outside the eyes.
/// Stern features (lowered brows, lids) appear only in hmmph, simmer and boil.
enum TomoArt {
    static let size = CGSize(width: 200, height: 236)
    static let splashLength = 1.9, entranceLength = 1.45, celebrateLength = 4.2, growInLength = 0.55
    static let home = CGPoint(x: 100, y: 104), radius: CGFloat = 60

    enum Face { case idle, focus, nudge, happy, sleep, hmmph, simmer, boil }

    static let red = Gradient(colors: [Color(hex: 0xFF7A63), Color(hex: 0xE8392B), Color(hex: 0xB3201B)])
    static let hot = Gradient(colors: [Color(hex: 0xFF5A4A), Color(hex: 0xD31E1E), Color(hex: 0x8E0F12)])
    static let flesh = Color(hex: 0xFFA595), seed = Color(hex: 0xFFE08A), ink = Color(hex: 0x3A1512)
    static let leafG = Gradient(colors: [Color(hex: 0x7BCB5E), Color(hex: 0x2E8B3E)])

    static func draw(_ ctx: inout GraphicsContext, _ s: TomoScene, _ t: Double) {
        let c = home, r = radius
        var g = ctx
        if s.mode == .paused { g.addFilter(.saturation(0.7)); g.opacity = 0.85 }
        switch s.mode {
        case .rest: plant(&g, s.progress, t, growIn: s.reduceMotion ? 1 : min(1, s.phaseT / growInLength))
        case .splash: splash(&g, c, r, s, t)
        case .entrance: entrance(&g, s, t)
        case .celebrate: celebrate(&g, s, t)
        case .breathe: breathe(&g, s, t)
        default: character(&g, s, t)
        }
        crate(&g, s.harvestFraction ?? Double(s.harvested), newest: s.mode == .splash ? s.phaseT : nil, glow: s.mode == .dayDone || s.mode == .celebrate,
              wave: s.mode == .celebrate ? s.phaseT : nil, dark: s.dark, t: t)
        if s.update { sprout(&g, t, dark: s.dark) }
        if s.hold > 0 {
            var ring = Path(); ring.addArc(center: c, radius: r * 1.32, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * s.hold), clockwise: false)
            g.stroke(ring, with: .color(Color(hex: 0xFF7A4D)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }

    /// The everyday Tomo: breathing, blinking, glancing, plus any squash-and-stretch reaction.
    static func character(_ g: inout GraphicsContext, _ s: TomoScene, _ t: Double) {
        let c = home, r = radius
        let face: Face = switch s.mode {
        case .focus: .focus
        case .nudge: .nudge
        case .hmmph: .hmmph
        case .simmer: .simmer
        case .boil, .siren: .boil
        case .ready, .dayDone: .happy
        case .paused: .sleep
        default: .idle
        }
        var m = motion(s, t)
        if s.mode == .ready && !s.reduceMotion { m.dy -= abs(sin(t * 2.6)) * 6 }
        if s.mode == .boil { m.dx += sin(t * 47) * 1.6; m.rot += sin(t * 31) * 0.02 }
        if s.mode == .siren && !s.reduceMotion { m.dy -= abs(sin(t * 6)) * 8; m.rot += sin(t * 12) * 0.06 }
        if s.mode == .siren { beams(&g, c, r, t) }
        if s.mode == .simmer { m.dx += sin(t * 23) * 0.6 }
        let n = [.focus, .nudge, .paused, .hmmph, .simmer, .boil, .siren].contains(s.mode) ? s.progress * Double(bites) : 0
        shadow(&g, CGPoint(x: c.x, y: c.y + r * 0.98), r * (1 - min(0.25, -m.dy / 40)))
        if s.mode == .ready { pulse(&g, c, r, t) }
        if s.mode == .boil || s.mode == .simmer { steam(&g, c, r, t, strong: s.mode == .boil) }
        var body = g
        body.translateBy(x: m.dx, y: m.dy)
        tomo(&body, c, r, face: face, eaten: n, t: t, sx: m.sx, sy: m.sy, rot: m.rot, look: s.look,
             stemTilt: s.mode == .paused ? 0.9 : 0, spin: s.mode == .dayDone ? sin(t * 1.4) * 0.5 : 0,
             heat: s.mode == .boil || s.mode == .siren ? 1 : s.mode == .simmer ? 0.5 : s.mode == .hmmph ? 0.15 : 0,
             rattle: s.mode == .boil ? abs(sin(t * 26)) * 3 : 0)
        if s.mode == .siren { var top = g; top.translateBy(x: m.dx, y: m.dy); beacon(&top, CGPoint(x: c.x, y: c.y - r * 1.12), t) }
        if s.mode == .paused { zzz(&g, c, r, t) }
        if s.mode == .dayDone { sparkles(&g, c, r, t) }
    }

    // MARK: motion (Thomas and Johnston: squash and stretch, anticipation, slow in and slow out)

    struct Motion { var dx: CGFloat = 0, dy: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, rot: Double = 0 }

    static func motion(_ s: TomoScene, _ t: Double) -> Motion {
        // Breathing: a slow 4-second cycle, volume kept (wider when shorter) so it reads as soft, not rubbery.
        let b = 1 + 0.016 * sin(t * 2 * .pi / 4)
        var m = Motion(dy: -1.2 * sin(t * 2 * .pi / 4), sx: 1 / b, sy: b)
        if s.mode == .hmmph { m.sx *= 1.05; m.sy *= 1.04 }          // stays puffed up while sulking
        guard !s.reduceMotion else { return m }
        let k = s.reactT
        switch s.react {
        case .hop where k < 0.75:
            // anticipation squash, stretch up, land squash, overshoot, settle
            let (sx, sy, y): (Double, Double, Double) =
                k < 0.12 ? lerp3((1, 1, 0), (1.12, 0.86, 0), ease(k / 0.12)) :
                k < 0.42 ? lerp3((1.12, 0.86, 0), (0.92, 1.1, -16), easeOut((k - 0.12) / 0.3)) :
                k < 0.52 ? lerp3((0.92, 1.1, -16), (1.14, 0.84, 0), easeIn((k - 0.42) / 0.1)) :
                lerp3((1.14, 0.84, 0), (1, 1, 0), easeOutBack((k - 0.52) / 0.23))
            m.sx *= sx; m.sy *= sy; m.dy += y
        case .wobble where k < 0.7:
            m.rot += sin(k * 28) * 0.13 * (1 - k / 0.7)
        case .puff where k < 0.45:
            let p = sin(min(1, k / 0.45) * .pi)
            m.sx *= 1 + 0.06 * p; m.sy *= 1 + 0.07 * p
        case .stretch where k < 1.4:
            let p = sin(min(1, k / 1.4) * .pi)
            m.sx *= 1 - 0.05 * p; m.sy *= 1 + 0.07 * p; m.rot += 0.04 * sin(k * 4) * p
        default: break
        }
        return m
    }

    static func lerp3(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ k: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k, a.2 + (b.2 - a.2) * k)
    }
    static func ease(_ x: Double) -> Double { let x = min(1, max(0, x)); return x * x * (3 - 2 * x) }
    static func easeOut(_ x: Double) -> Double { let x = min(1, max(0, x)); return 1 - pow(1 - x, 3) }
    static func easeIn(_ x: Double) -> Double { let x = min(1, max(0, x)); return x * x * x }
    static func easeOutBack(_ x: Double) -> Double {
        let x = min(1, max(0, x)), c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    // MARK: the tomato

    static func bodyPath(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for i in 0...120 {
            let a = Double(i) / 120 * 2 * .pi
            let fromTop = atan2(sin(a + .pi / 2), cos(a + .pi / 2))
            // ribs strongest on the shoulders, fading towards the bottom; a dip where the stem sits
            let shoulder = 0.35 + 0.65 * max(0, cos(fromTop * 0.9))
            let k = 1 + 0.032 * shoulder * cos(6 * fromTop) - 0.1 * exp(-pow(fromTop / 0.28, 2)) - 0.025 * exp(-pow((abs(fromTop) - .pi) / 0.5, 2))
            let pt = CGPoint(x: c.x + r * 1.12 * k * cos(a), y: c.y + r * 0.9 * k * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    /// Eaten the way people eat a tomato, by active minutes: the first bite on the upper right, each next bite
    /// beside the last, working down the right side, across the bottom and up the left, so by the end only the
    /// top with the leaves is left. Bites overlap by half, keeping the edge a row of soft tooth marks.
    static let bites = 12
    static func bite(_ i: Int, _ c: CGPoint, _ r: CGFloat) -> (center: CGPoint, radius: CGFloat) {
        let a = (-48 + Double(i) * 24.0) * .pi / 180            // -48° (upper right) round to 216° (upper left)
        let d = 1.12 - 0.11 * Double(i) / Double(bites - 1)       // later bites reach deeper
        return (CGPoint(x: c.x + r * 1.12 * d * cos(a), y: c.y + r * 0.9 * d * sin(a)), r * (0.32 + 0.1 * Double(i) / Double(bites - 1)))
    }

    /// As the bottom goes, the face rides up so it always sits on what is left.
    static func faceLift(_ eaten: Double, _ r: CGFloat) -> CGFloat { -r * 0.3 * CGFloat(max(0, (eaten - 4) / Double(bites - 4))) }

    /// A bite edge: a smooth arc with three faint tooth marks, soft rather than spiky.
    static func nibble(_ c: CGPoint, _ rb: CGFloat, _ seed: Double) -> Path {
        var p = Path()
        for i in 0...60 {
            let a = Double(i) / 60 * 2 * .pi
            let k = rb * (1 + 0.03 * abs(sin(4 * a + seed)))   // tooth marks
            let pt = CGPoint(x: c.x + k * cos(a), y: c.y + k * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    static func tomo(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, face: Face, eaten: Double, t: Double,
                     sx: CGFloat = 1, sy: CGFloat = 1, rot: Double = 0, look: CGVector = .zero, stemTilt: Double = 0, spin: Double = 0,
                     heat: Double = 0, rattle: CGFloat = 0, eyesClosed: Bool = false) {
        var g = ctx
        // Squash, stretch and tilt around the bottom so Tomo stays planted on the ground.
        let foot = CGPoint(x: c.x, y: c.y + r * 0.88)
        g.translateBy(x: foot.x, y: foot.y); g.rotate(by: .radians(rot)); g.scaleBy(x: sx, y: sy); g.translateBy(x: -foot.x, y: -foot.y)
        let body = bodyPath(c, r)
        let whole = Int(eaten), partial = eaten - Double(whole)
        // a bite lands at the end of each 5-minute block with a quick chomp (first 1.5% of the next block)
        let chomp = eaten >= Double(bites) ? 1 : min(1, partial / 0.015)
        let cuts: [(i: Int, center: CGPoint, rb: CGFloat)] = (0..<min(bites, whole)).map { i in
            let b = bite(i, c, r), grow = i < whole - 1 ? 1 : chomp
            return (i, b.center, b.radius * (0.5 + 0.5 * grow))
        }
        g.drawLayer { l in
            l.fill(body, with: .radialGradient(red, center: CGPoint(x: c.x - r * 0.4, y: c.y - r * 0.45), startRadius: 0, endRadius: r * 1.9))
            if heat > 0 {
                l.fill(body, with: .radialGradient(hot, center: CGPoint(x: c.x, y: c.y - r * 0.2), startRadius: 0, endRadius: r * 1.6))
                l.opacity = 1
            }
            l.drawLayer { f in
                f.clip(to: body)
                if heat > 0 { f.fill(body, with: .color(Color(hex: 0x8E0F12, 0.35 * heat))) }
                // Realism from light, not lines (DESIGN.md section 2).
                // Translucent skin: light scatters inside, so the edges glow warmer than the middle.
                f.fill(body, with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.62), .init(color: Color(hex: 0xFF6A3A, 0.28), location: 0.9), .init(color: Color(hex: 0xFF8A55, 0.12), location: 1)]),
                       center: CGPoint(x: c.x - r * 0.1, y: c.y - r * 0.05), startRadius: 0, endRadius: r * 1.15))
                // Shoulders round the stem stay a touch orange on a vine-ripened tomato.
                f.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.75, y: c.y - r * 1.05, width: r * 1.5, height: r * 0.75)),
                       with: .radialGradient(Gradient(colors: [Color(hex: 0xFF9A4D, 0.3), .clear]), center: CGPoint(x: c.x, y: c.y - r * 0.82), startRadius: 0, endRadius: r * 0.75))
                // Lobes by shading: soft shadowed valleys between the shoulders and lit crowns between them.
                for (k, a) in [-0.95, -0.42, 0.42, 0.95].enumerated() {
                    let from = CGPoint(x: c.x + r * 0.1 * a, y: c.y - r * 0.76), to = CGPoint(x: c.x + r * 0.78 * a, y: c.y - r * 0.18)
                    let len = hypot(to.x - from.x, to.y - from.y)
                    var v = f
                    v.translateBy(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2); v.rotate(by: .radians(atan2(to.y - from.y, to.x - from.x)))
                    let band = Path(ellipseIn: CGRect(x: -len / 2, y: -r * 0.09, width: len, height: r * 0.18))
                    v.fill(band, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: Color(hex: 0x8E1410, 0.16), location: 0.5), .init(color: .clear, location: 1)]),
                                                     startPoint: CGPoint(x: 0, y: -r * 0.09), endPoint: CGPoint(x: 0, y: r * 0.09)))
                    v.translateBy(x: 0, y: (k < 2 ? 1 : -1) * r * 0.13)
                    v.fill(band, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.07), location: 0.5), .init(color: .clear, location: 1)]),
                                                     startPoint: CGPoint(x: 0, y: -r * 0.09), endPoint: CGPoint(x: 0, y: r * 0.09)))
                }
                // Contact shadow on the underside.
                f.fill(body, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0.55), .init(color: Color(hex: 0x5A0A08, 0.28), location: 1)]),
                       startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r * 0.9)))
                // Fine skin speckle, barely there.
                for i in 0..<34 {
                    let u = abs(sin(Double(i) * 12.9898)), v = abs(sin(Double(i) * 78.233))
                    let p = CGPoint(x: c.x + r * (u * 2 - 1) * 0.95, y: c.y + r * (v * 2 - 1) * 0.8)
                    f.fill(Path(ellipseIn: CGRect(x: p.x - 0.6, y: p.y - 0.6, width: 1.2, height: 1.2)), with: .color(Color(hex: 0xFFE2B0, 0.18)))
                }
                // Gloss: a broad soft sheen with a small, sharp window highlight inside it, like light on wet skin.
                var sheen = f
                sheen.translateBy(x: c.x - r * 0.5, y: c.y - r * 0.5); sheen.rotate(by: .radians(-0.55))
                sheen.fill(Path(ellipseIn: CGRect(x: -r * 0.3, y: -r * 0.16, width: r * 0.6, height: r * 0.32)),
                           with: .radialGradient(Gradient(colors: [.white.opacity(0.32), .clear]), center: .zero, startRadius: 0, endRadius: r * 0.3))
                sheen.fill(Path(roundedRect: CGRect(x: -r * 0.15, y: -r * 0.07, width: r * 0.27, height: r * 0.11), cornerRadius: r * 0.05), with: .color(.white.opacity(0.75)))
                f.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.25, y: c.y - r * 0.74, width: r * 0.07, height: r * 0.05)), with: .color(.white.opacity(0.55)))
                // A faint bounce light from below on the lower right.
                f.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.2, y: c.y + r * 0.45, width: r * 0.7, height: r * 0.35)),
                       with: .radialGradient(Gradient(colors: [Color(hex: 0xFF9E80, 0.18), .clear]), center: CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.62), startRadius: 0, endRadius: r * 0.35))
                if heat >= 1 {
                    // boiling: little bubbles rise and pop on the skin
                    for i in 0..<6 {
                        let k = (t * 1.3 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
                        let bx = c.x + r * 0.8 * sin(Double(i) * 2.4), by = c.y + r * (0.6 - 1.1 * k)
                        f.stroke(Path(ellipseIn: CGRect(x: bx - 3 * k - 1, y: by - 3 * k - 1, width: 6 * k + 2, height: 6 * k + 2)), with: .color(.white.opacity(0.45 * (1 - k))), lineWidth: 1.2)
                    }
                }
                // The cut face of a ripe tomato: a thin deep-red wall, glistening red flesh, and glossy red gel
                // pockets holding pale teardrop seeds (yellow-green gel would mean unripe).
                for b in cuts { f.fill(nibble(b.center, b.rb + r * 0.3, Double(b.i)), with: .color(Color(hex: 0xA8170F))) }
                for b in cuts {
                    f.fill(nibble(b.center, b.rb + r * 0.26, Double(b.i)), with: .radialGradient(Gradient(colors: [Color(hex: 0xF4563F), Color(hex: 0xE23A28), Color(hex: 0xC92519)]),
                           center: b.center, startRadius: b.rb, endRadius: b.rb + r * 0.26))
                }
                for b in cuts {
                    let inward = atan2(c.y + r * 0.1 - b.center.y, c.x - b.center.x)
                    for side in [-0.5, 0.5] {
                        let a = inward + side
                        let gc = CGPoint(x: b.center.x + (b.rb + r * 0.12) * cos(a), y: b.center.y + (b.rb + r * 0.12) * sin(a))
                        var gel = f
                        gel.translateBy(x: gc.x, y: gc.y); gel.rotate(by: .radians(a + .pi / 2))
                        let pocket = Path(ellipseIn: CGRect(x: -r * 0.13, y: -r * 0.085, width: r * 0.26, height: r * 0.17))
                        gel.fill(pocket, with: .radialGradient(Gradient(colors: [Color(hex: 0xFF8A6A, 0.95), Color(hex: 0xF0583F, 0.9), Color(hex: 0xD7341F, 0.8)]),
                                                           center: CGPoint(x: -r * 0.03, y: -r * 0.03), startRadius: 0, endRadius: r * 0.14))
                        for (k, dy, tilt) in [(-1.0, -0.02, 0.5), (0.0, 0.03, -0.3), (1.0, -0.015, 0.2)] {
                            var sd = gel
                            sd.translateBy(x: CGFloat(k) * r * 0.07, y: r * CGFloat(dy)); sd.rotate(by: .radians(tilt))
                            let seedShape = Path { q in
                                q.move(to: CGPoint(x: -2.6, y: 0))
                                q.addQuadCurve(to: CGPoint(x: 2.6, y: 0), control: CGPoint(x: 0, y: -2.8))
                                q.addQuadCurve(to: CGPoint(x: -2.6, y: 0), control: CGPoint(x: 0.6, y: 2.2))
                            }
                            sd.fill(seedShape, with: .color(Color(hex: 0xF2E2B4, 0.95)))
                            sd.fill(Path(ellipseIn: CGRect(x: -3.6, y: -2.6, width: 7.2, height: 5.2)), with: .color(Color(hex: 0xFFD2C2, 0.18)))   // the clear seed capsule
                        }
                        gel.fill(Path(ellipseIn: CGRect(x: -r * 0.08, y: -r * 0.065, width: r * 0.07, height: r * 0.035)), with: .color(.white.opacity(0.55)))
                    }
                }
                // Wet glints along the bite edge.
                for b in cuts {
                    let inward = atan2(c.y - b.center.y, c.x - b.center.x)
                    var glint = Path()
                    glint.addArc(center: b.center, radius: b.rb + 1.8, startAngle: .radians(inward - 0.35), endAngle: .radians(inward - 0.05), clockwise: false)
                    f.stroke(glint, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            }
            // Every 6 s a drop of juice runs down the skin from the lowest bite. Drawn before the cut,
            // so any part over the bitten-away area is removed with it.
            if let low = cuts.max(by: { $0.center.y < $1.center.y }) {
                let k = (t / 6).truncatingRemainder(dividingBy: 1)
                if k < 0.45 {
                    var d = l; d.clip(to: body); d.opacity = k < 0.35 ? 1 : 1 - (k - 0.35) / 0.1
                    let toward = atan2(c.y + r - low.center.y, c.x - r * 0.2 - low.center.x)
                    let start = CGPoint(x: low.center.x + (low.rb + 2) * cos(toward), y: low.center.y + (low.rb + 2) * sin(toward))
                    let y = start.y + CGFloat(ease(k / 0.45)) * r * 0.3, len = 4 + 5 * k
                    d.fill(Path(ellipseIn: CGRect(x: start.x - 2.6, y: y - len, width: 5.2, height: len * 1.6)), with: .color(Color(hex: 0xF0503F)))
                    d.fill(Path(ellipseIn: CGRect(x: start.x - 1.2, y: y - len * 0.6, width: 1.6, height: 2.4)), with: .color(.white.opacity(0.6)))
                }
            }
            // cut unclipped, so no fringe of the uneaten outline survives
            l.blendMode = .destinationOut
            for b in cuts { l.fill(nibble(b.center, b.rb, Double(b.i)), with: .color(.black)) }
        }
        var lid = g
        lid.translateBy(x: 0, y: -rattle)
        calyx(&lid, CGPoint(x: c.x, y: c.y - r * 0.82), r, t: t, tilt: stemTilt, spin: spin)
        var faceCtx = g
        let lift = faceLift(eaten, r)
        faceCtx.translateBy(x: -r * 0.12 * (lift / (-r * 0.3)), y: lift)
        faceCtx.scaleBy(x: 1, y: 1)
        faceDraw(&faceCtx, c, r, eyesClosed ? .sleep : face, t, look: look)
    }

    static func leaf(_ len: CGFloat, _ w: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: len, y: w * 0.25), control: CGPoint(x: len * 0.45, y: -w))
        p.addQuadCurve(to: .zero, control: CGPoint(x: len * 0.5, y: w * 1.1))
        return p
    }

    static func calyx(_ ctx: inout GraphicsContext, _ at: CGPoint, _ r: CGFloat, t: Double, tilt: Double, spin: Double) {
        var g = ctx
        g.translateBy(x: at.x, y: at.y)
        for (deg, len) in [(8.0, 0.44), (52.0, 0.34), (128.0, 0.34), (172.0, 0.44), (-90.0, 0.2)] {
            var l = g
            l.rotate(by: .degrees(deg + 4 * sin(t * 1.1 + deg)))
            l.fill(leaf(r * len, r * 0.16), with: .linearGradient(leafG, startPoint: .zero, endPoint: CGPoint(x: r * len, y: 0)))
        }
        // The stem is Tomo's cowlick and carries the mood: upright, drooping asleep, swinging on a full harvest.
        var s = g
        s.rotate(by: .radians(0.12 * sin(t * 1.3) + tilt + spin))
        var stem = Path()
        stem.move(to: .zero)
        stem.addCurve(to: CGPoint(x: r * 0.08, y: -r * 0.34), control1: CGPoint(x: -r * 0.06, y: -r * 0.14), control2: CGPoint(x: r * 0.12, y: -r * 0.2))
        stem.addQuadCurve(to: CGPoint(x: r * 0.22, y: -r * 0.32), control: CGPoint(x: r * 0.12, y: -r * 0.48))
        s.stroke(stem, with: .color(Color(hex: 0x3F8F3A)), style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: at.x - r * 0.09, y: at.y - r * 0.05, width: r * 0.18, height: r * 0.11)), with: .color(Color(hex: 0x2E7D32)))
    }

    static func starShape(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var p = Path()
        for i in 0..<10 {
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            let k = i % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: c.x + k * cos(a), y: c.y + k * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE27A), Color(hex: 0xF4A81D)]), startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
    }

    /// Blinks every 3 to 6 seconds; the gap changes each time so it never looks mechanical.
    static func blink(_ t: Double) -> Double {
        let period = 4.5
        let i = floor(t / period), start = i * period + 1.5 * sin(i * 12.9898)
        let since = t - start
        return since >= 0 && since < 0.16 ? max(0.08, abs(since - 0.08) / 0.08) : 1
    }

    static func arc(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat) -> Path {
        var p = Path(); p.move(to: CGPoint(x: c.x - w / 2, y: c.y)); p.addQuadCurve(to: CGPoint(x: c.x + w / 2, y: c.y), control: CGPoint(x: c.x, y: c.y + h)); return p
    }

    // MARK: face

    static func faceDraw(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ face: Face, _ t: Double, look: CGVector) {
        // Baby schema: eyes big, round, set low and a little apart.
        let ew = r * 0.26, eh = r * 0.31
        let eyeY = c.y + r * 0.06
        let lx = r * 0.05 * look.dx, ly = r * 0.04 * look.dy
        let eyes = [CGPoint(x: c.x - r * 0.33 + lx, y: eyeY + ly), CGPoint(x: c.x + r * 0.33 + lx, y: eyeY + ly)]
        let line = StrokeStyle(lineWidth: r * 0.05, lineCap: .round, lineJoin: .round)
        let cheekBoost: CGFloat = face == .hmmph ? 1.35 : face == .boil ? 0.6 : 1
        for (i, e) in eyes.enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            let cheek = CGRect(x: c.x + side * r * 0.52 - r * 0.11 * cheekBoost, y: eyeY + r * 0.22, width: r * 0.22 * cheekBoost, height: r * 0.13 * cheekBoost)
            ctx.fill(Path(ellipseIn: cheek), with: .color(Color(hex: 0xFF8FA6, face == .hmmph ? 0.75 : 0.55)))
            switch face {
            case .happy:
                ctx.stroke(arc(CGPoint(x: e.x, y: e.y + r * 0.04), ew * 1.05, -eh * 0.85), with: .color(ink), style: line)
            case .sleep:
                ctx.stroke(arc(CGPoint(x: e.x, y: e.y), ew * 1.0, eh * 0.45), with: .color(ink), style: line)
            case .boil:
                // squeezed shut "> <": comic fury, not menace
                var p = Path()
                p.move(to: CGPoint(x: e.x - side * ew * 0.5, y: e.y - eh * 0.35))
                p.addLine(to: CGPoint(x: e.x + side * ew * 0.45, y: e.y))
                p.addLine(to: CGPoint(x: e.x - side * ew * 0.5, y: e.y + eh * 0.35))
                ctx.stroke(p, with: .color(ink), style: line)
            default:
                var k = blink(t)
                if face == .focus { k *= 0.92 }
                var eye = ctx
                if face == .hmmph || face == .simmer {
                    // a flat, tilted lid: the side-eye of someone not impressed
                    let lid = face == .hmmph ? 0.18 : 0.1
                    var clip = Path()
                    clip.move(to: CGPoint(x: e.x - ew, y: e.y - eh * lid + side * eh * 0.12))
                    clip.addLine(to: CGPoint(x: e.x + ew, y: e.y - eh * lid - side * eh * 0.12))
                    clip.addLine(to: CGPoint(x: e.x + ew, y: e.y + eh)); clip.addLine(to: CGPoint(x: e.x - ew, y: e.y + eh)); clip.closeSubpath()
                    eye.clip(to: clip)
                }
                let rect = CGRect(x: e.x - ew / 2, y: e.y - eh / 2 * k, width: ew, height: eh * k)
                eye.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [ink, Color(hex: 0x6A2A22)]), startPoint: CGPoint(x: e.x, y: rect.minY), endPoint: CGPoint(x: e.x, y: rect.maxY)))
                if k > 0.5 {
                    // two catchlights: the sparkle that makes the eyes read as alive
                    eye.fill(Path(ellipseIn: CGRect(x: e.x - ew * 0.34, y: e.y - eh * 0.36, width: ew * 0.46, height: ew * 0.46)), with: .color(.white))
                    eye.fill(Path(ellipseIn: CGRect(x: e.x + ew * 0.1, y: e.y + eh * 0.12, width: ew * 0.2, height: ew * 0.2)), with: .color(.white.opacity(0.85)))
                }
                if face == .nudge {
                    // soft raised brows: "hm?"
                    ctx.stroke(arc(CGPoint(x: e.x, y: e.y - eh * 0.85), ew * 0.9, -r * 0.06), with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: r * 0.035, lineCap: .round))
                }
                if face == .simmer {
                    let drop: CGFloat = 0.16
                    // inner end lower than the outer end: cross, not sad
                    var brow = Path()
                    brow.move(to: CGPoint(x: e.x - side * ew * 0.7, y: e.y - eh * 0.62 + r * drop * 0.5))
                    brow.addLine(to: CGPoint(x: e.x + side * ew * 0.6, y: e.y - eh * 0.85))
                    ctx.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.045, lineCap: .round))
                }
            }
            if face == .boil {
                var brow = Path()
                brow.move(to: CGPoint(x: e.x - side * ew * 0.75, y: e.y - eh * 0.45))
                brow.addLine(to: CGPoint(x: e.x + side * ew * 0.65, y: e.y - eh * 0.9))
                ctx.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
            }
        }
        let m = CGPoint(x: c.x + lx * 0.5, y: eyeY + r * 0.3)
        switch face {
        case .idle:
            ctx.stroke(arc(m, r * 0.13, r * 0.07), with: .color(ink), style: line)
        case .focus:
            ctx.stroke(arc(m, r * 0.1, r * 0.045), with: .color(ink), style: line)
        case .nudge, .sleep:
            let w = face == .nudge ? r * 0.075 : r * 0.05
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - w / 2, y: m.y - w * 0.3, width: w, height: w * 1.1)), with: .color(ink))
        case .hmmph:
            // a pout pushed to one side
            var p = Path(); p.move(to: CGPoint(x: m.x - r * 0.02, y: m.y + r * 0.02))
            p.addQuadCurve(to: CGPoint(x: m.x + r * 0.1, y: m.y + r * 0.01), control: CGPoint(x: m.x + r * 0.04, y: m.y - r * 0.04))
            ctx.stroke(p, with: .color(ink), style: line)
        case .simmer:
            var p = Path(); p.move(to: CGPoint(x: m.x - r * 0.09, y: m.y + r * 0.02))
            for i in 1...4 { p.addLine(to: CGPoint(x: m.x - r * 0.09 + r * 0.045 * CGFloat(i), y: m.y + (i % 2 == 0 ? r * 0.02 : -r * 0.01))) }
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: r * 0.04, lineCap: .round, lineJoin: .round))
        case .boil, .happy:
            let w = face == .boil ? r * 0.2 : r * 0.24, h = face == .boil ? r * 0.2 : r * 0.2
            var p = Path(); p.move(to: CGPoint(x: m.x - w / 2, y: m.y - r * 0.02))
            p.addQuadCurve(to: CGPoint(x: m.x + w / 2, y: m.y - r * 0.02), control: CGPoint(x: m.x, y: m.y + h * (face == .boil ? 0.6 : 1.25)))
            if face == .boil { p.addQuadCurve(to: CGPoint(x: m.x - w / 2, y: m.y - r * 0.02), control: CGPoint(x: m.x, y: m.y - h * 0.5)) }
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))
            var tongue = ctx; tongue.clip(to: p)
            tongue.fill(Path(ellipseIn: CGRect(x: m.x - r * 0.07, y: m.y + r * 0.06, width: r * 0.14, height: r * 0.12)), with: .color(Color(hex: 0xFF6F8A)))
        }
    }

    static func shadow(_ ctx: inout GraphicsContext, _ at: CGPoint, _ w: CGFloat) {
        // A radial gradient squashed flat, not a blur: a blur re-runs every frame and cost ~2% CPU.
        var g = ctx
        g.translateBy(x: at.x, y: at.y); g.scaleBy(x: 1, y: 0.14)
        g.fill(Path(ellipseIn: CGRect(x: -w, y: -w, width: w * 2, height: w * 2)),
               with: .radialGradient(Gradient(colors: [.black.opacity(0.26), .black.opacity(0.1), .clear]), center: .zero, startRadius: 0, endRadius: w))
    }

    static func pulse(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ t: Double) {
        let k = (t / 1.6).truncatingRemainder(dividingBy: 1)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * (1.05 + 0.35 * k), y: c.y - r * (0.97 + 0.35 * k), width: r * (2.1 + 0.7 * k), height: r * (1.94 + 0.7 * k))),
                   with: .color(Color(hex: 0xFF7A4D, 0.5 * (1 - k))), lineWidth: 3)
    }

    static func zzz(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ t: Double) {
        for i in 0..<3 {
            let k = ((t / 3) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var g = ctx; g.opacity = sin(k * .pi)
            g.draw(Text("z").font(.system(size: 13 + 7 * k, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: 0x8FA3C7)),
                   at: CGPoint(x: c.x + r * (0.75 + 0.35 * k), y: c.y - r * (0.55 + 0.7 * k)))
        }
    }

    static func sparkles(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ t: Double) {
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + t * 0.3
            starShape(&ctx, CGPoint(x: c.x + r * 1.35 * cos(a), y: c.y + r * 1.15 * sin(a)), 3 + 4 * (0.5 + 0.5 * sin(t * 2.2 + Double(i) * 1.7)))
        }
    }

    /// Siren: a red and blue beacon sits on the stem and alternates every 0.35 s.
    static func sirenRed(_ t: Double) -> Bool { Int(t / 0.35) % 2 == 0 }

    static func beacon(_ ctx: inout GraphicsContext, _ at: CGPoint, _ t: Double) {
        let red = sirenRed(t)
        let dome = Path { p in
            p.move(to: CGPoint(x: at.x - 13, y: at.y + 2))
            p.addCurve(to: CGPoint(x: at.x + 13, y: at.y + 2), control1: CGPoint(x: at.x - 13, y: at.y - 22), control2: CGPoint(x: at.x + 13, y: at.y - 22))
            p.closeSubpath()
        }
        var halo = ctx; halo.opacity = 0.55
        halo.fill(Path(ellipseIn: CGRect(x: at.x - 26, y: at.y - 32, width: 52, height: 44)),
                  with: .radialGradient(Gradient(colors: [Color(hex: red ? 0xFF3B30 : 0x3B82FF), .clear]), center: CGPoint(x: at.x, y: at.y - 9), startRadius: 0, endRadius: 26))
        var left = ctx; left.clip(to: Path(CGRect(x: at.x - 14, y: at.y - 24, width: 14, height: 28)))
        left.fill(dome, with: .color(Color(hex: red ? 0xFF3B30 : 0x7A1A16)))
        var right = ctx; right.clip(to: Path(CGRect(x: at.x, y: at.y - 24, width: 14, height: 28)))
        right.fill(dome, with: .color(Color(hex: red ? 0x1B2E6B : 0x3B82FF)))
        ctx.fill(Path(ellipseIn: CGRect(x: at.x - 7, y: at.y - 15, width: 5, height: 4)), with: .color(.white.opacity(0.7)))
        ctx.fill(Path(roundedRect: CGRect(x: at.x - 16, y: at.y + 1, width: 32, height: 6), cornerRadius: 2), with: .color(Color(hex: 0x3A3A40)))
    }

    /// Two light beams sweeping round from the beacon, coloured with whichever side is lit.
    static func beams(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ t: Double) {
        let at = CGPoint(x: c.x, y: c.y - r * 1.2)
        for k in 0..<2 {
            let a = t * 5 + Double(k) * .pi
            var beam = Path(); beam.move(to: at)
            beam.addLine(to: CGPoint(x: at.x + 160 * cos(a - 0.22), y: at.y + 160 * sin(a - 0.22)))
            beam.addLine(to: CGPoint(x: at.x + 160 * cos(a + 0.22), y: at.y + 160 * sin(a + 0.22)))
            beam.closeSubpath()
            var g = ctx; g.opacity = 0.22
            g.fill(beam, with: .radialGradient(Gradient(colors: [Color(hex: k == 0 ? 0xFF3B30 : 0x3B82FF), .clear]), center: at, startRadius: 0, endRadius: 160))
        }
    }

    /// Simmer: two thin wisps. Boil: puffs of steam rolling off both sides, rising and fading.
    static func steam(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ t: Double, strong: Bool) {
        let n = strong ? 7 : 2
        for i in 0..<n {
            let k = (t * (strong ? 0.9 : 0.5) + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
            let side: Double = i % 2 == 0 ? -1 : 1
            let x = c.x + side * r * (0.25 + 0.35 * k) + 6 * sin(k * 9 + Double(i))
            let y = c.y - r * (0.85 + 1.0 * k)
            var g = ctx; g.opacity = sin(k * .pi) * (strong ? 0.85 : 0.6)
            if strong {
                let s = 7 + 12 * k
                for (dx, dy, f) in [(0.0, 0.0, 1.0), (s * 0.6, s * 0.2, 0.75), (-s * 0.55, s * 0.25, 0.7)] {
                    g.fill(Path(ellipseIn: CGRect(x: x + dx - s * f, y: y + dy - s * f * 0.8, width: s * 2 * f, height: s * 1.6 * f)), with: .color(Color(hex: 0xC9C2BC)))
                    g.fill(Path(ellipseIn: CGRect(x: x - s * 0.8, y: y - s * 0.75, width: s * 1.6, height: s * 1.3)), with: .color(Color(hex: 0xF4F1EE)))
                }
            } else {
                var p = Path(); p.move(to: CGPoint(x: x, y: y + 14))
                p.addCurve(to: CGPoint(x: x, y: y - 14), control1: CGPoint(x: x + 8, y: y + 4), control2: CGPoint(x: x - 8, y: y - 4))
                g.stroke(p, with: .color(Color(hex: 0xBDB5AE)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    // MARK: end of focus: the juice splash

    struct Drop { let angle: Double, speed: Double, size: Double, seed: Bool }
    static let drops: [Drop] = (0..<26).map { i in
        let u = abs(sin(Double(i) * 78.233)), v = abs(sin(Double(i) * 12.9898 + 4.1))
        return Drop(angle: -.pi + 0.15 + u * (.pi - 0.3), speed: 150 + 190 * v, size: 3 + 6 * abs(sin(Double(i) * 3.7)), seed: i % 5 == 0)
    }

    static func splash(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ s: TomoScene, _ t: Double) {
        let st = s.phaseT, ground = c.y + r * 0.96
        if st < 0.24 {
            let e = pow(st / 0.24, 2)
            shadow(&ctx, CGPoint(x: c.x, y: ground + 4), r * (1 + 0.3 * e))
            tomo(&ctx, c, r, face: .happy, eaten: Double(bites), t: t, sx: 1 + 0.38 * e, sy: 1 - 0.42 * e)
            return
        }
        let k = st - 0.24
        let fade = max(0, 1 - k / 1.25)
        var splat = Path()
        for i in 0...60 {
            let a = Double(i) / 60 * 2 * .pi
            let rr = r * (0.7 + 0.5 * min(1, k / 0.18)) * (1 + 0.14 * sin(9 * a) + 0.08 * sin(4 * a + 1))
            let pt = CGPoint(x: c.x + rr * 1.3 * cos(a), y: ground - r * 0.08 + rr * 0.32 * sin(a))
            i == 0 ? splat.move(to: pt) : splat.addLine(to: pt)
        }
        var g = ctx; g.opacity = fade
        g.fill(splat, with: .radialGradient(red, center: CGPoint(x: c.x, y: ground - r * 0.1), startRadius: 0, endRadius: r * 1.3))
        let w = min(1, k / 0.5)
        g.stroke(Path(ellipseIn: CGRect(x: c.x - r * (0.6 + 1.0 * w), y: ground - r * 0.1 - r * (0.3 + 0.45 * w), width: r * (1.2 + 2.0 * w), height: r * (0.6 + 0.9 * w))),
                 with: .color(Color(hex: 0xFF6F61, 0.7 * (1 - w))), lineWidth: 4 * (1 - w) + 0.5)
        for d in drops {
            let vx = d.speed * cos(d.angle), vy = d.speed * sin(d.angle)
            let x = c.x + vx * k, y = ground - r * 0.25 + vy * k + 0.5 * 720 * k * k
            let dy = vy + 720 * k
            var drop = g
            drop.translateBy(x: x, y: y); drop.rotate(by: .radians(atan2(dy, vx)))
            let len = d.size * (1 + min(2.2, hypot(vx, dy) / 160))
            drop.fill(Path(ellipseIn: CGRect(x: -len / 2, y: -d.size / 2, width: len, height: d.size)), with: .color(d.seed ? seed : Color(hex: d.size > 6 ? 0xE8392B : 0xFF6F61)))
        }
        if k > 0.55 {
            var plus = ctx; plus.opacity = max(0, 1 - (k - 0.55) / 1.1)
            plus.draw(Text("+1").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: 0xFF5A47)), at: CGPoint(x: c.x, y: c.y - r * 0.4 - 18 * (k - 0.55)))
        }
    }

    // MARK: a new version is ripe: a seed packet beside Tomo with a sprout that sways

    static func sprout(_ ctx: inout GraphicsContext, _ t: Double, dark: Bool) {
        let base = CGPoint(x: 22, y: 168)
        var g = ctx
        g.addFilter(.shadow(color: .black.opacity(0.18), radius: 2, y: 1.5))
        // the packet, a little tilted, with a tomato on its label
        var p = g; p.translateBy(x: base.x, y: base.y); p.rotate(by: .degrees(-6))
        let packet = Path(roundedRect: CGRect(x: -14, y: -34, width: 28, height: 34), cornerRadius: 3)
        p.fill(packet, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFF3DC), Color(hex: 0xF1D9B0)]), startPoint: CGPoint(x: 0, y: -34), endPoint: .zero))
        p.stroke(Path { q in q.move(to: CGPoint(x: -14, y: -27)); q.addLine(to: CGPoint(x: 14, y: -27)) }, with: .color(Color(hex: 0xC8372B, 0.7)), lineWidth: 1.2)
        p.fill(Path(ellipseIn: CGRect(x: -7, y: -21, width: 14, height: 13)), with: .radialGradient(red, center: CGPoint(x: -2, y: -18), startRadius: 0, endRadius: 12))
        p.fill(Path(ellipseIn: CGRect(x: -2, y: -23, width: 4, height: 3)), with: .color(Color(hex: 0x3F8F3A)))
        // the sprout out of the top, swaying
        let sway = 0.12 * sin(t * 1.6)
        var s = g; s.translateBy(x: base.x + 2, y: base.y - 34); s.rotate(by: .radians(sway))
        var stem = Path(); stem.move(to: .zero); stem.addQuadCurve(to: CGPoint(x: 1, y: -16), control: CGPoint(x: -3, y: -8))
        s.stroke(stem, with: .color(Color(hex: 0x3F8F3A)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for (dx, deg) in [(-1.0, 200.0), (2.0, -20.0)] {
            var l = s; l.translateBy(x: dx, y: -15); l.rotate(by: .degrees(deg))
            var leaf = Path(); leaf.move(to: .zero); leaf.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: -5)); leaf.addQuadCurve(to: .zero, control: CGPoint(x: 5, y: 4))
            l.fill(leaf, with: .linearGradient(leafG, startPoint: .zero, endPoint: CGPoint(x: 10, y: 0)))
        }
        // a small "new" tag
        ctx.fill(Path(roundedRect: CGRect(x: base.x + 3, y: base.y - 8, width: 20, height: 12), cornerRadius: 6), with: .color(Color(hex: 0xC8372B)))
        ctx.draw(Text("new").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: base.x + 13, y: base.y - 2))
    }

    // MARK: break, first half: breathe with Tomo

    /// Cycle length and when the exhale starts, shared with the breath sounds.
    static func breathCycle(_ technique: String) -> (cycle: Double, outAt: Double) { technique == "box" ? (16, 8) : (6, 2.5) }

    /// 0...1 lung fullness at `t` seconds. Cyclic sighing (Balban et al. 2023): an inhale, a short top-up
    /// inhale, then a long slow exhale; 6 s a cycle, 10 breaths a minute (24 Oct: 8 s read as "too slow").
    /// Box breathing: in 4, hold 4, out 4, hold 4.
    static func breath(_ t: Double, _ technique: String) -> (fill: Double, cue: String) {
        if technique == "box" {
            let k = t.truncatingRemainder(dividingBy: 16)
            return k < 4 ? (ease(k / 4), "breathe in") : k < 8 ? (1, "hold") : k < 12 ? (1 - ease((k - 8) / 4), "breathe out") : (0, "hold")
        }
        let k = t.truncatingRemainder(dividingBy: 6)
        return k < 1.8 ? (0.8 * ease(k / 1.8), "breathe in") : k < 2.5 ? (0.8 + 0.2 * ease((k - 1.8) / 0.7), "a little more")
            : (1 - ease((k - 2.5) / 3.5), "and out, slowly")
    }

    static func breathe(_ ctx: inout GraphicsContext, _ s: TomoScene, _ t: Double) {
        let c = home, r = radius
        let (b, cue) = breath(s.phaseT, s.breathing)
        // a breath lifts the body from its base a little, more up than out, like a chest (was a 23% balloon)
        let sx = 1 + 0.04 * b, sy = 1 + 0.06 * b, k = sx
        // fade in from the splash
        var g = ctx; g.opacity = min(1, s.phaseT / 0.8)
        // a soft halo that grows with the breath
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.5 * k, y: c.y - r * 1.4 * k, width: r * 3 * k, height: r * 2.8 * k)),
               with: .radialGradient(Gradient(colors: [Color(hex: 0xFF8A6A, 0.22 * b + 0.05), .clear]), center: c, startRadius: r * 0.8, endRadius: r * 1.5 * k))
        shadow(&g, CGPoint(x: c.x, y: c.y + r * 0.98), r * k)
        var body = g
        body.translateBy(x: c.x, y: c.y + r * 0.88); body.scaleBy(x: sx, y: sy); body.translateBy(x: -c.x, y: -(c.y + r * 0.88))
        tomo(&body, c, r, face: .sleep, eaten: 0, t: t)
        g.draw(Text(cue).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Color(hex: 0xC2452F, 0.9)), at: CGPoint(x: c.x, y: 181))
    }

    // MARK: break: the next tomato regrows and ripens

    static let potBase = CGPoint(x: 100, y: 150)

    /// Where the hanging fruit sits on the vine for a given break progress, and its radius.
    static func fruit(_ p: Double, sway: Double) -> (center: CGPoint, radius: CGFloat) {
        let h = 18 + 82 * ease(min(1, p / 0.45))
        let q = min(1, max(0, (p - 0.62) / 0.38))
        let rf = 7 + 25 * ease(min(1, q / 0.6))
        // branch tip in pot space, then swayed around the soil point
        let local = CGPoint(x: 30, y: -h * 0.78 + 4 + rf * 0.9)
        let x = local.x * cos(sway) - local.y * sin(sway), y = local.x * sin(sway) + local.y * cos(sway)
        return (CGPoint(x: potBase.x + x, y: potBase.y + y), rf)
    }

    static func plant(_ ctx: inout GraphicsContext, _ p: Double, _ t: Double, growIn: Double = 1, hideFruit: Bool = false) {
        let base = potBase
        let sway = 0.05 * sin(t * 0.9)
        var whole = ctx
        if growIn < 1 {
            // the pot springs up out of the splash with a small overshoot
            let k = easeOutBack(growIn)
            whole.opacity = min(1, growIn * 2)
            whole.translateBy(x: base.x, y: 186); whole.scaleBy(x: 0.4 + 0.6 * k, y: 0.4 + 0.6 * k); whole.translateBy(x: -base.x, y: -186)
        }
        shadow(&whole, CGPoint(x: base.x, y: 186), 34)
        var g = whole
        g.translateBy(x: base.x, y: base.y); g.rotate(by: .radians(sway))
        let h = 18 + 82 * ease(min(1, p / 0.45))
        var stem = Path(); stem.move(to: .zero)
        stem.addQuadCurve(to: CGPoint(x: 4, y: -h), control: CGPoint(x: -10, y: -h * 0.5))
        g.stroke(stem, with: .color(Color(hex: 0x4E9F3D)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        for (i, (at, side)) in [(0.45, 1.0), (0.65, -1.0), (0.85, 1.0)].enumerated() {
            let grow = ease(min(1, max(0, (p - 0.1 - Double(i) * 0.12) / 0.15)))
            guard grow > 0 else { continue }
            var l = g; l.translateBy(x: -2, y: -h * at); l.rotate(by: .degrees(side > 0 ? -25 : 205)); l.scaleBy(x: grow, y: grow)
            l.fill(leaf(30, 11), with: .linearGradient(leafG, startPoint: .zero, endPoint: CGPoint(x: 30, y: 0)))
        }
        var top = g; top.translateBy(x: 4, y: -h)
        for d in [-30.0, 210.0] { var l = top; l.rotate(by: .degrees(d)); l.fill(leaf(17, 8), with: .color(Color(hex: 0x7BCB5E))) }
        let branch = CGPoint(x: 30, y: -h * 0.78)
        if p > 0.4 {
            var b = Path(); b.move(to: CGPoint(x: -1, y: -h * 0.72)); b.addQuadCurve(to: branch, control: CGPoint(x: 18, y: -h * 0.9))
            g.stroke(b, with: .color(Color(hex: 0x4E9F3D)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        let flower = p < 0.5 ? 0 : p < 0.62 ? ease((p - 0.5) / 0.12) : max(0, 1 - (p - 0.62) / 0.06)
        if flower > 0 {
            var f = g; f.translateBy(x: branch.x, y: branch.y + 6); f.scaleBy(x: flower, y: flower)
            for i in 0..<5 { var pt = f; pt.rotate(by: .degrees(Double(i) * 72 + t * 8)); pt.fill(Path(ellipseIn: CGRect(x: 1, y: -3.5, width: 11, height: 7)), with: .color(Color(hex: 0xFFD54F))) }
            f.fill(Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(Color(hex: 0xF9A825)))
        }
        if p >= 0.62 && !hideFruit {
            let fr = fruit(p, sway: sway)
            babyTomo(&whole, fr.center, fr.radius, ripeness: min(1, (p - 0.62) / 0.38), t: t, sway: sway)
        }
        let pot = Path { q in
            q.move(to: CGPoint(x: base.x - 30, y: base.y + 6)); q.addLine(to: CGPoint(x: base.x + 30, y: base.y + 6))
            q.addLine(to: CGPoint(x: base.x + 23, y: base.y + 36)); q.addQuadCurve(to: CGPoint(x: base.x - 23, y: base.y + 36), control: CGPoint(x: base.x, y: base.y + 39)); q.closeSubpath()
        }
        whole.fill(pot, with: .linearGradient(Gradient(colors: [Color(hex: 0xD9774A), Color(hex: 0xA9502C)]), startPoint: CGPoint(x: base.x - 30, y: 0), endPoint: CGPoint(x: base.x + 30, y: 0)))
        whole.fill(Path(roundedRect: CGRect(x: base.x - 34, y: base.y - 3, width: 68, height: 12), cornerRadius: 4), with: .color(Color(hex: 0xC2643A)))
        whole.fill(Path(ellipseIn: CGRect(x: base.x - 28, y: base.y - 3, width: 56, height: 7)), with: .color(Color(hex: 0x5A3A26)))
    }

    /// The fruit on the vine: green to orange to red, asleep while it ripens.
    static func babyTomo(_ g: inout GraphicsContext, _ center: CGPoint, _ rf: CGFloat, ripeness q: Double, t: Double, sway: Double = 0,
                         wiggle: Double = 0, sx: CGFloat = 1, sy: CGFloat = 1) {
        let col = q < 0.6 ? mix(0x8BC34A, 0x9CCC65, q / 0.6) : q < 0.85 ? mix(0x9CCC65, 0xFB8C00, (q - 0.6) / 0.25) : mix(0xFB8C00, 0xE8392B, (q - 0.85) / 0.15)
        var fr = g
        fr.translateBy(x: center.x, y: center.y - rf * 0.85); fr.rotate(by: .radians(-sway * 2 + wiggle)); fr.scaleBy(x: sx, y: sy); fr.translateBy(x: -center.x, y: -(center.y - rf * 0.85))
        fr.fill(bodyPath(center, rf), with: .radialGradient(Gradient(colors: [col.opacity(0.75), col]), center: CGPoint(x: center.x - rf * 0.4, y: center.y - rf * 0.4), startRadius: 0, endRadius: rf * 1.8))
        fr.fill(Path(ellipseIn: CGRect(x: center.x - rf * 0.6, y: center.y - rf * 0.55, width: rf * 0.35, height: rf * 0.2)), with: .color(.white.opacity(0.35)))
        if rf > 16 {
            for dx in [-rf * 0.3, rf * 0.3] { fr.stroke(arc(CGPoint(x: center.x + dx, y: center.y + rf * 0.08), rf * 0.22, rf * 0.12), with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
            fr.fill(Path(ellipseIn: CGRect(x: center.x - 1.8, y: center.y + rf * 0.3, width: 3.6, height: 3.6)), with: .color(ink))
        }
        for d in [20.0, 80.0, 150.0] { var l = fr; l.translateBy(x: center.x, y: center.y - rf * 0.85); l.rotate(by: .degrees(d)); l.fill(leaf(rf * 0.45, rf * 0.16), with: .color(Color(hex: 0x3F8F3A))) }
    }

    // MARK: the ripe tomato jumps off the vine and becomes Tomo

    /// 0-0.35 s swell and wiggle (anticipation), 0.35-0.5 pop off with a stretch, 0.5-1.05 hop and spin
    /// along an arc to Tomo's spot while the plant fades, 1.05-1.2 land squash, then settle and open the eyes.
    static func entrance(_ ctx: inout GraphicsContext, _ s: TomoScene, _ t: Double) {
        let k = s.phaseT
        let start = fruit(1, sway: 0)
        if s.reduceMotion {
            var a = ctx; a.opacity = max(0, 1 - k / 0.6); plant(&a, 1, t)
            var b = ctx; b.opacity = min(1, k / 0.6)
            tomo(&b, home, radius, face: .happy, eaten: 0, t: t)
            return
        }
        var stage = ctx
        stage.opacity = k < 0.5 ? 1 : max(0, 1 - (k - 0.5) / 0.4)
        if stage.opacity > 0 { plant(&stage, 1, t, hideFruit: true) }
        if k < 0.5 {
            let a = min(1, k / 0.35)
            let wig = k < 0.35 ? sin(k * 46) * 0.16 * a : 0
            let pop = k < 0.35 ? 1.0 : ease((k - 0.35) / 0.15)
            babyTomo(&ctx, CGPoint(x: start.center.x, y: start.center.y - 6 * pop), start.radius * (1 + 0.12 * a), ripeness: 1, t: t,
                     wiggle: wig, sx: 1 - 0.14 * pop, sy: 1 + 0.24 * pop)
            return
        }
        let to = home, scale0 = start.radius / radius
        if k < 1.05 {
            let q = (k - 0.5) / 0.55, e = easeOut(q)
            let x = start.center.x + (to.x - start.center.x) * e
            let y = start.center.y + (to.y - start.center.y) * e - 34 * sin(q * .pi)   // the arc of the hop, kept inside the window
            let sc = scale0 + (1 - scale0) * e
            var g = ctx
            g.translateBy(x: x, y: y); g.rotate(by: .radians(2 * .pi * ease(q))); g.scaleBy(x: sc, y: sc); g.translateBy(x: -to.x, y: -to.y)
            tomo(&g, to, radius, face: .sleep, eaten: 0, t: t, sx: q < 0.3 ? 0.9 : 1, sy: q < 0.3 ? 1.12 : 1)
            return
        }
        let q = k - 1.05
        let (sx, sy, _) = q < 0.15 ? lerp3((1, 1, 0), (1.16, 0.84, 0), easeIn(q / 0.15)) : lerp3((1.16, 0.84, 0), (1, 1, 0), easeOutBack((q - 0.15) / 0.25))
        shadow(&ctx, CGPoint(x: to.x, y: to.y + radius * 0.98), radius)
        tomo(&ctx, to, radius, face: .happy, eaten: 0, t: t, sx: sx, sy: sy, eyesClosed: q < 0.2)
    }

    // MARK: 5 of 5: the victory dance

    struct Confetto { let angle: Double, speed: Double, spin: Double, color: UInt32, w: Double }
    static let confetti: [Confetto] = (0..<44).map { i in
        let u = abs(sin(Double(i) * 91.7)), v = abs(sin(Double(i) * 17.3 + 2))
        return Confetto(angle: -.pi / 2 + (u - 0.5) * 2.2, speed: 220 + 200 * v, spin: (v - 0.5) * 14,
                        color: [0xE8392B, 0x7BCB5E, 0xFFD54F, 0xFFF3E0, 0xFF8FA6][i % 5], w: 4 + 4 * u)
    }

    /// Three hops, left, right, then a spin, under a burst of confetti; the crate's tomatoes wave in turn.
    static func celebrate(_ ctx: inout GraphicsContext, _ s: TomoScene, _ t: Double) {
        let k = s.phaseT, c = home, r = radius
        var m = Motion()
        if !s.reduceMotion && k < 2.4 {
            let hop = k.truncatingRemainder(dividingBy: 0.8) / 0.8, n = Int(k / 0.8)
            let up = sin(hop * .pi)
            m.dy = -22 * up
            m.sx = hop < 0.12 || hop > 0.88 ? 1.1 : 1 - 0.06 * up; m.sy = hop < 0.12 || hop > 0.88 ? 0.9 : 1 + 0.08 * up
            m.rot = n == 2 ? 2 * .pi * ease(hop) : (n == 0 ? -0.18 : 0.18) * up
        }
        let spinning = k >= 1.6 && k < 2.4
        shadow(&ctx, CGPoint(x: c.x, y: c.y + r * 0.98), r * (1 + m.dy / 60))
        var body = ctx; body.translateBy(x: 0, y: m.dy)
        if spinning { body.translateBy(x: c.x, y: c.y); body.rotate(by: .radians(m.rot)); body.translateBy(x: -c.x, y: -c.y) }
        tomo(&body, c, r, face: .happy, eaten: 0, t: t, sx: m.sx, sy: m.sy, rot: spinning ? 0 : m.rot, spin: sin(t * 3) * 0.4)
        guard !s.reduceMotion, k > 0.15 else { return }
        let f = k - 0.15
        for (i, p) in confetti.enumerated() {
            let x = c.x + p.speed * cos(p.angle) * f * 0.55, y = c.y - 20 + p.speed * sin(p.angle) * f * 0.55 + 0.5 * 300 * f * f
            var g = ctx; g.opacity = max(0, 1 - f / 3.2)
            g.translateBy(x: x, y: y); g.rotate(by: .radians(p.spin * f + Double(i)))
            g.fill(Path(roundedRect: CGRect(x: -p.w / 2, y: -2, width: p.w, height: 4), cornerRadius: 1.5), with: .color(Color(hex: p.color)))
        }
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ k: Double) -> Color {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double(v >> s & 255) / 255 }
        let k = min(1, max(0, k))
        return Color(.sRGB, red: ch(a, 16) + (ch(b, 16) - ch(a, 16)) * k, green: ch(a, 8) + (ch(b, 8) - ch(a, 8)) * k, blue: ch(a, 0) + (ch(b, 0) - ch(a, 0)) * k)
    }

    // MARK: the day's harvest

    static func crate(_ ctx: inout GraphicsContext, _ amount: Double, newest: Double?, glow: Bool, wave: Double?, dark: Bool, t: Double) {
        let n = Int(amount.rounded(.up)), part = amount - floor(amount)
        let box = CGRect(x: 22, y: 204, width: 156, height: 26)
        if glow {
            var g = ctx; g.opacity = 0.45 + 0.25 * sin(t * 2)
            g.fill(Path(roundedRect: box.insetBy(dx: -10, dy: -10), cornerRadius: 16),
                   with: .radialGradient(Gradient(colors: [Color(hex: 0xFFC83D, 0.9), .clear]), center: CGPoint(x: box.midX, y: box.midY), startRadius: 0, endRadius: box.width * 0.6))
        }
        for i in 0..<5 {
            let c = CGPoint(x: box.minX + 18 + CGFloat(i) * 30, y: box.minY + 2)
            if i < n {
                var k = 1.0
                if let st = newest, i == n - 1 { k = st < 1.1 ? 0 : min(1, (st - 1.1) / 0.35) }
                guard k > 0 else { continue }
                var g = ctx
                var lift = -40 * (1 - k) * (1 - k)
                if let w = wave { let q = w - 0.4 - Double(i) * 0.18; if q > 0 && q < 0.5 { lift -= 9 * sin(q / 0.5 * .pi) } }
                g.translateBy(x: 0, y: lift)
                if i == n - 1 && part > 0.001 {
                    // a tomato still filling: an outline, ripening up from the bottom by the minutes worked
                    g.stroke(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 9, width: 20, height: 18)), with: .color(dark ? .white.opacity(0.28) : .black.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    g.clip(to: Path(CGRect(x: c.x - 14, y: c.y + 11 - 22 * part, width: 28, height: 22 * part)))
                }
                g.fill(bodyPath(c, 11), with: .radialGradient(red, center: CGPoint(x: c.x - 4, y: c.y - 5), startRadius: 0, endRadius: 20))
                g.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 5, height: 3)), with: .color(.white.opacity(0.45)))
                for d in [0.0, 72, 144, 216, 288] { var l = g; l.translateBy(x: c.x, y: c.y - 9); l.rotate(by: .degrees(d - 90)); l.fill(leaf(6, 3), with: .color(Color(hex: 0x3F8F3A))) }
            } else {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 9, width: 20, height: 18)), with: .color(dark ? .white.opacity(0.28) : .black.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        let front = Path(roundedRect: CGRect(x: box.minX, y: box.minY + 6, width: box.width, height: box.height - 6), cornerRadius: 5)
        ctx.fill(front, with: .linearGradient(Gradient(colors: [Color(hex: 0xC4935F), Color(hex: 0x8E6038)]), startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
        ctx.stroke(Path { p in p.move(to: CGPoint(x: box.minX + 4, y: box.minY + 18)); p.addLine(to: CGPoint(x: box.maxX - 4, y: box.minY + 18)) }, with: .color(Color(hex: 0x6E4826, 0.6)), lineWidth: 1)
        for x in [box.minX + 8, box.maxX - 8] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: box.minY + 11, width: 3, height: 3)), with: .color(Color(hex: 0x5A3A1E)))
        }
    }
}

/// A frame of Tomo. `time` drives blinks, breathing and the timed moments.
struct TomoCanvas: View {
    var scene: TomoScene
    var time: Double
    var body: some View {
        Canvas { ctx, _ in TomoArt.draw(&ctx, scene, time) }
            .frame(width: TomoArt.size.width, height: TomoArt.size.height)
    }
}
