import AppKit
import SwiftUI
import PomodoroCore

/// Notify, then install on one click (24 Oct: "can it not auto install? like when i click on get the new version").
/// Never silent: nothing changes until the person clicks, and the new app must carry this app's own code signature
/// (same identifier, same certificate) before it replaces anything; otherwise it falls back to the drag step.
@MainActor enum Updater {
    static let enabledKey = "checkForUpdates", lastKey = "lastUpdateCheck"
    /// On unless turned off in Settings.
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var current: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }

    static func fetch() async -> Update.Outcome {
        guard let current else { return .failed("This copy has no version number (a development build).") }
        var r = URLRequest(url: Update.latestURL, timeoutInterval: 15)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: r)
            return Update.outcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data, current: current)
        } catch {
            return .failed("Pomodoro could not reach GitHub. Check the internet connection and try again.")
        }
    }

    /// At launch: at most once a day, quietly; a newer version shows the sprout beside Tomo.
    static func atLaunch(_ m: Model) {
        let d = UserDefaults.standard
        guard enabled, Update.due(last: d.object(forKey: lastKey) as? Date, now: Date()) else { return }
        d.set(Date(), forKey: lastKey)
        Task { await check(m, manual: false) }
    }

    /// By hand (menu or Settings): always says what it found.
    static func check(_ m: Model, manual: Bool) async {
        switch await fetch() {
        case .newer(let r):
            m.update = r
            if manual { m.showUpdate?() }
        case .upToDate:
            m.update = nil
            if manual { m.say("You have the newest Pomodoro, \(current ?? "").", for: 5) }
        case .failed(let why):
            if manual { m.say(why, for: 6) }
        }
    }

    /// Set while an install is quitting the app, so the mid-session "Quit Pomodoro?" question is skipped.
    static var installing = false

    /// One click: download, verify, then a helper swaps the app in place once Pomodoro quits and opens the new one.
    /// Returns why it could not, so the card can fall back to the manual steps.
    static func install(_ r: Update.Release) async -> String? {
        guard let src = r.dmg else { return "This release has no disk image." }
        let here = Bundle.main.bundleURL, parent = here.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else { return "Pomodoro can't write to \(parent.path)." }
        guard let (tmp, response) = try? await URLSession.shared.download(from: src), (response as? HTTPURLResponse)?.statusCode == 200 else {
            return "The download didn't work."
        }
        return await Task.detached { () -> String? in
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("pomodoro-update-\(UUID().uuidString)")
            let mount = work.appendingPathComponent("mnt"), staged = work.appendingPathComponent("Pomodoro.app")
            try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, tmp.path]).ok else { return "The disk image wouldn't open." }
            defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
            let new = mount.appendingPathComponent("Pomodoro.app")
            // genuine: the new app must satisfy this app's own designated requirement (identifier + certificate)
            let dr = run("/usr/bin/codesign", ["-d", "-r-", here.path]).out
                .components(separatedBy: "\n").first { $0.hasPrefix("designated => ") }?.replacingOccurrences(of: "designated => ", with: "")
            guard let dr, !dr.contains("cdhash") else { return "This copy isn't signed in a way updates can be checked against." }
            guard run("/usr/bin/codesign", ["--verify", "--strict", "--deep", "-R=\(dr)", new.path]).ok else { return "The download isn't signed like this app, so it wasn't installed." }
            guard run("/usr/bin/ditto", [new.path, staged.path]).ok else { return "Copying the new version failed." }
            // the helper outlives this process: wait for it to quit, swap (old kept until the new is in), reopen
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "$1.old" && mv "$1" "$1.old" && /usr/bin/ditto "$2" "$1" && rm -rf "$1.old" || { rm -rf "$1"; mv "$1.old" "$1"; }
            rm -rf "$3"; /usr/bin/open "$1"
            """
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", script, "sh", here.path, staged.path, work.path]
            do { try p.run() } catch { return "The installer couldn't start." }
            return nil
        }.value
    }

    nonisolated static func run(_ tool: String, _ args: [String]) -> (ok: Bool, out: String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: tool); p.arguments = args; p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return (false, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }

    /// Fallback: downloads the disk image to Downloads and opens it at the drag-to-Applications step.
    static func download(_ r: Update.Release) async -> URL? {
        guard let src = r.dmg,
              let (tmp, response) = try? await URLSession.shared.download(from: src),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let dest = downloads.appendingPathComponent("Pomodoro-\(r.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil else { return nil }
        NSWorkspace.shared.open(dest)
        return dest
    }
}

/// The card the sprout opens: what's new, how to install, one button.
struct UpdateView: View {
    @ObservedObject var m: Model
    var close: () -> Void
    @State var stage = Stage.ready
    enum Stage: Equatable { case ready, installing, manual(String), opened(String), failed }

    var body: some View {
        VStack(alignment: .leading, spacing: T.s4) {
            if let r = m.update {
                HStack(alignment: .center, spacing: T.s3) {
                    Text("🌱").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pomodoro \(r.version) is ripe").font(T.title()).foregroundStyle(T.ink)
                        Text("You have \(Updater.current ?? "an older version").").font(T.callout()).foregroundStyle(T.ink2)
                    }
                }
                .padding(.top, 36)
                if !r.notes.isEmpty {
                    Card {
                        ScrollView {
                            ReleaseNotes(text: r.notes).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 180)
                    }
                }
                Text("Install downloads it, checks it's signed exactly like this copy, swaps it in and reopens Pomodoro in a few seconds. Your sessions, profiles and ideas stay; they live outside the app.")
                    .font(T.callout()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                switch stage {
                case .manual(let why):
                    VStack(alignment: .leading, spacing: T.s1 + 2) {
                        Text("\(why) Install it by hand instead:").font(T.callout()).foregroundStyle(T.tomato).fixedSize(horizontal: false, vertical: true)
                        step(1, "Download the disk image (the button below opens it).")
                        step(2, "Quit Pomodoro (⌘Q), drag Pomodoro onto Applications and choose Replace.")
                        step(3, "Open Pomodoro from Applications.")
                    }
                case .opened(let path):
                    Text("Opened \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Drag Pomodoro onto Applications.")
                        .font(T.callout()).foregroundStyle(T.leaf).fixedSize(horizontal: false, vertical: true)
                case .failed:
                    Text("The download didn't work, so the release page is open in your browser instead.")
                        .font(T.callout()).foregroundStyle(T.tomato).fixedSize(horizontal: false, vertical: true)
                default: EmptyView()
                }
                Spacer(minLength: 0)
                HStack(spacing: T.s2) {
                    PButton(title: "Later", kind: .ghost) { close() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if case .manual = stage {
                        PButton(title: "Download the disk image", symbol: "arrow.down.circle.fill", kind: .primary) { get(r) }.keyboardShortcut(.defaultAction)
                    } else {
                        PButton(title: stage == .installing ? "Installing…" : "Install and restart", symbol: "arrow.down.circle.fill", kind: .primary) { install(r) }
                            .keyboardShortcut(.defaultAction).disabled(stage == .installing)
                    }
                }
            } else {
                Text("Pomodoro is up to date.").font(T.title()).foregroundStyle(T.ink).padding(.top, 36)
                Spacer()
            }
        }
        .padding(.horizontal, T.s5).padding(.bottom, T.s5)
        .frame(minWidth: 440, minHeight: 420)
        .background(T.paper)
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: T.s2) {
            Text("\(n)").font(T.caption()).fontWeight(.bold).foregroundStyle(T.onTomato).frame(width: 18, height: 18).background(Circle().fill(T.tomato))
            Text(text).font(T.callout()).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    func install(_ r: Update.Release) {
        stage = .installing
        Task {
            if let why = await Updater.install(r) { stage = .manual(why) }
            else { Updater.installing = true; NSApp.terminate(nil) }
        }
    }

    func get(_ r: Update.Release) {
        stage = .installing
        Task {
            if let url = await Updater.download(r) { stage = .opened(url.path) }
            else { stage = .failed; NSWorkspace.shared.open(r.page) }
        }
    }
}

/// GitHub release notes, line by line: headings, bullets and inline bold or code. (Inline-only parsing showed
/// "### New" as typed, found in the 0.5.2 update test.)
struct ReleaseNotes: View {
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#") {
                    Text(md(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))).font(T.headline()).foregroundStyle(T.ink).padding(.top, 4)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(T.tomato).frame(width: 4, height: 4).offset(y: -2)
                        Text(md(String(line.dropFirst(2)))).font(T.callout()).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
                    }
                } else if !line.isEmpty {
                    Text(md(line)).font(T.callout()).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    func md(_ s: String) -> AttributedString { (try? AttributedString(markdown: s)) ?? AttributedString(s) }
}
