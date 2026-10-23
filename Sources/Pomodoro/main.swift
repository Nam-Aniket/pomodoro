import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), i + 2 < args.count {
    MainActor.assumeIsolated { Render.sheet(dark: args[i + 1] == "dark", to: URL(fileURLWithPath: args[i + 2])) }
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
if let i = args.firstIndex(of: "--sounds"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1])
    for c in Sound.Cue.allCases { for k in 1...3 { try? Sound.wav(Sound.render(c, seed: UInt64(k * 7919))).write(to: dir.appendingPathComponent("new-\(c.rawValue)-\(k).wav")) } }
    for p in Sound.Presence.allCases { for k in 1...3 { try? Sound.wav(Sound.render(p, seed: UInt64(k * 104729))).write(to: dir.appendingPathComponent("presence-\(p.rawValue)-\(k).wav")) } }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu bar + floating Tomo, no Dock icon
    app.run()
}
