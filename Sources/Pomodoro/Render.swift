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
        func s(_ m: TomoScene.Mode, _ p: Double = 0, app: String? = "HackerSolve", n: Int = 2, at: Double = 9, hold: Double = 0,
               look: CGVector = .zero) -> TomoScene {
            TomoScene(mode: m, progress: p, phaseT: at, app: app, harvested: n, hold: hold, dark: dark, look: look)
        }
        return [
            Cell(label: "idle (eyes follow cursor)", scene: s(.idle, app: nil, n: 0, look: CGVector(dx: 0.6, dy: -0.3)), time: 1, bubble: "Hi, I'm Tomo. Open a lesson and I'll keep you company."),
            Cell(label: "focus 0:00", scene: s(.focus, 0.0, look: CGVector(dx: 0, dy: 0.6)), time: 1, bubble: "HackerSolve, Lesson 4. Let's grow one."),
            Cell(label: "focus 22 min", scene: s(.focus, 22.0 / 45, look: CGVector(dx: 0, dy: 0.6)), time: 2, bubble: nil),
            Cell(label: "focus 44 min", scene: s(.focus, 44.0 / 45, app: "SpeakFit", look: CGVector(dx: 0, dy: 0.6)), time: 2, bubble: nil),
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
        let length: Double = what == "siren" ? 3 : what == "idle" ? 7 : what == "celebrate" ? TomoArt.celebrateLength : what == "splash" ? TomoArt.splashLength + 1 : what == "breathe" ? 12 : what == "harvest" ? 8 : what == "update" ? 2 : TomoArt.entranceLength + 0.8
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
            case "update":
                s.mode = .idle; s.update = true
            case "harvest":
                // the break's second half compressed into 6 s, then the ripe tomato hops off the vine
                if t < 6 { s.mode = .rest; s.progress = t / 6; s.phaseT = t } else { s.mode = .entrance; s.phaseT = t - 6; s.progress = 1 }
            case "breathe":
                s.mode = .breathe; s.phaseT = t + 1   // past the fade-in
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
    /// `Pomodoro --insights <data dir> <Today|Week|Month> <out.png>`: the whole insights page, unscrolled, from a data folder.
    @MainActor static func insights(dir: URL, range: String, to url: URL) {
        let store = Store(root: dir), db = SessionDB(url: dir.appendingPathComponent("sessions.sqlite"))
        let v = InsightsView(db: db, store: store, range: InsightsView.Range(rawValue: range) ?? .today, forRender: true)
        let r = ImageRenderer(content: v); r.scale = 1.5
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

extension Render {
    /// `Pomodoro --launcher <data dir> <out.png>`: the launcher panel drawn from a data folder's profiles.
    @MainActor static func launcher(dir: String, to url: URL) {
        setenv("POMODORO_HOME", dir, 1)
        let m = Model()
        let v = LauncherView(m: m, close: {}, openInsights: {}, openProfiles: {}, openSettings: {}).padding(12).background(Color(hex: 0xE9E6E2))
        let r = ImageRenderer(content: v); r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("render failed"); return }
        try? png.write(to: url)
    }
}

extension Render {
    /// `Pomodoro --profiles <data dir> <out prefix>`: the Profiles window at its minimum size, light and dark,
    /// for each create step with a sample draft, plus the edit view. Drawn offscreen, nothing is shown.
    @MainActor static func profiles(dir: String, to prefix: String) {
        setenv("POMODORO_HOME", dir, 1)
        let m = Model()
        let site = Profile(id: "d", name: "Thesis", kind: .website, domains: ["github.com"], browsers: ["com.google.Chrome"], minutes: 30)
        let cases: [(String, Profile?, Int)] = [("create-1-empty", Profile(id: "d", name: "", kind: .app), 0),
                                                ("create-1-picked", site, 0), ("create-2-sites", site, 1),
                                                ("create-3-allowed", site, 2), ("create-4-length", site, 3), ("edit", nil, 0)]
        for (name, d, step) in cases {
            for dark in [false, true] {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let host = NSHostingView(rootView: ProfilesView(m: m, draft: d, step: step).ignoresSafeArea()); host.sizingOptions = []
                w.contentView = host; Chrome.style(w)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}

extension Render {
    /// `Pomodoro --perf [seconds]`: Tomo animating in focus inside the real app event loop, in a click-through
    /// window at 1% opacity, at 15 then 30 fps. Prints the process CPU share and frames drawn for each; exits 1
    /// if 15 fps costs over 2% (the active-focus budget). `PERF_EMPTY=1` draws a plain shape (harness baseline).
    @MainActor static var frames = 0
    @MainActor static func perf(seconds: Double) {
        func cpu() -> Double {
            var u = rusage(); getrusage(RUSAGE_SELF, &u)
            return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        }
        let empty = ProcessInfo.processInfo.environment["PERF_EMPTY"] != nil
        if let mode = ProcessInfo.processInfo.environment["PERF_APP"] { app(mode, seconds: seconds, cpu: cpu) }
        var results: [Double] = []
        func run(_ rates: [Double]) {
            guard let fps = rates.first else { exit(results.first.map { $0 > 2 ? 1 : 0 } ?? 1) }
            let start = Date()
            let useTimer = ProcessInfo.processInfo.environment["PERF_TIMER"] != nil
            let clock = PerfClock()
            if useTimer { clock.timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { _ in MainActor.assumeIsolated { clock.now = Date() } } }
            let v = PerfHost(clock: clock, useTimer: useTimer, fps: fps) { tl in
                let _ = (Render.frames += 1)
                if ProcessInfo.processInfo.environment["PERF_STATIC"] != nil { Color.red.opacity(0.5) }
                else if empty { Rectangle().fill(.red).opacity(tl.timeIntervalSince(start).truncatingRemainder(dividingBy: 1)) }
                else if ProcessInfo.processInfo.environment["PERF_DG"] != nil { TomoCanvas(scene: TomoScene(mode: .focus, progress: 0.4, harvested: 1, look: CGVector(dx: 0, dy: 0.6)), time: tl.timeIntervalSince(start)).drawingGroup() }
                else { TomoCanvas(scene: TomoScene(mode: .focus, progress: 0.4, harvested: 1, look: CGVector(dx: 0, dy: 0.6)), time: tl.timeIntervalSince(start)) }
            }
            let w = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 240, height: 340), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.alphaValue = 0.01; w.ignoresMouseEvents = true; w.level = .floating
            let h = NSHostingView(rootView: v); h.sizingOptions = []; w.contentView = h; w.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {   // after a warm-up second
                MainActor.assumeIsolated {
                    Render.frames = 0
                    let c0 = cpu(), t0 = Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                        MainActor.assumeIsolated {
                            let share = (cpu() - c0) / Date().timeIntervalSince(t0) * 100
                            print(String(format: "tomo %.0f fps: %.1f%% CPU, %.0f frames/s drawn", fps, share, Double(Render.frames) / seconds))
                            results.append(share)
                            w.orderOut(nil); w.contentView = nil
                            run(Array(rates.dropFirst()))
                        }
                    }
                }
            }
        }
        run(ProcessInfo.processInfo.environment["PERF_RATES"].map { $0.split(separator: ",").compactMap { Double($0) } } ?? [4, 8, 15, 30])
        NSApplication.shared.run()
    }
}

extension Render {
    /// The real Tomo panel (model, clock, view) in a 1% window: `PERF_APP=idle` or `PERF_APP=focus` (an Other
    /// session; run with POMODORO_HOME, POMODORO_HIDE_ONLY=none and POMODORO_EVENT_NAME set, so nothing real is touched).
    @MainActor static func app(_ mode: String, seconds: Double, cpu: @escaping () -> Double) {
        UserDefaults.standard.set(true, forKey: "soundMuted")
        let m = Model()
        if mode == "focus" { m.start(.other, task: "perf") }
        let w = NSPanel(contentRect: NSRect(x: 40, y: 40, width: 240, height: 340), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.alphaValue = 0.01; w.ignoresMouseEvents = true; w.level = .floating
        let h = NSHostingView(rootView: PanelView(m: m)); h.sizingOptions = []; w.contentView = h; w.orderFrontRegardless()
        m.panel = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {   // past the start reaction and its bubble
            MainActor.assumeIsolated {
                m.bubble = nil
                let c0 = cpu(), t0 = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                    MainActor.assumeIsolated {
                        let share = (cpu() - c0) / Date().timeIntervalSince(t0) * 100
                        print(String(format: "app %@ (%@): %.2f%% CPU over %.0f s", mode, m.state.phase.rawValue, share, seconds))
                        exit(share > 2 ? 1 : 0)
                    }
                }
            }
        }
        NSApplication.shared.run()
    }
}

@MainActor final class PerfClock: ObservableObject { @Published var now = Date(); var timer: Timer? }
struct PerfHost<C: View>: View {
    @ObservedObject var clock: PerfClock
    var useTimer: Bool, fps: Double
    @ViewBuilder var content: (Date) -> C
    var body: some View {
        if useTimer { content(clock.now) }
        else { TimelineView(.periodic(from: .now, by: 1 / fps)) { tl in content(tl.date) } }
    }
}

extension Render {
    /// `Pomodoro --pages <data dir> <out prefix>`: Help and Settings at their minimum sizes, light and dark, offscreen.
    @MainActor static func pages(dir: String, to prefix: String) {
        setenv("POMODORO_HOME", dir, 1)
        let m = Model()
        m.update = Update.Release(version: "0.5.2", notes: "- Tomo stays visible with Stage Manager\n- Smooth breathing, and the vine harvest is back\n- Shortcuts & help", dmg: nil, page: Update.releasesPage)
        let pages: [(String, AnyView, NSSize)] = [("help", AnyView(HelpView(m: m)), NSSize(width: 460, height: 520)),
                                                  ("update", AnyView(UpdateView(m: m, close: {})), NSSize(width: 440, height: 420)),
                                                  ("settings", AnyView(SettingsView(m: m)), NSSize(width: 420, height: 480))]
        for (name, view, size) in pages {
            for dark in [false, true] {
                let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let host = NSHostingView(rootView: view.ignoresSafeArea()); host.sizingOptions = []
                w.contentView = host; Chrome.style(w); host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}

extension Render {
    /// `Pomodoro --dmg-background <out prefix>`: the installer window's background (640 x 420 pt, 1x and 2x):
    /// app on the left, Applications on the right, a tomato arrow between, and the first-open step.
    @MainActor static func dmgBackground(to prefix: String) {
        let v = ZStack {
            Color(hex: 0xFBF7F2)
            VStack(spacing: 6) {
                Text("Drag Pomodoro to Applications").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0x2B1A17))
                Text("Then open it from Applications").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Color(hex: 0x6B5B54))
            }.frame(maxHeight: .infinity, alignment: .top).padding(.top, 34)
            Canvas { ctx, _ in
                var arrow = Path(); arrow.move(to: CGPoint(x: 250, y: 220)); arrow.addQuadCurve(to: CGPoint(x: 384, y: 220), control: CGPoint(x: 317, y: 182))
                ctx.stroke(arrow, with: .color(Color(hex: 0xE8392B)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 11]))
                var head = Path(); head.move(to: CGPoint(x: 372, y: 206)); head.addLine(to: CGPoint(x: 390, y: 222)); head.addLine(to: CGPoint(x: 368, y: 230))
                ctx.stroke(head, with: .color(Color(hex: 0xE8392B)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            Text("First time only: if macOS says it can't check the app, open System Settings › Privacy & Security and click Open Anyway.")
                .font(.system(size: 11.5, weight: .medium, design: .rounded)).foregroundStyle(Color(hex: 0x6B5B54))
                .multilineTextAlignment(.center).frame(width: 470).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 26)
        }.frame(width: 640, height: 420)
        for scale in [1.0, 2.0] {
            let r = ImageRenderer(content: v); r.scale = scale
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [.compressionFactor: 1]) {
                try? png.write(to: URL(fileURLWithPath: prefix + (scale == 2 ? "@2x.png" : ".png")))
            }
        }
    }
}
