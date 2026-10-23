import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.sheet(dark: args[i + 1] == "dark", to: URL(fileURLWithPath: args[i + 2])) }
    exit(0)
}
if let i = args.firstIndex(of: "--perf") {
    let secs = i + 1 < args.count ? Double(args[i + 1]) ?? 10 : 10
    MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.accessory); Render.perf(seconds: secs) }
}
if let i = args.firstIndex(of: "--dmg-background"), i + 1 < args.count {
    MainActor.assumeIsolated { Render.dmgBackground(to: args[i + 1]) }
    exit(0)
}
if let i = args.firstIndex(of: "--pages"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.pages(dir: args[i + 1], to: args[i + 2]) }
    exit(0)
}
if let i = args.firstIndex(of: "--profiles"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.profiles(dir: args[i + 1], to: args[i + 2]) }
    exit(0)
}
if let i = args.firstIndex(of: "--launcher"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.launcher(dir: args[i + 1], to: URL(fileURLWithPath: args[i + 2])) }
    exit(0)
}
if let i = args.firstIndex(of: "--reels"), i + 1 < args.count {
    Sound.reels(to: URL(fileURLWithPath: args[i + 1]))
    exit(0)
}
if let i = args.firstIndex(of: "--eaten"), i + 1 < args.count {
    MainActor.assumeIsolated { Render.eaten(to: URL(fileURLWithPath: args[i + 1])) }
    exit(0)
}
if let i = args.firstIndex(of: "--insights"), i + 3 < args.count {
    MainActor.assumeIsolated { Render.insights(dir: URL(fileURLWithPath: args[i + 1]), range: args[i + 2], to: URL(fileURLWithPath: args[i + 3])) }
    exit(0)
}
if let i = args.firstIndex(of: "--frames"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.frames(args[i + 1], to: URL(fileURLWithPath: args[i + 2])) }
    exit(0)
}
if let i = args.firstIndex(of: "--face"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.face(dark: args[i + 1] == "dark", to: URL(fileURLWithPath: args[i + 2])) }
    exit(0)
}
if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
    MainActor.assumeIsolated { Render.icon(to: URL(fileURLWithPath: args[i + 1])) }
    exit(0)
}
// `--sounds <dir>` writes every sound, three takes each (every take differs), for a listen.
// Update test: this copy installs the latest release over itself (run a copy in a temp folder, labelled older).
if args.contains("--update-test") {
    Task { @MainActor in
        guard case .newer(let r) = await Updater.fetch() else { print("update-test: no newer release"); exit(2) }
        let why = await Updater.install(r)
        print(why.map { "update-test: fell back: \($0)" } ?? "update-test: installing \(r.version) over \(Bundle.main.bundlePath)")
        exit(why == nil ? 0 : 1)
    }
    RunLoop.main.run()
}

// Regression check: every sound in every palette, 20 random seeds each. A buffer overrun traps, so reaching the
// end is the pass (the breath sounds crashed every breathing break until 0.5.3).
if args.contains("--sound-check") {
    var n = 0
    for c in Sound.Cue.allCases {
        for p in Sound.Palette.allCases { for _ in 0..<20 { _ = Sound.render(c, palette: p, seed: .random(in: 1...UInt64.max)); n += 1 } }
        for _ in 0..<20 { _ = Sound.render(c, seed: .random(in: 1...UInt64.max)); n += 1 }
    }
    for p in Sound.Presence.allCases { for _ in 0..<20 { _ = Sound.render(p, seed: .random(in: 1...UInt64.max)); n += 1 } }
    print("sound-check: \(n) renders, all passed"); exit(0)
}
if let i = args.firstIndex(of: "--sounds"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1])
    for c in Sound.Cue.allCases { for k in 1...3 { try? Sound.wav(Sound.render(c, seed: UInt64(k * 7919))).write(to: dir.appendingPathComponent("new-\(c.rawValue)-\(k).wav")) } }
    for p in Sound.Presence.allCases { for k in 1...3 { try? Sound.wav(Sound.render(p, seed: UInt64(k * 104729))).write(to: dir.appendingPathComponent("presence-\(p.rawValue)-\(k).wav")) } }
    exit(0)
}

// One copy only: two copies would both write state.json and count sessions twice (23 Oct incident).
// A second launch fronts the running copy and exits.
if let id = Bundle.main.bundleIdentifier,
   let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    other.activate()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu bar + floating Tomo, no Dock icon
    app.run()
}
