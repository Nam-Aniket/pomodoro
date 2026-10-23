import Foundation

/// Decides which app may come to the front during a session. Hiding is the only action; nothing is ever quit.
public enum Policy {
    /// Never hidden, whatever the session (safety rules): Claude runs his background sessions, the rest are
    /// the ways out of any trap. Non-regular processes (login window, lock screen, password prompts,
    /// Notification Centre, menu bar agents) never reach this check at all.
    public static let safety: Set<String> = [
        "com.anthropic.claudefordesktop", "com.apple.Terminal", "com.apple.finder",
        "com.apple.systempreferences", "com.apple.FaceTime", "com.apple.ActivityMonitor",
        "com.apple.loginwindow", "com.apple.SecurityAgent",
    ]

    /// Extra apps each session allows (DESIGN.md section 5). Google search lives in Tomo's own window.
    public static let extras: [FocusApp: Set<String>] = [
        .speakFit: [],
        .hackerSolve: [],
        .northstar: ["com.google.Chrome", "com.apple.Preview", "com.anthropic.claudefordesktop"],
        .other: ["com.google.Chrome", "com.apple.Preview"],
    ]

    /// Example presets: the three apps Pomodoro was first built around. Profiles for any app replace these in 0.4.
    public static func focusApp(bundleID: String?) -> FocusApp? {
        switch bundleID {
        case "com.aniketnamjoshi.speakfit": .speakFit
        case "com.aniket.northstar.viewer": .northstar
        case let id? where id == "com.aniketnamjoshi.hackersolve" || id.hasPrefix("com.aniketnamjoshi.hackersolve."): .hackerSolve
        default: nil
        }
    }

    /// Blocking runs through focus and the break (D3) and stops when paused, ready or idle.
    public static func isGuarding(_ s: DayState) -> Bool { s.isTimed && !s.isPaused }

    public static func mayFront(bundleID: String?, bundlePath: String?, isRegular: Bool, isSelf: Bool, session: FocusApp?) -> Bool {
        if isSelf || !isRegular { return true }
        guard let id = bundleID else { return true }   // ponytail: an app with no bundle id is too odd to touch
        if safety.contains(id) { return true }
        if bundlePath?.hasPrefix("/System/Library/CoreServices/") == true { return true }
        guard let session else { return true }
        // Any study app may come forward: switching tasks moves the session (23 Oct incident: 0.1.0 hid
        // SpeakFit four times while the user tried to open it).
        if focusApp(bundleID: id) != nil { return true }
        return extras[session, default: []].contains(id)
    }

    /// Whether time in the front app counts as working on the session's task (the active clock).
    /// Allowed is not the same as on task: Finder or Terminal stay reachable but do not fill the tomato.
    public static func onTask(bundleID: String?, isSelf: Bool, session: FocusApp?) -> Bool {
        guard let session else { return false }
        if isSelf { return true }                       // Tomo's own search window
        guard let id = bundleID else { return false }
        if focusApp(bundleID: id) == session { return true }
        return extras[session, default: []].contains(id)
    }
}

/// One `com.aniket.focus` distributed notification (DESIGN.md section 7).
public struct FocusEvent: Equatable, Sendable {
    /// v2 adds `activity`: posted on real work (slide advance, answer, recording start or stop, edit, save),
    /// at most about once every 30 s per app. v1 posters keep working unchanged.
    public enum Kind: String, Sendable { case start, end, activity }
    public let app: FocusApp
    public let phase: Kind
    public let task: String
    public let extras: [String: String]

    public static let name = "com.aniket.focus"

    public init?(userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo,
              let app = (info["app"] as? String).flatMap(FocusApp.init(rawValue:)),
              let phase = (info["phase"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
        self.app = app; self.phase = phase
        task = (info["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var x: [String: String] = [:]
        for (k, v) in info { if let k = k as? String, !["app", "phase", "task", "at"].contains(k), let v = v as? String { x[k] = v } }
        extras = x
    }
}

/// The search window shows Google's results page and nothing else (D2).
public enum SearchRules {
    static let hosts: Set<String> = ["google.com", "www.google.com", "google.com.au", "www.google.com.au"]
    static let paths: Set<String> = ["/", "/search", "/webhp", "/sorry/index"]

    public static func allows(_ url: URL?, isMainFrame: Bool) -> Bool {
        guard isMainFrame else { return true }          // iframes (consent, captcha) belong to the allowed page
        guard let url else { return false }
        if url.absoluteString == "about:blank" { return true }
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        if host == "consent.google.com" || host == "consent.google.com.au" { return true }
        return hosts.contains(host) && paths.contains(url.path.isEmpty ? "/" : url.path)
    }

    public static func searchURL(_ query: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return c.url
    }
}

/// Ideas noticed mid-session, all in one inbox file; each line names the app and task so the
/// coordinating chat can route it to the right place later.
public struct ParkingLot: Sendable {
    public let file: URL
    /// The inbox file: the `ideasInboxPath` setting, or ~/Documents/Pomodoro/ideas-inbox.md.
    public init(file: URL = UserDefaults.standard.string(forKey: "ideasInboxPath").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pomodoro/ideas-inbox.md")) { self.file = file }

    @discardableResult
    public func park(_ idea: String, app: FocusApp?, task: String?, now: Date) throws -> URL {
        let text = idea.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !text.isEmpty else { return file }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_AU_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
        let where_ = [app?.rawValue ?? "General", task.flatMap { $0.isEmpty ? nil : $0 }].compactMap { $0 }.joined(separator: " · ")
        let line = "- [ ] \(f.string(from: now)) · \(where_): \(text)\n"
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try h.close()
        } else {
            let head = "# Ideas inbox\n\nIdeas parked during focus sessions, newest last. Each line: time · app · task: idea. Tick one when it is handled.\n\n"
            try Data((head + line).utf8).write(to: file)
        }
        return file
    }
}

/// Tier 1 of the Chrome watcher (DESIGN.md section 10, D11): instant rules on the tab's address.
/// Anything the rules cannot settle goes to the on-device meaning check.
public enum TopicRules {
    public enum Verdict: String, Sendable { case onTopic, offTopic, unsure, titleDecides }

    static let off = ["instagram.com", "facebook.com", "x.com", "twitter.com", "reddit.com", "netflix.com", "tiktok.com",
                      "primevideo.com", "hotstar.com", "disneyplus.com", "cricbuzz.com", "espncricinfo.com", "9gag.com",
                      "twitch.tv", "discord.com", "web.whatsapp.com", "amazon.com", "amazon.com.au", "ebay.com", "ebay.com.au",
                      "linkedin.com/feed", "news.google.com", "news.yahoo.com"]
    static let on: [FocusApp: [String]] = [
        .northstar: ["seek.com.au", "linkedin.com/jobs", "indeed.com", "greenhouse.io", "lever.co", "myworkdayjobs.com", "workday.com",
                     "smartrecruiters.com", "ashbyhq.com", "glassdoor.com", "jora.com", "docs.google.com", "mail.google.com", "claude.ai"],
        .other: ["claude.ai", "docs.google.com"],
    ]
    /// Video sites can be a tutorial or a distraction: the title decides.
    static let titleDecides = ["youtube.com", "youtu.be", "vimeo.com"]

    public static func judge(url: String, app: FocusApp) -> Verdict {
        guard let u = URL(string: url), let host = u.host?.lowercased() else { return .unsure }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let hp = h + u.path.lowercased()
        func matches(_ list: [String]) -> Bool { list.contains { hp == $0 || hp.hasPrefix($0) || h.hasSuffix("." + $0) || h == $0 } }
        if matches(on[app] ?? []) { return .onTopic }
        if matches(off) { return .offTopic }
        if matches(titleDecides) { return .titleDecides }
        if url.hasPrefix("chrome://") || url.hasPrefix("about:") { return .onTopic }   // a new tab, settings
        return .unsure
    }
}
