import AppKit
import SwiftUI

/// A tomato kitchen timer, the object the Pomodoro technique is named after: twist the leaf around the face to
/// set 5 to 60 minutes. Drawn entirely here, no system controls (23 Oct: "do not use anything from default mac").
/// One full turn is an hour; it snaps every 5 minutes and never wraps past 60 or below 5.
struct TimerDial: View {
    @Binding var minutes: Int
    var size: CGFloat = 210
    @FocusState private var focused: Bool

    static let red = Gradient(colors: [Color(hex: 0xFF7A63), Color(hex: 0xE8392B), Color(hex: 0xB3201B)])
    static let ink = Color(hex: 0x3A1512)

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, sz) }
            .frame(width: size, height: size)
            .overlay {
                VStack(spacing: 0) {
                    Text("\(minutes)").font(.system(size: size * 0.19, weight: .heavy, design: .rounded)).foregroundStyle(Self.ink)   // the face is always white, so fixed ink, not the theme token
                        .contentTransition(.numericText()).animation(.snappy(duration: 0.15), value: minutes)
                    Text("min").font(.system(size: size * 0.068, weight: .semibold, design: .rounded)).foregroundStyle(Color(hex: 0x6B5B54))
                }
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in set(from: v.location) })
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(.rightArrow) { step(5); return .handled }
            .onKeyPress(.upArrow) { step(5); return .handled }
            .onKeyPress(.leftArrow) { step(-5); return .handled }
            .onKeyPress(.downArrow) { step(-5); return .handled }
            .accessibilityElement()
            .accessibilityLabel("Session length")
            .accessibilityValue("\(minutes) minutes")
            .accessibilityAdjustableAction { $0 == .increment ? step(5) : step(-5) }
    }

    private func step(_ d: Int) { commit(min(60, max(5, minutes + d))) }

    /// Angle from 12 o'clock, clockwise, to minutes; a jump across 12 o'clock is clamped, not wrapped.
    private func set(from p: CGPoint) {
        let c = CGPoint(x: size / 2, y: size / 2)
        var a = atan2(p.x - c.x, c.y - p.y)            // 0 at top, clockwise positive
        if a < 0 { a += 2 * .pi }
        var m = Int((a / (2 * .pi) * 60 / 5).rounded()) * 5
        if m == 0 { m = minutes > 30 ? 60 : 5 }
        if minutes >= 50 && m <= 15 { m = 60 }
        if minutes <= 10 && m >= 45 { m = 5 }
        commit(min(60, max(5, m)))
    }

    private func commit(_ m: Int) {
        guard m != minutes else { return }
        minutes = m
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        Sound.play(.tick)
    }

    /// Layout, outside in: quarter numbers in a ring outside the dial (so the handle can never cover one),
    /// the tomato rim, the white face, the time arc on a quiet track at the face's edge with the leaf handle on
    /// it, tick marks just inside the arc, and the number in the clear centre.
    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let labelR = sz.width / 2 - 9, r = sz.width / 2 - 22, face = r - 9
        let trackR = face - 9, tickOut = face - 19, tickIn = face - 25
        // quarter numbers outside the rim, all four, never under the handle
        for (i, n) in [(0, 60), (3, 15), (6, 30), (9, 45)] {
            let a = Double(i) / 12 * 2 * .pi - .pi / 2
            ctx.draw(Text("\(n)").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(T.ink2),
                     at: CGPoint(x: c.x + labelR * cos(a), y: c.y + labelR * sin(a)))
        }
        // tomato rim, soft shadow, a little gloss
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.16), radius: 7, y: 3))
        shadowed.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                      with: .radialGradient(Self.red, center: CGPoint(x: c.x - r * 0.4, y: c.y - r * 0.5), startRadius: 0, endRadius: r * 1.8))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.72, y: c.y - r * 0.94, width: r * 0.42, height: r * 0.16)), with: .color(.white.opacity(0.32)))
        // the face
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - face, y: c.y - face, width: face * 2, height: face * 2)), with: .color(.white))
        // time arc on a quiet track
        let frac = Double(minutes) / 60
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - trackR, y: c.y - trackR, width: trackR * 2, height: trackR * 2)),
                   with: .color(Color(hex: 0xF1ECE6)), lineWidth: 7)
        var arc = Path()
        arc.addArc(center: c, radius: trackR, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * frac), clockwise: false)
        ctx.stroke(arc, with: .color(Color(hex: 0xE8392B)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        // ticks every 5 minutes just inside the arc; longer at the quarters
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi - .pi / 2, quarter = i % 3 == 0
            let r2 = quarter ? tickIn - 3 : tickIn
            var t = Path(); t.move(to: CGPoint(x: c.x + tickOut * cos(a), y: c.y + tickOut * sin(a))); t.addLine(to: CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a)))
            ctx.stroke(t, with: .color(Color(hex: 0x3A1512).opacity(quarter ? 0.4 : 0.2)), style: StrokeStyle(lineWidth: quarter ? 2 : 1.3, lineCap: .round))
        }
        // the leaf handle sits on the arc's end, pointing along it
        let ha = -Double.pi / 2 + 2 * .pi * frac
        let hp = CGPoint(x: c.x + trackR * cos(ha), y: c.y + trackR * sin(ha))
        var leaf = ctx
        leaf.translateBy(x: hp.x, y: hp.y); leaf.rotate(by: .radians(ha + .pi / 2))
        var lp = Path()
        lp.move(to: CGPoint(x: -3, y: 0))
        lp.addQuadCurve(to: CGPoint(x: 15, y: 0), control: CGPoint(x: 6, y: -8))
        lp.addQuadCurve(to: CGPoint(x: -3, y: 0), control: CGPoint(x: 6, y: 7))
        leaf.addFilter(.shadow(color: .black.opacity(0.22), radius: 1.5, y: 1))
        leaf.fill(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(.white))
        leaf.fill(Path(ellipseIn: CGRect(x: -5, y: -5, width: 10, height: 10)), with: .color(Color(hex: 0x2E7D32)))
        leaf.fill(lp, with: .linearGradient(Gradient(colors: [Color(hex: 0x7BCB5E), Color(hex: 0x2E8B3E)]), startPoint: .zero, endPoint: CGPoint(x: 15, y: 0)))
        // the calyx on top, as on Tomo
        for (deg, len) in [(195.0, 13.0), (345.0, 13.0)] {   // sideways only, so the "60" above stays clear
            var l = ctx; l.translateBy(x: c.x, y: c.y - r + 2); l.rotate(by: .degrees(deg))
            var p = Path(); p.move(to: .zero); p.addQuadCurve(to: CGPoint(x: len, y: 1), control: CGPoint(x: len * 0.45, y: -4)); p.addQuadCurve(to: .zero, control: CGPoint(x: len * 0.5, y: 4))
            l.fill(p, with: .color(Color(hex: 0x3F8F3A)))
        }
    }
}
