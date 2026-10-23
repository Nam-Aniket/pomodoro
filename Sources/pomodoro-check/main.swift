import Foundation
import PomodoroCore

// Assertion runner for PomodoroCore. `swift run pomodoro-check` exits 1 on any failure.
nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

let cal = Calendar.current
func at(_ h: Int, _ m: Int = 0, _ s: Int = 0, day: Int = 23) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m, second: s))!
}
let d = Durations()

/// Runs the clock second by second; `working` decides which seconds count.
func run(_ s: inout DayState, from t0: Date, seconds n: Int, working: (Int) -> Bool = { _ in true }, _ d: Durations) -> [ScheduleEvent] {
    var ev: [ScheduleEvent] = []
    for i in 1...max(1, n) { ev += s.tick(now: t0.addingTimeInterval(Double(i)), active: working(i), d) }
    return ev
}

// Arming: opening an app does not start the clock; a task start does (23 Oct rule).
do {
    var s = DayState(day: DayState.dayKey(at(9)))
    s.arm(app: "NorthstarViewer")
    check(s.phase == .armed && s.app == "NorthstarViewer", "app open arms Tomo")
    check(run(&s, from: at(9), seconds: 600, d).isEmpty && s.dayActive == 0, "armed: no time counts")
    check(s.startFocus(app: "NorthstarViewer", task: "Reviewing a job posting", now: at(9, 10), d), "task start begins the clock")
    check(!s.startFocus(app: "SpeakFit", task: nil, now: at(9, 11), d), "no second session on top of a running one")
}

// Only active seconds count, a 45-minute session needs 45 ACTIVE minutes, harvest fills by minutes.
do {
    var s = DayState(day: DayState.dayKey(at(9)))
    s.startFocus(app: "HackerSolve", task: "Lesson 4", now: at(9), d)
    _ = run(&s, from: at(9), seconds: 1200, working: { $0 % 2 == 0 }, d)      // half the seconds idle
    check(abs(s.active - 600) < 1 && abs(s.elapsed - 1200) < 1, "20 min wall, 10 min active (got \(s.active))")
    check(abs(s.progress(d) - 600.0 / 2700) < 0.001, "progress by active time")
    let t1 = at(9, 20)
    let ev = run(&s, from: t1, seconds: 2100, d)                               // 35 more active minutes
    check(ev.first == .focusEnded(count: 1) && s.phase == .breakTime, "ends at 45 active minutes, not 45 wall minutes")
    check(abs(s.harvest(d) - 1) < 0.01, "one full tomato")
    check(d.rest(after: 2700) == 600 && d.rest(after: 1800) == 420 && d.rest(after: 600) == 180, "breaks scale: 10, 7, min 3")
    _ = run(&s, from: at(10), seconds: 600, d)
    check(s.phase == .ready, "break ends into ready, waits for a tap")
}

// A 30-minute session fills two-thirds of a tomato; 5/5 fires only at 225 active minutes.
do {
    var s = DayState(day: DayState.dayKey(at(9)))
    s.startFocus(app: "SpeakFit", task: "Practice", target: 1800, now: at(9), d)
    _ = run(&s, from: at(9), seconds: 1800, d)
    check(abs(s.harvest(d) - 2.0 / 3) < 0.01, "30 min = 2/3 tomato")
    var all: [ScheduleEvent] = []
    var t = at(10)
    while s.dayActive < d.dayGoal - 1 {
        _ = run(&s, from: t, seconds: Int(s.rest(d)) + 1, d)                 // finish the break
        t = t.addingTimeInterval(s.rest(d) + 1)
        s.startFocus(app: "HackerSolve", task: "L", target: 1800, now: t, d)
        all += run(&s, from: t, seconds: 1800, d)
        t = t.addingTimeInterval(1800)
    }
    check(all.filter { $0 == .dayDone }.count == 1 && s.celebrated, "5/5 fires once, at 225 active minutes")
    check(s.harvest(d) == 5, "crate full")
}

// Pause and resume to the second, quit and reload, crash = paused, a sleep gap never counts as work.
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pomodoro-check-\(UUID())")
    let store = Store(root: dir)
    var s = DayState(day: DayState.dayKey(at(10)))
    s.startFocus(app: "SpeakFit", task: "Day 12 plan", now: at(10), d)
    _ = run(&s, from: at(10), seconds: 754, d)
    s.pause(now: at(10, 12, 34))
    check(s.isPaused && Int(s.active.rounded()) == 754, "paused at 12:34")
    _ = s.tick(now: at(11), active: true, d)
    check(Int(s.active.rounded()) == 754, "no time while paused")
    store.save(s, now: at(11))
    var r = store.load(now: at(11, 30))
    check(r.isPaused && Int(r.active.rounded()) == 754 && r.task == "Day 12 plan", "reload keeps 12:34")
    r.resume(now: at(12))
    _ = run(&r, from: at(12), seconds: 10, d)
    check(Int(r.active.rounded()) == 764, "resume counts on from 12:34")
    _ = r.tick(now: at(12, 30), active: true, d)                              // a 30-minute jump (sleep)
    check(Int(r.active.rounded()) == 764, "a long gap never counts as work")
    var c = DayState(day: DayState.dayKey(at(13)))
    c.startFocus(app: "NorthstarViewer", task: nil, now: at(13), d)
    _ = run(&c, from: at(13), seconds: 300, d)
    store.save(c, now: at(13, 5))
    let back = store.load(now: at(14))
    check(back.isPaused && Int(back.active.rounded()) == 300, "crash = paused at last save")
    check(store.load(now: at(10, day: 24)).phase == .idle, "next day starts fresh")
    try? Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
    check(store.load(now: at(10)).phase == .idle, "corrupt state starts fresh")
    check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state.json.bad").path), "corrupt file kept")
    try? FileManager.default.removeItem(at: dir)
}

// An 0.2 state file (no active clock) loads, mid-session, without losing the day.
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("old-\(UUID())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let old = #"{"app":"HackerSolve","day":"\#(DayState.dayKey(at(9)))","done":1,"elapsed":949.2,"focusStartedAt":"2026-10-23T03:31:24Z","phase":"focus","task":"Lesson 4","tasks":["Lesson 3"]}"#
    try? Data(old.utf8).write(to: dir.appendingPathComponent("state.json"))
    let s = Store(root: dir).load(now: at(9, 30))
    check(s.phase == .focus && s.isPaused && Int(s.active) == 949 && s.done == 1 && Int(s.dayActive) == 2700 + 949 && s.tasks == ["Lesson 3"], "0.2 state carries over, paused")
    try? FileManager.default.removeItem(at: dir)
}

// Day boundary is 4:00; emergency stop keeps the minutes; rollover resets.
do {
    check(DayState.dayKey(at(3, 59, day: 24)) == "2026-10-23", "3:59 belongs to the day before")
    check(DayState.dayKey(at(4, 0, day: 24)) == "2026-10-24", "4:00 starts a new day")
    var s = DayState(day: "2026-10-23")
    s.startFocus(app: "HackerSolve", task: nil, now: at(20), d)
    _ = run(&s, from: at(20), seconds: 120, d)
    s.stop(d)
    check(s.phase == .idle && Int(s.dayActive.rounded()) == 120, "emergency stop keeps worked minutes")
    check(s.tick(now: at(4, 1, day: 24), active: true, d) == [.newDay] && s.dayActive == 0, "rollover resets the day")
}

// Switching study apps mid-session moves the session, never restarts the clock.
do {
    var s = DayState(day: DayState.dayKey(at(9)))
    s.startFocus(app: "HackerSolve", task: "Lesson 4", now: at(9), d)
    _ = run(&s, from: at(9), seconds: 60, d)
    s.retag(app: "SpeakFit", task: "Day 12 plan", taskId: nil)
    check(s.app == "SpeakFit" && s.task == "Day 12 plan" && Int(s.active.rounded()) == 60, "retag keeps the clock")
}

// The anger ladder (D12 strict, D13 siren) and the not-working rule.
do {
    typealias L = Ladder
    check(L.stage(.offTask, seconds: 5) == .calm && L.stage(.offTask, seconds: 15) == .nudge, "10 s grace, then a nudge")
    check(L.stage(.offTask, seconds: 45) == .hmmph && L.stage(.offTask, seconds: 75) == .simmer, "hmmph 30 s, simmer 1 min")
    check(L.stage(.offTask, seconds: 100) == .boil && L.stage(.offTask, seconds: 160) == .siren, "boil 90 s, siren 2.5 min")
    check(L.stage(.notWorking, seconds: 0) == .hmmph && L.stage(.notWorking, seconds: 200) == .boil && L.stage(.notWorking, seconds: 400) == .siren, "not working: hmmph, boil +3, siren +6")
    check(L.isWorking(inputIdle: 30, sinceProgress: 600), "typing counts as working")
    check(L.isWorking(inputIdle: 120, sinceProgress: 60), "a recent slide change counts while reading")
    check(!L.isWorking(inputIdle: 120, sinceProgress: 400), "no input 60 s and no progress 3 min = not working")
    check(L.isWorking(inputIdle: 150, sinceProgress: nil) && !L.isWorking(inputIdle: 200, sinceProgress: nil), "no-progress apps judged on input, 3 min")
}

// Policy, profile-based: allowlists, the safety list, contract apps never hidden, on task vs merely allowed,
// website profiles judged by the front tab's domain.
do {
    let hs = Profile.contractPresets[0], sf = Profile.contractPresets[1], ns = Profile.contractPresets[2]
    let contract = Profile.contractPresets.compactMap(\.appID)
    let gh = Profile(id: "gh", name: "GitHub", kind: .website, domains: ["github.com"], allowed: ["com.apple.Notes"])
    let code = Profile(id: "vs", name: "VS Code", kind: .app, appID: "com.microsoft.VSCode", allowed: ["com.google.Chrome"])
    func may(_ id: String, _ p: Profile?, path: String? = nil, regular: Bool = true, browser: Bool = false) -> Bool {
        Policy.mayFront(.init(bundleID: id, path: path, isRegular: regular, isBrowser: browser), profile: p, contractTargets: contract)
    }
    func on(_ id: String, _ p: Profile, browser: Bool = false, host: String? = nil) -> Bool {
        Policy.onTask(.init(bundleID: id, isBrowser: browser, host: host), profile: p)
    }
    check(!may("com.apple.Safari", sf), "Safari hidden in SpeakFit")
    check(!may("com.google.Chrome", sf) && !may("com.google.Chrome", hs), "Chrome hidden in SpeakFit and HackerSolve")
    check(may("com.google.Chrome", ns) && may("com.apple.Preview", ns), "Chrome and Preview in Northstar (D4)")
    check(may("com.google.Chrome", .other) && !may("com.apple.Notes", .other), "Other: browsers and Preview")
    check(may("com.aniketnamjoshi.speakfit", hs) && may("com.aniket.northstar.viewer", sf), "contract apps never hidden (23 Oct incident)")
    check(may("com.aniketnamjoshi.hackersolve.v111", sf), "copies of a contract app count")
    for id in ["com.anthropic.claudefordesktop", "com.apple.Terminal", "com.apple.finder", "com.apple.systempreferences", "com.apple.FaceTime"] {
        check(may(id, sf), "safety: \(id) never hidden")
    }
    check(may("com.apple.Notes", sf, regular: false), "non-regular processes untouched")
    check(may("com.apple.Installer", sf, path: "/System/Library/CoreServices/Installer.app"), "CoreServices untouched")
    check(may("com.apple.Notes", nil), "no session, nothing hidden")
    check(on("com.aniketnamjoshi.hackersolve", hs) && !on("com.apple.finder", hs), "Finder allowed but not on task")
    check(on("com.anthropic.claudefordesktop", ns) && !on("com.anthropic.claudefordesktop", hs), "Claude on task only for Northstar")
    check(Policy.onTask(.init(bundleID: nil, isSelf: true), profile: hs), "Tomo's own window is on task")
    // any app
    check(may("com.microsoft.VSCode", code) && may("com.google.Chrome", code) && !may("com.tinyspeck.slackmacgap", code), "app profile: target and allowed stay, Slack hidden")
    check(on("com.microsoft.VSCode", code) && on("com.google.Chrome", code), "app profile on task")
    // websites, any browser
    check(may("com.brave.Browser", gh, browser: true) && may("com.apple.Notes", gh) && !may("com.apple.Mail", gh), "website: any browser and allowed apps stay")
    check(on("com.apple.Safari", gh, browser: true, host: "github.com") && on("com.google.Chrome", gh, browser: true, host: "gist.github.com"), "github.com and subdomains on task")
    check(!on("com.google.Chrome", gh, browser: true, host: "www.youtube.com") && !on("com.google.Chrome", gh, browser: true, host: "github.io"), "other domains off task")
    var strict = gh; strict.includeSubdomains = false; strict.browsers = ["com.apple.Safari"]
    check(!on("com.apple.Safari", strict, browser: true, host: "gist.github.com") && !may("com.google.Chrome", strict, browser: true), "subdomain toggle and browser limit")
}

// Profiles store: presets only for installed contract apps, plus Other; saved profiles round-trip.
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID())")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ps = ProfileStore(root: dir)
    check(ps.load(installed: { _ in false }).map(\.id) == ["Other"], "fresh Mac: only Other")
    check(ps.load(installed: { $0 == "com.aniketnamjoshi.speakfit" }).map(\.id) == ["SpeakFit", "Other"], "installed contract app becomes a preset")
    let gh = Profile(id: "gh", name: "GitHub", kind: .website, domains: ["github.com"], minutes: 30)
    ps.save([gh, .other])
    check(ps.load(installed: { _ in true }) == [gh, .other], "saved profiles round-trip")
    try? FileManager.default.removeItem(at: dir)
}

// Chrome watcher rules (tier 1).
do {
    typealias T = TopicRules
    check(T.judge(url: "https://www.instagram.com/", app: "NorthstarViewer") == .offTopic, "Instagram off")
    check(T.judge(url: "https://www.seek.com.au/job/95441065", app: "NorthstarViewer") == .onTopic, "SEEK on for Northstar")
    check(T.judge(url: "https://www.seek.com.au/job/1", app: "Other") == .unsure, "SEEK not automatic for Other")
    check(T.judge(url: "https://www.linkedin.com/jobs/view/1", app: "NorthstarViewer") == .onTopic && T.judge(url: "https://www.linkedin.com/feed/", app: "NorthstarViewer") == .offTopic, "LinkedIn jobs on, feed off")
    check(T.judge(url: "https://canva.wd3.myworkdayjobs.com/x", app: "NorthstarViewer") == .onTopic, "Workday subdomain on")
    check(T.judge(url: "https://www.youtube.com/watch?v=1", app: "Other") == .titleDecides, "YouTube: the title decides")
    check(T.judge(url: "https://notx.com/", app: "Other") == .unsure, "look-alike host not matched")
    check(T.judge(url: "https://www.google.com/search?q=kafka", app: "Other") == .unsure, "searches go to the meaning check")
}

// SQLite session store.
do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("db-\(UUID()).sqlite")
    let db = SessionDB(url: url)
    db.add(.init(day: "2026-10-23", app: "HackerSolve", task: "Lesson 4, \"intro\"", start: at(9), end: at(9, 50), active: 2700, elapsed: 3000, idle: 200, offTask: 100, completed: true))
    db.add(.init(day: "2026-10-24", app: "SpeakFit", task: "Day 13", start: at(9, day: 24), end: at(9, 30, day: 24), active: 1500, elapsed: 1800, completed: false))
    db.event("nudge", app: "HackerSolve", detail: "com.apple.Safari", at: at(9, 5))
    let rows = db.sessions(from: "2026-10-23", to: "2026-10-23")
    check(rows.count == 1 && rows[0].active == 2700 && rows[0].completed && rows[0].task == "Lesson 4, \"intro\"", "session round-trips")
    check(db.sessions(from: "2026-10-01", to: "2026-10-31").count == 2, "range query")
    let csv = db.csv()
    check(csv.contains("\"Lesson 4, \"\"intro\"\"\"") && csv.contains(",45.0,50.0,"), "CSV escapes quotes, minutes")
    try? FileManager.default.removeItem(at: url)
}

// The com.aniket.focus contract.
do {
    let e = FocusEvent(userInfo: ["app": "SpeakFit", "phase": "start", "task": " Day 12 plan: voice ", "at": "2026-10-23T10:00:00Z", "day": "12", "minutes": "15"])
    check(e?.app == "SpeakFit" && e?.phase == .start && e?.task == "Day 12 plan: voice", "parses SpeakFit start")
    check(e?.extras == ["day": "12", "minutes": "15"], "extras pass through")
    check(FocusEvent(userInfo: ["app": "NorthstarViewer", "phase": "end"])?.app == "NorthstarViewer", "Viewer end without task")
    check(FocusEvent(userInfo: ["app": "  ", "phase": "start"]) == nil, "blank app ignored")
    check(FocusEvent(userInfo: ["app": "MyEditor", "phase": "start", "task": "Chapter 3"])?.app == "MyEditor", "any app may post the contract")
    check(FocusEvent(userInfo: ["app": "SpeakFit", "phase": "open"]) == nil, "unknown phase ignored")
    let act = FocusEvent(userInfo: ["app": "HackerSolve", "phase": "activity", "task": "Lesson 4", "kind": "slide", "taskId": "l4"])
    check(act?.phase == .activity && act?.extras == ["kind": "slide", "taskId": "l4"], "v2 activity parses, taskId passes through")
    check(FocusEvent(userInfo: nil) == nil, "missing userInfo ignored")
}

// Search window: Google's results page only (D2).
do {
    func ok(_ s: String, main: Bool = true) -> Bool { SearchRules.allows(URL(string: s), isMainFrame: main) }
    check(ok("https://www.google.com/search?q=spark+partitioning"), "results page")
    check(ok("https://www.google.com.au/search?q=x&udm=50"), "AU results and AI mode")
    check(ok("https://consent.google.com/ml?continue=x"), "cookie consent")
    check(!ok("https://www.google.com/url?q=https://stackoverflow.com"), "result click redirect blocked")
    check(!ok("https://stackoverflow.com/questions/1"), "result page blocked")
    check(!ok("https://www.youtube.com/watch?v=1"), "YouTube blocked")
    check(!ok("https://maps.google.com/"), "other Google products blocked")
    check(!ok("http://www.google.com/search?q=x"), "plain http blocked")
    check(!ok("https://www.google.com.evil.com/search"), "look-alike host blocked")
    check(ok("https://www.recaptcha.net/x", main: false), "iframes left to the page")
    check(SearchRules.searchURL("a&b c")?.absoluteString == "https://www.google.com/search?q=a%26b%20c", "query is escaped")
}

// Ideas inbox: one file, header once, each line with time, app and task, newest last.
do {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lot-\(UUID())")
    let lot = ParkingLot(file: dir.appendingPathComponent("ideas-inbox.md"))
    _ = try? lot.park("Make the lesson diagram zoomable", app: "HackerSolve", task: "Lesson 4", now: at(14, 5))
    _ = try? lot.park("  second\nidea ", app: "SpeakFit", task: nil, now: at(14, 9))
    _ = try? lot.park("   ", app: "HackerSolve", task: nil, now: at(14, 9))
    _ = try? lot.park("general one", app: nil, task: "", now: at(14, 10))
    let text = (try? String(contentsOf: lot.file, encoding: .utf8)) ?? ""
    check(text.hasPrefix("# Ideas inbox"), "header written once")
    check(text.contains("- [ ] 2026-10-23 14:05 · HackerSolve · Lesson 4: Make the lesson diagram zoomable\n"), "line has time, app, task")
    check(text.contains("- [ ] 2026-10-23 14:09 · SpeakFit: second idea\n"), "newlines flattened, no task")
    check(text.hasSuffix("- [ ] 2026-10-23 14:10 · General: general one\n"), "no session goes to General, newest last")
    check(text.components(separatedBy: "- [ ]").count == 4, "blank idea ignored")
    try? FileManager.default.removeItem(at: dir)
}

// The 5-of-5 summary and the full-harvest record (a count, never a streak).
do {
    var s = DayState(day: DayState.dayKey(at(9)))
    let quick = Durations(focus: 10, dayGoal: 20, perDay: 2, restOverride: 5)
    s.startFocus(app: "HackerSolve", task: "Lesson 4", now: at(9), quick)
    _ = run(&s, from: at(9), seconds: 16, quick)
    s.startFocus(app: "SpeakFit", task: "", now: at(9, 1), quick)
    let ev = run(&s, from: at(9, 1), seconds: 10, quick)
    check(ev.contains(.dayDone) && s.tasks == ["Lesson 4", "SpeakFit"], "day keeps task titles, app name when blank")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harvest-\(UUID())")
    let store = Store(root: dir)
    check(store.recordFullHarvest(day: "2026-10-23") == 1 && store.recordFullHarvest(day: "2026-10-23") == 1, "same day counted once")
    check(store.recordFullHarvest(day: "2026-10-26") == 2, "a gap of days loses nothing")
    try? FileManager.default.removeItem(at: dir)
}

domainChecks()

print(failures == 0 ? "pomodoro-check: all passed" : "pomodoro-check: \(failures) failed")
exit(failures == 0 ? 0 : 1)
