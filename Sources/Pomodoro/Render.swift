import SwiftUI
import PomodoroCore

/// Tomo's speech bubble, shown only at transitions.
struct Bubble: View {
    var text: String
    var dark: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(dark ? Color.white : Color(hex: 0x2B1A17))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(dark ? Color(hex: 0x2C2C30) : .white)
                .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 6, y: 2))
            .overlay(alignment: .bottom) {
                Triangle().fill(dark ? Color(hex: 0x2C2C30) : .white).frame(width: 14, height: 8).offset(y: 7)
            }
            .frame(maxWidth: 200)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath() } }
}

/// `Pomodoro --sheet <light|dark> <out.png>` draws every state side by side, for checking by eye.
enum Render {
    struct Cell { let label: String; let scene: TomoScene; let time: Double; let bubble: String? }

    static func cells(dark: Bool) -> [Cell] {
        func s(_ m: TomoScene.Mode, _ p: Double = 0, app: FocusApp? = .hackerSolve, n: Int = 2, at: Double = 9, hold: Double = 0,
               look: CGVector = .zero) -> TomoScene {
            TomoScene(mode: m, progress: p, phaseT: at, app: app, harvested: n, hold: hold, dark: dark, look: look)
        }
        return [
            Cell(label: "idle (eyes follow cursor)", scene: s(.idle, app: nil, n: 0, look: CGVector(dx: 0.6, dy: -0.3)), time: 1, bubble: "Hi, I'm Tomo. Open a lesson and I'll keep you company."),
            Cell(label: "focus 0:00", scene: s(.focus, 0.0, look: CGVector(dx: 0, dy: 0.6)), time: 1, bubble: "HackerSolve, Lesson 4. Let's grow one."),
            Cell(label: "focus 22 min", scene: s(.focus, 22.0 / 45, look: CGVector(dx: 0, dy: 0.6)), time: 2, bubble: nil),
            Cell(label: "focus 44 min", scene: s(.focus, 44.0 / 45, app: .speakFit, look: CGVector(dx: 0, dy: 0.6)), time: 2, bubble: nil),
            Cell(label: "nudge", scene: s(.nudge, 0.4, look: CGVector(dx: 1, dy: 0)), time: 1, bubble: "Not now. Lesson 4 first."),
            Cell(label: "hmmph", scene: s(.hmmph, 0.4, look: CGVector(dx: -1, dy: 0)), time: 1, bubble: "Hmmph. That's not Lesson 4."),
            Cell(label: "simmer", scene: s(.simmer, 0.4), time: 1, bubble: "Still off track..."),
            Cell(label: "boil", scene: s(.boil, 0.4), time: 1.3, bubble: "BACK. TO. LESSON. 4."),
            Cell(label: "siren (red)", scene: s(.siren, 0.4), time: 0.1, bubble: "WEE-WOO! Lesson 4. Tap me when you're back."),
            Cell(label: "siren (blue)", scene: s(.siren, 0.4), time: 0.5, bubble: nil),
            Cell(label: "breathe: in (cyclic)", scene: { var x = s(.breathe, n: 3, at: 2.9); x.harvestFraction = 2.67; return x }(), time: 1, bubble: "Session 3 harvested! Breathe with me."),
            Cell(label: "breathe: out", scene: { var x = s(.breathe, n: 3, at: 6.5); x.harvestFraction = 2.67; return x }(), time: 1, bubble: nil),
            Cell(label: "splash 0.5 s", scene: s(.splash, 1, n: 3, at: 0.5), time: 1, bubble: nil),
            Cell(label: "break: pot grows in 0.25 s", scene: s(.rest, 0.02, n: 3, at: 0.25), time: 1, bubble: "Session 3 harvested! Stand up."),
            Cell(label: "break 80%", scene: s(.rest, 0.8, n: 3), time: 1, bubble: nil),
            Cell(label: "entrance 0.3 s wiggle", scene: s(.entrance, 1, n: 3, at: 0.3), time: 1, bubble: nil),
            Cell(label: "entrance 0.75 s hop", scene: s(.entrance, 1, n: 3, at: 0.75), time: 1, bubble: nil),
            Cell(label: "entrance 1.12 s land", scene: s(.entrance, 1, n: 3, at: 1.12), time: 1, bubble: nil),
            Cell(label: "ready", scene: s(.ready, n: 3), time: 0.3, bubble: "Ripe! Tap me to start session 4."),
            Cell(label: "paused + holding", scene: s(.paused, 0.3, hold: 0.6), time: 1.2, bubble: "Paused at 13:30. Hold me to carry on."),
            Cell(label: "5 of 5: dance 0.9 s", scene: s(.celebrate, n: 5, at: 0.9), time: 1, bubble: "Full harvest! Lesson 4, Lesson 5, Day 12 voice, Job review, Lesson 6."),
            Cell(label: "5 of 5: dance 2.0 s", scene: s(.celebrate, n: 5, at: 2.0), time: 1, bubble: nil),
            Cell(label: "day done", scene: s(.dayDone, app: nil, n: 5), time: 1, bubble: "Full harvest. 3 full days so far."),
        ]
    }

    /// `Pomodoro --face <out.png>`: the resting face alone at true on-screen size (1 pt = 2 px on Retina),
    /// for before and after comparisons.
    @MainActor static func face(dark: Bool, to url: URL) {
        let v = TomoCanvas(scene: TomoScene(mode: .idle, dark: dark), time: 1).padding(10).background(dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xF3F1EE))
        let r = ImageRenderer(content: v); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    @MainActor static func sheet(dark: Bool, to url: URL) {
        let cols = 4
        let grid = VStack(spacing: 0) {
            ForEach(0..<(cells(dark: dark).count + cols - 1) / cols, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(cells(dark: dark)[(row * cols)..<min(cells(dark: dark).count, row * cols + cols)].indices, id: \.self) { i in
                        let c = cells(dark: dark)[i]
                        VStack(spacing: 6) {
                            ZStack { if let b = c.bubble { Bubble(text: b, dark: dark) } }.frame(height: 62, alignment: .bottom)
                            TomoCanvas(scene: c.scene, time: c.time)
                            Text(c.label).font(.system(size: 11, design: .monospaced)).foregroundStyle(dark ? Color.white.opacity(0.6) : .black.opacity(0.55))
                        }
                        .frame(width: 240, height: 340)
                    }
                }
            }
        }
        .padding(16)
        .background(dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xF3F1EE))
        .environment(\.colorScheme, dark ? .dark : .light)
        let r = ImageRenderer(content: grid); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); return }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}

extension Render {
    /// `Pomodoro --icon <out.png>`: Tomo's happy face on a paper tile, 1024 px, for the app icon.
    @MainActor static func icon(to url: URL) {
        let tile = Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0xFFFDF9), Color(hex: 0xF3ECE2)]), startPoint: CGPoint(x: 0, y: 100), endPoint: CGPoint(x: 0, y: 924)))
            ctx.translateBy(x: 512 - 100 * 5.4, y: 520 - 104 * 5.4); ctx.scaleBy(x: 5.4, y: 5.4)
            TomoArt.shadow(&ctx, CGPoint(x: 100, y: 164), 60)
            TomoArt.tomo(&ctx, CGPoint(x: 100, y: 104), 60, face: .happy, eaten: 0, t: 0.4)
        }.frame(width: 1024, height: 1024)
        let r = ImageRenderer(content: tile); r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("icon failed"); return }
        try? png.write(to: url)
    }
}

extension Render {
    /// `Pomodoro --frames <idle|entrance|celebrate|splash> <dir>`: 30 fps PNG frames of a performed moment, for GIFs.
    @MainActor static func frames(_ what: String, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let length: Double = what == "siren" ? 3 : what == "idle" ? 7 : what == "celebrate" ? TomoArt.celebrateLength : what == "splash" ? TomoArt.splashLength + 1 : TomoArt.entranceLength + 0.8
        for f in 0..<Int(length * 30) {
            let t = Double(f) / 30
            var s = TomoScene(harvested: 3)
            switch what {
            case "idle":
                // the eyes follow a cursor drifting around; a stretch beat at 2 s, a hop at 4.8 s
                s.mode = .idle; s.look = CGVector(dx: sin(t * 0.9), dy: 0.5 * cos(t * 0.7))
                if t >= 2 && t < 3.6 { s.react = .stretch; s.reactT = t - 2 }
                if t >= 4.8 { s.react = .hop; s.reactT = t - 4.8 }
            case "siren":
                s.mode = .siren; s.progress = 0.4
            case "entrance":
                s.mode = t < TomoArt.entranceLength ? .entrance : .ready; s.phaseT = t; s.progress = 1
            case "celebrate":
                s.mode = .celebrate; s.phaseT = t; s.harvested = 5
            default:
                if t < TomoArt.splashLength { s.mode = .splash; s.phaseT = t } else { s.mode = .rest; s.progress = 0.01; s.phaseT = t - TomoArt.splashLength }
                s.harvested = 3
            }
            let v = TomoCanvas(scene: s, time: t + 1).background(Color(hex: 0xF3F1EE))
            let r = ImageRenderer(content: v); r.scale = 1.5
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent(String(format: "%03d.png", f)))
            }
        }
    }
}

extension Render {
    /// `Pomodoro --insights <data dir> <range> <out.png>`: the insights window drawn from a data folder.
    @MainActor static func insights(dir: URL, range: String, to url: URL) {
        let store = Store(root: dir), db = SessionDB(url: dir.appendingPathComponent("sessions.sqlite"))
        var v = InsightsView(db: db, store: store); v.range = InsightsView.Range(rawValue: range) ?? .today
        let r = ImageRenderer(content: v.frame(width: 760, height: 620)); r.scale = 1.5
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); return }
        try? png.write(to: url)
    }
}

extension Render {
    /// `Pomodoro --eaten <out.png>`: focus at 0, 25, 50, 75 and 100% of the active minutes.
    @MainActor static func eaten(to url: URL) {
        let strip = HStack(spacing: 0) {
            ForEach([0.0, 0.25, 0.5, 0.75, 0.999], id: \.self) { p in
                VStack(spacing: 2) {
                    TomoCanvas(scene: TomoScene(mode: .focus, progress: p, harvested: 1, look: CGVector(dx: 0, dy: 0.6)), time: 3)
                    Text("\(Int((p * 100).rounded()))% · \(Int((p * 45).rounded())) active min").font(.system(size: 12, design: .rounded)).foregroundStyle(.black.opacity(0.6))
                }.frame(width: 220)
            }
        }.padding(12).background(Color(hex: 0xF3F1EE))
        let r = ImageRenderer(content: strip); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
