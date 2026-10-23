import AppKit
import PomodoroCore

/// Glue between the pure day state (PomodoroCore) and the Mac: the once-a-second working check, the guard,
/// focus events, the anger ladder, gestures and bubbles.
@MainActor final class Model: ObservableObject {
    @Published var state: DayState
    @Published var bubble: String?
    @Published var hold: Double = 0
    @Published var hovering = false
    @Published var parking = false
    @Published var draft = ""
    /// What the text field under Tomo is collecting: an idea for the inbox, or an Other task to start.
    enum FieldMode { case idea, otherTask }
    @Published var fieldMode = FieldMode.idea
    @Published var stage = Ladder.Stage.calm
    /// Small while working well, full size when idle or off track (23 Oct: "auto shrink ... when focusing").
    @Published var compact = false
    @Published var frozen = false   // screen locked or Tomo hidden: no frames drawn at all

    let d = Durations.fromEnvironment()
    let store: Store
    let db: SessionDB
    let lot = ProcessInfo.processInfo.environment["POMODORO_LOT"].map { ParkingLot(file: URL(fileURLWithPath: $0)) } ?? ParkingLot()
    let watcher = ChromeWatcher()
    let launched = Date()
    enum Moment { case splash, entrance }
    var moment: (kind: Moment, at: Date)?
    var reaction: (kind: TomoScene.Reaction, at: Date) = (.none, .distantPast)
    private var look = CGVector.zero
    private var glanceUntil = Date.distantPast, nextGlance = Date().addingTimeInterval(25)
    private var nextBeat = Date().addingTimeInterval(20)
    private var nextPresence = Date().addingTimeInterval(.random(in: 40...90))
    private var nextSiren = Date.distantPast
    var lastActivity: [FocusApp: Date] = [:]
    var hideTomo: () -> Void = {}
    var nudgeUntil: Date?
    var bubbleUntil: Date?
    weak var panel: NSPanel?
    var onChange: () -> Void = {}
    private var lastSave = Date.distantPast
    private var hidden: Set<pid_t> = []
    private let me = ProcessInfo.processInfo.processIdentifier

    // the working check, refreshed each second
    private(set) var trouble = Ladder.Trouble.none
    private var troubleSince: Date?
    private var calmSince: Date?
    private(set) var working = true
    // the current segment (one task within a session), for the session store
    private var segStart: Date?
    private var segActive: Double = 0, segElapsed: Double = 0, segIdle: Double = 0, segOff: Double = 0, segPaused: Double = 0

    /// Session length for the next session, chosen in the launcher (minutes).
    var sessionMinutes: Int {
        get { UserDefaults.standard.object(forKey: "sessionMinutes") as? Int ?? Int(d.focus / 60) }
        set { UserDefaults.standard.set(newValue, forKey: "sessionMinutes"); objectWillChange.send() }
    }
    var breathing: String { UserDefaults.standard.string(forKey: "breathing") ?? "cyclic" }

    init() {
        let home = ProcessInfo.processInfo.environment["POMODORO_HOME"].map { URL(fileURLWithPath: $0) }
        store = home.map { Store(root: $0) } ?? Store()
        db = SessionDB(url: store.root.appendingPathComponent("sessions.sqlite"))
        state = store.load(now: Date())
        if let k = ProcessInfo.processInfo.environment["POMODORO_LADDER_SCALE"].flatMap(Double.init) { Ladder.timeScale = k }
        if state.isPaused { say("Paused at \(clock(state.active)). Hold me to carry on.", for: 8) }
        else if state.phase == .ready { say("Ripe! Tap me to start session \(state.done + 1).", for: 8) }
        else if state.phase == .idle || state.phase == .armed { say("Hi, I'm Tomo. Tap me to pick what we're working on.", for: 7) }
        if state.isTimed { segStart = Date() }
        observe()
        if let a = NSWorkspace.shared.frontmostApplication.flatMap({ Policy.focusApp(bundleID: $0.bundleIdentifier) }) { arm(a) }
        store.log(["type": "launch", "accessibility": AXIsProcessTrusted() ? "granted" : "not granted", "at": iso(Date())])
        // .common so the clock keeps ticking while a mouse button is held (event-tracking run loop mode)
        RunLoop.main.add(Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { self.tick() } }, forMode: .common)
    }

    func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    // MARK: what Tomo shows

    var lively: Bool {
        let now = Date()
        return hold > 0 || state.phase == .ready || stage >= .simmer || now.timeIntervalSince(reaction.at) < 1.5
            || (moment.map { now.timeIntervalSince($0.at) < TomoArt.splashLength + TomoArt.celebrateLength } ?? false)
            || (nudgeUntil.map { now < $0 } ?? false) || (state.phase == .breakTime && inBreathing)
    }

    var inBreathing: Bool { state.phase == .breakTime && !state.paused && state.elapsed < state.rest(d) / 2 && !skipBreathing }
    var skipBreathing = false

    func react(_ kind: TomoScene.Reaction) { reaction = (kind, Date()) }

    /// Hard guards: silent for the whole of a SpeakFit session (or Tomo ends up in the practice recording),
    /// whenever any app is recording from the mic (calls, meetings, dictation), and when the Mac is muted.
    var soundAllowed: Bool { !(state.app == .speakFit && state.isTimed) && !Sound.micInUse && !Sound.systemMuted }
    func cue(_ c: Sound.Cue) { if soundAllowed { Sound.play(c) } }

    func scene(at now: Date, dark: Bool) -> TomoScene {
        var s = TomoScene(app: state.app, harvested: Int(state.harvest(d)), hold: hold, dark: dark)
        s.harvestFraction = state.harvest(d)
        s.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        s.react = reaction.kind; s.reactT = now.timeIntervalSince(reaction.at)
        s.look = eyes(now)
        if let mo = moment {
            let k = now.timeIntervalSince(mo.at)
            if mo.kind == .splash && k < TomoArt.splashLength { s.mode = .splash; s.phaseT = k; s.progress = 1; return s }
            if mo.kind == .splash && state.celebrated && k < TomoArt.splashLength + TomoArt.celebrateLength && state.done > 0 && state.dayActive >= d.dayGoal {
                s.mode = .celebrate; s.phaseT = k - TomoArt.splashLength; return s
            }
            if mo.kind == .entrance && k < TomoArt.entranceLength { s.mode = .entrance; s.phaseT = k; s.progress = 1; return s }
        }
        s.progress = state.progress(d)
        switch state.phase {
        case .idle: s.mode = .idle
        case .armed: s.mode = .idle
        case .ready: s.mode = .ready
        case .dayDone: s.mode = .dayDone
        case .breakTime:
            if inBreathing {
                s.mode = .breathe; s.phaseT = state.elapsed; s.breathing = breathing
            } else {
                s.mode = .rest
                let half = skipBreathing ? 0 : state.rest(d) / 2
                s.progress = min(1, max(0, (state.elapsed - half) / max(1, state.rest(d) - half)))
                s.phaseT = state.elapsed - half
            }
        case .focus:
            if state.isPaused { s.mode = .paused }
            else if let n = nudgeUntil, now < n { s.mode = .nudge }
            else {
                s.mode = switch stage {
                case .calm: .focus
                case .nudge: .nudge
                case .hmmph: .hmmph
                case .simmer: .simmer
                case .boil: .boil
                case .siren: .siren
                }
            }
        }
        if state.phase == .breakTime && state.isPaused { s.mode = .paused; s.progress = 0 }
        return s
    }

    /// Where Tomo looks. Idle: follows the cursor. Focus: down at the work, with a glance at the cursor
    /// every half minute or so. Off track: straight at you. Eased each frame so the eyes drift rather than snap.
    private func eyes(_ now: Date) -> CGVector {
        var target = CGVector.zero
        let atCursor: Bool
        switch state.phase {
        case .focus where !state.isPaused:
            if now > nextGlance { glanceUntil = now.addingTimeInterval(1.6); nextGlance = now.addingTimeInterval(.random(in: 25...45)) }
            atCursor = now < glanceUntil || stage >= .nudge
            target = CGVector(dx: 0, dy: 0.6)
        case .idle, .armed, .ready, .dayDone: atCursor = true
        default: atCursor = false
        }
        if atCursor, let f = panel?.frame {
            let m = NSEvent.mouseLocation
            let cx = f.minX + 120, cy = f.minY + 30 + 132 * (compact ? 0.62 : 1)   // Tomo's face in screen points
            target = CGVector(dx: max(-1, min(1, (m.x - cx) / 260)), dy: max(-1, min(1, (cy - m.y) / 260)))
        }
        look.dx += (target.dx - look.dx) * 0.12; look.dy += (target.dy - look.dy) * 0.12
        if let n = nudgeUntil, now < n { return CGVector(dx: 1, dy: 0) }
        return look
    }

    var taskLabel: String { state.task?.isEmpty == false ? state.task! : state.app?.title ?? "this" }

    var info: String {
        switch state.phase {
        case .focus:
            let left = Int(state.remaining(d) / 60) + 1
            let wall = Int(state.elapsed / 60), act = Int(state.active / 60)
            return "\(left) min left · \(act) of \(wall) min active · \(taskLabel)" + (state.isPaused ? " · paused" : "")
        case .breakTime:
            return inBreathing ? "Breathe with me · tap to skip" : "\(Int(state.remaining(d) / 60) + 1) min of rest left"
        case .ready: return "Tap to start session \(state.done + 1)"
        case .dayDone: return "Full harvest · \(Int(state.dayActive / 60)) active min today"
        case .armed: return "\(state.app?.title ?? "App") is open · the clock starts with a task"
        case .idle: return String(format: "%.1f of %d tomatoes today", state.harvest(d), d.perDay)
        }
    }

    var menuTitle: String {
        switch state.phase {
        case .focus: "\(Int(state.remaining(d) / 60) + 1)" + (state.isPaused ? " ⏸" : stage >= .hmmph ? " !" : "")
        case .breakTime: "\(Int(state.remaining(d) / 60) + 1) ☕︎"
        case .ready: "ripe"
        case .dayDone: "5/5"
        case .armed: "·"
        case .idle: ""
        }
    }

    func say(_ text: String, for seconds: Double = 5) {
        bubble = text; bubbleUntil = Date().addingTimeInterval(seconds)
    }

    func clock(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    // MARK: the once-a-second working check

    private static let anyInput = CGEventType(rawValue: ~0)!

    /// Is the person working on the session's task right now? On task = the session's app (or its allowed
    /// helpers) is in front; working = recent input or progress pings; on topic = the Chrome page fits the task.
    private func assess(_ now: Date) -> (active: Bool, trouble: Ladder.Trouble) {
        guard state.phase == .focus, !state.paused else { return (false, .none) }
        let front = NSWorkspace.shared.frontmostApplication
        let onTask = Policy.onTask(bundleID: front?.bundleIdentifier, isSelf: front?.processIdentifier == me, session: state.app)
        let inputIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        let sinceProgress = state.app.flatMap { lastActivity[$0] }.map { now.timeIntervalSince($0) }
        working = Ladder.isWorking(inputIdle: inputIdle, sinceProgress: sinceProgress)
        let onTopic = !(front?.bundleIdentifier == "com.google.Chrome" && watcher.verdict == .offTopic)
        if !onTask || !onTopic { return (false, .offTask) }
        if !working { return (false, .notWorking) }
        return (true, .none)
    }

    func tick() {
        let now = Date()
        let (active, t) = assess(now)
        if state.phase == .focus && !state.paused {
            segElapsed += 1; if active { segActive += 1 } else if t == .notWorking { segIdle += 1 } else { segOff += 1 }
        } else if state.isPaused { segPaused += 1 }
        updateLadder(t, now)
        // the Chrome watcher only runs where Chrome is allowed, while a session is running
        watcher.app = state.app ?? .other
        watcher.task = state.phase == .focus && (state.app == .northstar || state.app == .other) ? taskLabel : nil
        for e in state.tick(now: now, active: active, d) { handle(e, now) }
        if let u = bubbleUntil, now > u { bubble = nil; bubbleUntil = nil }
        presence(now)
        let shouldCompact = state.phase == .focus && !state.paused && stage == .calm && active && (calmSince.map { now.timeIntervalSince($0) > 6 } ?? false)
        if shouldCompact != compact { compact = shouldCompact }
        if now.timeIntervalSince(lastSave) > 15 { save() }
        onChange()
    }

    private func updateLadder(_ t: Ladder.Trouble, _ now: Date) {
        if t != trouble { trouble = t; troubleSince = t == .none ? nil : now }
        if t == .none { if calmSince == nil { calmSince = now } } else { calmSince = nil }
        let next = Ladder.stage(t, seconds: troubleSince.map { now.timeIntervalSince($0) } ?? 0)
        if next == stage {
            if next == .siren && now > nextSiren { cue(.siren); nextSiren = now.addingTimeInterval(4) }
            return
        }
        let was = stage
        stage = next
        if next > was {
            let what = t == .notWorking ? "You've gone quiet." : "That's not \(taskLabel)."
            switch next {
            case .nudge: react(.wobble); cue(.nudge); say("Hm? \(what)", for: 4)
            case .hmmph: react(.puff); cue(.hmmph); say("Hmmph. \(what)", for: 6)
            case .simmer: say("Still off track... back to \(taskLabel)?", for: 6)
            case .boil: cue(.boil); say("BACK. TO. \(taskLabel.uppercased()).", for: 8)
            case .siren: cue(.siren); nextSiren = now.addingTimeInterval(4); say("WEE-WOO! \(taskLabel). Tap me when you're back.", for: 30)
            case .calm: break
            }
            db.event("stage-\(next)", app: state.app?.rawValue, detail: t.rawValue, at: now)
        } else if next == .calm && was >= .hmmph {
            react(.hop); say("There you are. Back to it.", for: 3)
        }
    }

    private func handle(_ e: ScheduleEvent, _ now: Date) {
        switch e {
        case .focusEnded(let n):
            moment = (.splash, now)
            cue(.splash)
            recordSegment(completed: true, now)
            skipBreathing = false
            store.log(["type": "focus", "app": state.app?.rawValue ?? "", "task": state.task ?? "", "count": "\(n)", "end": iso(now)])
            if state.celebrated && state.dayActive >= d.dayGoal && state.tasks?.count == n {
                let days = store.recordFullHarvest(day: state.day)
                let list = (state.tasks ?? []).joined(separator: ", ")
                say("Full harvest! \(list). " + (days == 1 ? "Your first full day." : "Full day number \(days)."), for: 14)
                DispatchQueue.main.asyncAfter(deadline: .now() + TomoArt.splashLength) { MainActor.assumeIsolated { self.cue(.celebrate) } }
            } else {
                say("Session \(n) harvested! Breathe with me.", for: 7)
            }
        case .breakEnded:
            moment = (.entrance, now)
            cue(.ripe)
            say("Ripe! Tap me to start session \(state.done + 1).", for: 30)
        case .dayDone, .focusStarted: break
        case .newDay: say("New day, empty crate. Let's grow five.", for: 6)
        }
    }

    /// Presence: rare, soft signs of life. In focus only a non-voice pop or rustle every 5 to 10 minutes (D9).
    private func presence(_ now: Date) {
        if now > nextPresence {
            let focusing = state.phase == .focus && !state.isPaused
            if !frozen && soundAllowed && stage == .calm && !inBreathing && (focusing || [.idle, .armed, .ready, .breakTime, .dayDone].contains(state.phase)) {
                Sound.play(focusing ? [Sound.Presence.pop, .rustle].randomElement()! : Sound.Presence.allCases.randomElement()!)
                if state.phase != .breakTime && !focusing { react(.puff) }
            }
            nextPresence = now.addingTimeInterval(focusing ? .random(in: 300...600) : .random(in: 45...120))
        }
        if now > nextBeat {
            if [.idle, .armed, .ready].contains(state.phase) || (state.phase == .focus && !state.isPaused && stage == .calm) { react(.stretch) }
            nextBeat = now.addingTimeInterval(state.phase == .focus ? .random(in: 240...420) : .random(in: 25...50))
        }
        if inBreathing { breathCue(now) }
    }

    private var lastBreathCue = -1
    /// A soft breath sound as each inhale and each exhale begins.
    private func breathCue(_ now: Date) {
        let box = breathing == "box"
        let cycle: Double = box ? 16 : 8, outAt: Double = box ? 8 : 3
        let pos = state.elapsed.truncatingRemainder(dividingBy: cycle)
        let k = Int(state.elapsed / cycle) * 2 + (pos >= outAt ? 1 : 0)
        guard k != lastBreathCue else { return }
        lastBreathCue = k
        if soundAllowed { Sound.play(k % 2 == 0 ? .inhale : .exhale) }
    }

    func save() { store.save(state, now: Date()); lastSave = Date() }

    // MARK: sessions

    /// Writes the current task's stretch of the session to the store and starts a fresh segment.
    private func recordSegment(completed: Bool, _ now: Date) {
        guard let start = segStart, let app = state.app, segElapsed > 0 || segActive > 0 else { segStart = state.isTimed ? now : nil; return }
        db.add(.init(day: state.day, app: app.rawValue, task: taskLabel, taskId: state.taskId, start: start, end: now,
                     active: segActive, elapsed: segElapsed, idle: segIdle, offTask: segOff, paused: segPaused, completed: completed))
        segStart = now; segActive = 0; segElapsed = 0; segIdle = 0; segOff = 0; segPaused = 0
    }

    /// A study app is open (launched, switched to, or picked): arm Tomo; the clock waits for a task.
    func arm(_ app: FocusApp) {
        guard [.idle, .armed, .dayDone].contains(state.phase) else { return }
        let was = state.app
        state.arm(app: app)
        if was != app || state.phase == .armed {
            say(app == .speakFit ? "SpeakFit is open. I'll start when your session starts." :
                app == .northstar ? "Northstar is open. I'll start when you open a job." :
                "HackerSolve is open. I'll start when you open a lesson.", for: 6)
        }
        onChange()
    }

    func start(_ app: FocusApp, task: String? = nil, taskId: String? = nil) {
        let resumeTask = state.phase == .ready && state.app == app ? state.task : nil
        let now = Date()
        guard state.startFocus(app: app, task: task ?? resumeTask, taskId: taskId, target: Double(sessionMinutes) * 60, now: now, d) else { return }
        segStart = now; segActive = 0; segElapsed = 0; segIdle = 0; segOff = 0; segPaused = 0
        stage = .calm; trouble = .none; troubleSince = nil; calmSince = now
        lastActivity[app] = now
        store.log(["type": "start", "app": app.rawValue, "task": state.task ?? "", "at": iso(now)])
        say("\(app == .other ? "" : app.title + ", ")\(taskLabel == app.title ? "" : taskLabel + ". ")\(sessionMinutes) minutes. Let's grow one.", for: 6)
        react(.hop); cue(.start)
        hideOthers()
        save(); onChange()
    }

    func togglePause() {
        let now = Date()
        if state.isPaused { state.resume(now: now); say("Back to it.", for: 3); react(.hop); hideOthers() }
        else if state.isTimed { state.pause(now: now); say("Paused at \(clock(state.active)). Hold me to carry on.", for: 8) }
        else { return }
        stage = .calm; troubleSince = nil
        store.log(["type": state.isPaused ? "pause" : "resume", "phase": state.phase.rawValue, "active": "\(Int(state.active))", "at": iso(now)])
        save(); onChange()
    }

    /// Emergency exit: stops all hiding at once and brings back every app Tomo hid.
    func emergencyExit() {
        if state.phase == .focus { recordSegment(completed: false, Date()) }
        state.stop(d)
        stage = .calm; trouble = .none; troubleSince = nil; compact = false
        for pid in hidden { NSRunningApplication(processIdentifier: pid)?.unhide() }
        hidden.removeAll()
        store.log(["type": "exit", "at": iso(Date())])
        say("Session stopped. Everything is open again.", for: 6)
        save(); onChange()
    }

    func tap(onLeaf: Bool) {
        if onLeaf { beginField(.idea); return }
        if stage >= .nudge { calmDown(); return }
        switch state.phase {
        case .ready: if let a = state.app { start(a) }
        case .breakTime where inBreathing: skipBreathing = true; say("OK, just rest then.", for: 3)
        case .idle, .armed, .dayDone: showLauncher?()
        default: if state.isPaused { togglePause() } else { say(info, for: 3) }
        }
    }

    /// "I'm back": a tap calms Tomo at once; the ladder restarts only if the trouble continues.
    func calmDown() {
        stage = .calm; troubleSince = Date(); react(.hop)
        say("OK. Back to \(taskLabel).", for: 3)
    }

    var showLauncher: (() -> Void)?

    /// Launcher: open the app and arm; the clock starts when its task opens (or right away for Other).
    func launch(_ app: FocusApp) {
        let ids: [FocusApp: String] = [.hackerSolve: "com.aniketnamjoshi.hackersolve", .speakFit: "com.aniketnamjoshi.speakfit", .northstar: "com.aniket.northstar.viewer"]
        if let id = ids[app] {
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) { running.unhide(); running.activate() }
            else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        state.phase = state.phase == .dayDone ? .dayDone : .idle
        arm(app)
    }

    func runningStudyApp() -> FocusApp? {
        let front = NSWorkspace.shared.frontmostApplication.flatMap { Policy.focusApp(bundleID: $0.bundleIdentifier) }
        return front ?? NSWorkspace.shared.runningApplications.lazy.compactMap { Policy.focusApp(bundleID: $0.bundleIdentifier) }.first
    }

    // MARK: guard (DESIGN.md section 5)

    /// Test runs only: `POMODORO_HIDE_ONLY=com.apple.calculator` hides just those ids and logs the rest,
    /// so a test run never hides the developer's own windows.
    let hideOnly = ProcessInfo.processInfo.environment["POMODORO_HIDE_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }

    func mayFront(_ app: NSRunningApplication) -> Bool {
        let verdict = Policy.mayFront(bundleID: app.bundleIdentifier, bundlePath: app.bundleURL?.path, isRegular: app.activationPolicy == .regular,
                                      isSelf: app.processIdentifier == me, session: state.app)
        if !verdict, let only = hideOnly, !only.contains(app.bundleIdentifier ?? "") {
            store.log(["type": "would-hide", "blocked": app.bundleIdentifier ?? "?"]); return true
        }
        return verdict
    }

    /// D5: at session start everything not allowed is hidden (Cmd-H, never quit).
    func hideOthers() {
        guard Policy.isGuarding(state) else { return }
        var names: [String] = []
        for app in NSWorkspace.shared.runningApplications where !mayFront(app) && !app.isHidden {
            app.hide(); hidden.insert(app.processIdentifier)   // hide() reports false even on success
            names.append(app.localizedName ?? "?")
        }
        if !names.isEmpty {
            store.log(["type": "hid-at-start", "apps": names.joined(separator: ", "), "at": iso(Date())])
            db.event("hid-at-start", app: state.app?.rawValue, detail: names.joined(separator: ", "), at: Date())
        }
    }

    func activated(_ app: NSRunningApplication) {
        // A study app came forward: arm when idle; during a session it is always allowed (the task follows
        // the app's own start event).
        if let a = Policy.focusApp(bundleID: app.bundleIdentifier) {
            if [.idle, .armed, .dayDone].contains(state.phase) { arm(a) }
            return
        }
        guard Policy.isGuarding(state), !mayFront(app) else { return }
        // Hiding inside the activation itself is undone by macOS (checked 23 Oct 2026), and hide()
        // returns false even when it works. So: give focus back to the study app, hide a beat later, verify, retry once.
        sessionApp()?.activate()
        hidden.insert(app.processIdentifier)
        for delay in [0.15, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    guard !app.isHidden, Policy.isGuarding(self.state) else { return }
                    app.hide()
                    if delay > 0.5 { self.store.log(["type": "hide-retry", "blocked": app.bundleIdentifier ?? "?"]) }
                }
            }
        }
        nudgeUntil = Date().addingTimeInterval(2.5)
        react(.wobble); cue(.nudge)
        let name = app.localizedName ?? "That"
        let first = state.phase == .breakTime ? "Break time: stand up instead." : "Not now. \(taskLabel) first."
        say("\(name) is hidden. \(first)", for: 4)
        store.log(["type": "nudge", "blocked": app.bundleIdentifier ?? name, "app": state.app?.rawValue ?? "", "at": iso(Date())])
        db.event("hidden", app: state.app?.rawValue, detail: app.bundleIdentifier, at: Date())
        onChange()
    }

    private func observe() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { self.activated(app) } }
        }
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let a = Policy.focusApp(bundleID: id) else { return }
                if [.idle, .armed, .dayDone].contains(self.state.phase) { self.arm(a) }
                else if self.state.phase == .ready { self.say("\(a.title) is open. Tap me to start session \(self.state.done + 1).", for: 8) }
            }
        }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if self.state.isTimed && !self.state.isPaused { self.togglePause() } }
        }
        // Test copies listen on their own channel (POMODORO_EVENT_NAME), so a test can never retitle a real session.
        let channel = ProcessInfo.processInfo.environment["POMODORO_EVENT_NAME"] ?? FocusEvent.name
        DistributedNotificationCenter.default().addObserver(forName: .init(channel), object: nil, queue: .main) { n in
            let info = n.userInfo
            MainActor.assumeIsolated { if let e = FocusEvent(userInfo: info) { self.focusEvent(e) } }
        }
    }

    /// The contract. start: the clock begins (or the session follows a switch); end: a nod; activity: proof of work.
    /// "kind" means the session type on start and end, the action on activity; Pomodoro needs neither.
    func focusEvent(_ e: FocusEvent) {
        let now = Date()
        let taskId = e.extras["taskId"]
        db.event("contract-\(e.phase.rawValue)", app: e.app.rawValue, detail: e.task, at: now)
        switch e.phase {
        case .start:
            lastActivity[e.app] = now
            switch state.phase {
            case .focus:
                let changed = state.app != e.app || (!e.task.isEmpty && e.task != state.task)
                if changed { recordSegment(completed: false, now); state.retag(app: e.app, task: e.task.isEmpty ? nil : e.task, taskId: taskId)
                    say("\(e.task.isEmpty ? e.app.title : e.task). Same tomato, new task.", for: 4) }
            case .breakTime:
                say("Break first. Tap the ripe tomato when it's ready.", for: 5)
            default:
                start(e.app, task: e.task.isEmpty ? nil : e.task, taskId: taskId)
            }
        case .end:
            if state.app == e.app, !e.task.isEmpty { say("Nice, \(e.task) done.", for: 4) }
        case .activity:
            lastActivity[e.app] = now
            return
        }
        save(); onChange()
    }

    // MARK: the text field under Tomo: ideas inbox, or an Other task

    func beginField(_ mode: FieldMode) {
        fieldMode = mode; parking = true; draft = ""
        panel?.makeKey()
    }

    func park() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        parking = false; draft = ""
        if fieldMode == .otherTask {
            panel?.resignKey()
            guard !text.isEmpty else { return }
            start(.other, task: text)
            return
        }
        if !text.isEmpty {
            do { try lot.park(text, app: state.app, task: state.task, now: Date()); say("Parked in your ideas inbox. Back to it.", for: 3); react(.puff); cue(.park) }
            catch { say("Couldn't save that idea: \(error.localizedDescription)", for: 6) }
        }
        returnFocus()
    }

    /// Quit stops everything: state saved (it reopens paused), hidden apps brought back.
    func quitCleanly() {
        if state.phase == .focus { recordSegment(completed: false, Date()) }
        for pid in hidden { NSRunningApplication(processIdentifier: pid)?.unhide() }
        hidden.removeAll()
        save()
    }

    func cancelParking() { parking = false; draft = ""; returnFocus() }

    func returnFocus() {
        panel?.resignKey()
        sessionApp()?.activate()
    }

    func sessionApp() -> NSRunningApplication? {
        guard let a = state.app else { return nil }
        return NSWorkspace.shared.runningApplications.first { Policy.focusApp(bundleID: $0.bundleIdentifier) == a }
    }

    // MARK: press, hold, drag

    private var pressAt: Date?, mouseAt: NSPoint = .zero, originAt: NSPoint = .zero, dragging = false, held = false
    private var holdTimer: Timer?

    func pressChanged() {
        let mouse = NSEvent.mouseLocation
        if pressAt == nil {
            pressAt = Date(); mouseAt = mouse; originAt = panel?.frame.origin ?? .zero; dragging = false; held = false
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in MainActor.assumeIsolated { self.holdStep() } }
            RunLoop.main.add(t, forMode: .common); holdTimer = t   // a default-mode timer never fires mid-press
        }
        if !dragging, hypot(mouse.x - mouseAt.x, mouse.y - mouseAt.y) > 4 { dragging = true; hold = 0 }
        if dragging { panel?.setFrameOrigin(NSPoint(x: originAt.x + mouse.x - mouseAt.x, y: originAt.y + mouse.y - mouseAt.y)) }
    }

    private func holdStep() {
        guard let at = pressAt, !dragging, !held else { return }
        let k = Date().timeIntervalSince(at) - 0.25
        hold = max(0, min(1, k / 1.25))
        if hold >= 1 { held = true; hold = 0; if state.isTimed { togglePause() } }
    }

    func pressEnded(at location: CGPoint) {
        holdTimer?.invalidate(); holdTimer = nil
        defer { pressAt = nil; hold = 0 }
        if dragging { pressChanged() }   // the last drag events can arrive with the release
        guard let at = pressAt, !dragging, !held, Date().timeIntervalSince(at) < 0.5 else { return }
        // the leaves sit at the top of the drawing
        tap(onLeaf: location.y < 72 && abs(location.x - 100) < 45)
    }
}
