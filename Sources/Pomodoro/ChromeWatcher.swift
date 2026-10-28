import AppKit
import NaturalLanguage
import PomodoroCore

/// The tab watcher (DESIGN.md sections 10 and 14): reads the front browser tab's address and title in any
/// browser with full scripting support (Chrome, Safari, Brave, Edge, Arc, ...; macOS asks once per browser for
/// Automation permission), then applies rules and Apple's on-device sentence model. Nothing leaves the Mac.
/// Runs every 2 s, only while a browser is in front during a session or an armed website profile.
@MainActor final class ChromeWatcher {
    /// The session's task; nil switches the watcher off.
    var task: String? { didSet { if task == nil { verdict = .unsure; host = nil } } }
    var app = "Other"
    private(set) var verdict = TopicRules.Verdict.unsure
    private(set) var lastPage = ""
    /// The front tab's host, for website profiles.
    private(set) var host: String?
    /// Browsers that refused Automation (the user said no, or hasn't been asked yet).
    private(set) var denied: Set<String> = []
    private let reader = BrowserReader()
    private let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var busy = false

    init() {
        RunLoop.main.add(Timer(timeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { self.poll() } }, forMode: .common)
    }

    private func poll() {
        guard let task, !busy, let front = NSWorkspace.shared.frontmostApplication, let id = front.bundleIdentifier,
              Model.browserIDs.contains(id), let url = front.bundleURL, Browsers.tier(bundleID: id, url: url) == .full else { return }
        busy = true
        let app = self.app
        reader.read(bundleID: id) { url, title, denied in
            self.busy = false
            if denied { self.denied.insert(id) } else { self.denied.remove(id) }
            guard self.task != nil, let url else { return }
            var v = TopicRules.judge(url: url, app: app)
            if v == .unsure || v == .titleDecides {
                // the on-device meaning check: distance between the task and the page (search words count as the title)
                let words = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "q" })?.value ?? title ?? ""
                v = TopicRules.resolve(v, distance: self.embedding?.distance(between: task, and: words) ?? 1, task: task, url: url, title: title ?? "")
            }
            self.verdict = v; self.host = URL(string: url)?.host; self.lastPage = title ?? url
        }
    }
}
