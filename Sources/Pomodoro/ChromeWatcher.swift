import AppKit
import NaturalLanguage
import PomodoroCore

/// The Chrome topic watcher (DESIGN.md section 10, D11): reads the front tab's address and title through
/// Chrome's AppleScript (macOS asks the user once for Automation permission), then rules, then Apple's on-device
/// sentence model. Nothing leaves the Mac. Runs every 2 s, only while Chrome is in front during a session
/// where Chrome is allowed.
@MainActor final class ChromeWatcher {
    /// The session's task; nil switches the watcher off.
    var task: String? { didSet { if task == nil { verdict = .unsure } } }
    var app: FocusApp = .other
    private(set) var verdict = TopicRules.Verdict.unsure
    private(set) var lastPage = ""
    private(set) var needsPermission = false
    private let queue = DispatchQueue(label: "chrome-watcher")
    private nonisolated(unsafe) let script = NSAppleScript(source: "tell application \"Google Chrome\" to if (count of windows) > 0 then return (URL of active tab of front window) & \"\\n\" & (title of active tab of front window)")
    private nonisolated(unsafe) let embedding = NLEmbedding.sentenceEmbedding(for: .english)
    private var busy = false

    init() {
        RunLoop.main.add(Timer(timeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { self.poll() } }, forMode: .common)
    }

    private func poll() {
        guard let task, !busy, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else { return }
        busy = true
        let app = self.app
        nonisolated(unsafe) let script = self.script, embedding = self.embedding
        queue.async {
            var err: NSDictionary?
            let out = script?.executeAndReturnError(&err).stringValue
            let denied = (err?[NSAppleScript.errorNumber] as? Int) == -1743
            var v = TopicRules.Verdict.unsure
            var page = ""
            if let out {
                let parts = out.split(separator: "\n", maxSplits: 1).map(String.init)
                let url = parts.first ?? "", title = parts.count > 1 ? parts[1] : ""
                page = title.isEmpty ? url : title
                v = TopicRules.judge(url: url, app: app)
                if v == .unsure || v == .titleDecides {
                    // Tier 2: meaning distance between the task and the page (search words count as the title).
                    let words = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "q" })?.value ?? title
                    let dist = embedding?.distance(between: task, and: words) ?? 1
                    // Measured 23 Oct: on-topic pages 0.82 to 0.84, off-topic 0.99 to 1.26.
                    v = dist < 0.92 ? .onTopic : (dist > 1.02 || v == .titleDecides) ? .offTopic : .unsure
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.busy = false
                    self.needsPermission = denied
                    if self.task != nil { self.verdict = v; self.lastPage = page }
                }
            }
        }
    }
}
