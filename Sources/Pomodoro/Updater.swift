import AppKit
import SwiftUI
import PomodoroCore

/// Notify and download, never a silent replace: the app is not notarised, so macOS would rightly distrust a copy
/// that swaps itself (24 Oct: "notify-and-download, not silent installs").
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

    /// Downloads the disk image to Downloads and opens it at the drag-to-Applications step.
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
    enum Stage: Equatable { case ready, downloading, opened(String), failed }

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
                VStack(alignment: .leading, spacing: T.s1 + 2) {
                    step(1, "Get the new version: the disk image downloads and opens.")
                    step(2, "Drag Pomodoro onto Applications, and choose Replace.")
                    step(3, "Open it again. Your sessions, profiles and ideas stay; they live outside the app.")
                }
                switch stage {
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
                    PButton(title: stage == .downloading ? "Downloading…" : "Get the new version", symbol: "arrow.down.circle.fill", kind: .primary) { get(r) }
                        .keyboardShortcut(.defaultAction).disabled(stage == .downloading)
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

    func get(_ r: Update.Release) {
        stage = .downloading
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
