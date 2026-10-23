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
    let profileStore: ProfileStore
    @Published var profiles: [Profile] = []
    let launched = Date()
    let clock = TomoClock()
    enum Moment { case splash, entrance }
    var moment: (kind: Moment, at: Date)?
    var reaction: (kind: TomoScene.Reaction, at: Date) = (.none, .distantPast)
    private var look = CGVector.zero
    private var glanceUntil = Date.distantPast, nextGlance = Date().addingTimeInterval(25)
    private var nextBeat = Date().addingTimeInterval(20)
    private var nextPresence = Date().addingTimeInterval(.random(in: 40...90))
    var lastActivity: [String: Date] = [:]
    var hideTomo: () -> Void = {}
    /// A newer release, from the update check; Tomo shows a sprout for it outside focus.
    @Published var update: Update.Release?
    var showUpdate: (() -> Void)?
    /// The sprout is never shown in a running focus session, only idle, between sessions or on a break.
    var updateCueVisible: Bool { update != nil && !(state.phase == .focus && !state.paused) }
    var showTomo: () -> Void = {}
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

    /// Length picked in the launcher for the next session; whatever starts it (a tap, the app's own task start)
    /// uses it once. Unset: the profile's default length.
    @Published var nextMinutes: Int?
    var breathing: String { UserDefaults.standard.string(forKey: "breathing") ?? "cyclic" }

    init() {
        defer { clock.rate = { [unowned self] in self.breathCue(Date()); return self.frameRate }; clock.start() }
        let home = ProcessInfo.processInfo.environment["POMODORO_HOME"].map { URL(fileURLWithPath: $0) }
        store = home.map { Store(root: $0) } ?? Store()
        db = SessionDB(url: store.root.appendingPathComponent("sessions.sqlite"))
        profileStore = ProfileStore(root: store.root)
        state = store.load(now: Date())
        if let k = ProcessInfo.processInfo.environment["POMODORO_LADDER_SCALE"].flatMap(Double.init) { Ladder.timeScale = k }
        // POMODORO_FRESH (tests only) pretends none of the preset apps are installed: a friend's Mac.
        let fresh = ProcessInfo.processInfo.environment["POMODORO_FRESH"] != nil
        profiles = profileStore.load(installed: { !fresh && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
        if state.isPaused { say("Paused at \(clock(state.active)). Hold me to carry on.", for: 8) }
        else if state.phase == .ready { say("Ripe! Tap me to start session \(state.done + 1).", for: 8) }
        else if state.phase == .idle || state.phase == .armed { say("Hi, I'm Tomo. Tap me to pick what we're working on.", for: 7) }
        if state.isTimed { segStart = Date() }
        // A title only lives as long as the event that set it: after a restart the app's name shows until the
        // app reports its task again (23 Oct: a stale "Lesson 4" stuck for hours).
        state.task = nil; state.taskId = nil
        observe()
        if let a = NSWorkspace.shared.frontmostApplication.flatMap({ profileFor(bundleID: $0.bundleIdentifier) }) { arm(a) }
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

    /// Frames per second Tomo needs now. Each frame costs about 0.35% CPU per fps on this Mac (measured 23 Oct),
    /// so frames are drawn only when something moves: 30 for big moments, 15 for visible motion, and when calm a
    /// still frame with a 1.2 s burst of life every 8 s in focus (the still frame costs nothing).
    var frameRate: Double {
        if frozen { return 0 }
        if lively { return 30 }
        if hovering || hold > 0 || stage >= .nudge || state.phase == .breakTime || bubble != nil { return 15 }
        guard state.phase == .focus || updateCueVisible else { return 0 }   // idle: still until hovered (or a sprout sways)
        return Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 8) < 1.2 ? 15 : 0
    }

    /// Breathing opens the break for at most a minute (10 breaths), then the vine grows the next tomato for the rest:
    /// half-and-half hid the harvest behind 5 minutes of breathing after a 45-minute session (24 Oct).
    var breathLength: Double { skipBreathing ? 0 : min(60, state.rest(d) / 2) }
    var inBreathing: Bool { state.phase == .breakTime && !state.paused && state.elapsed < breathLength }
    var skipBreathing = false

    func react(_ kind: TomoScene.Reaction) { reaction = (kind, Date()) }

    /// Hard guards: silent for the whole of a SpeakFit session (or Tomo ends up in the practice recording),
    /// whenever any app is recording from the mic (calls, meetings, dictation), and when the Mac is muted.
    /// Silent while SpeakFit is the app in front during a session (so Tomo never lands in a practice take) and
    /// whenever any app records from the mic; the mic check also covers SpeakFit recording in the background.
    /// 0.4.0 silenced the whole SpeakFit session including pauses and breaks, which read as "sound isn't working".
    var soundAllowed: Bool {
        let speakFitInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.aniketnamjoshi.speakfit"
        return !(state.phase == .focus && !state.paused && speakFitInFront) && !Sound.micInUse && !Sound.systemMuted
    }

    /// Settings' test button: plays regardless of the session guard, but still respects mute and the mic.
    func testSound() {
        if Sound.systemMuted { say("Your Mac is muted.", for: 4); return }
        if Sound.micInUse { say("A mic is recording, so I stay quiet.", for: 4); return }
        Sound.play(.start); react(.hop); say("Can you hear me?", for: 3)
    }
    func cue(_ c: Sound.Cue) { if soundAllowed { Sound.play(c) } }

    func scene(at now: Date, dark: Bool) -> TomoScene {
        var s = TomoScene(app: state.app, harvested: Int(state.harvest(d)), hold: hold, dark: dark)
        s.update = updateCueVisible
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
                s.mode = .breathe; s.phaseT = smoothElapsed(now); s.breathing = breathing
            } else {
                s.mode = .rest
                let half = breathLength, e = smoothElapsed(now)   // smooth growth between the 1 s ticks
                s.progress = min(1, max(0, (e - half) / max(1, state.rest(d) - half)))
                s.phaseT = e - half
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

    var taskLabel: String { state.task?.isEmpty == false ? state.task! : state.appName ?? "this" }

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
        case .armed: return current?.contractApp != nil ? "\(state.appName ?? "App") is open · the clock starts with a task" : "Tap to start \(state.appName ?? "a session")"
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
        let onTask = Policy.onTask(frontInfo(front), profile: current)
        let inputIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput)
        let sinceProgress = state.app.flatMap { lastActivity[$0] }.map { now.timeIntervalSince($0) }
        // counting uses only progress the app itself reported; the start stamp above only spares the scolding
        let sinceReported = state.app.flatMap { lastReported[$0] }.map { now.timeIntervalSince($0) }
        working = Ladder.isWorking(inputIdle: inputIdle, sinceProgress: sinceProgress)
        // topic rules apply to Northstar and Other sessions; website profiles are judged by domain in onTask
        let onTopic = !(front.map { Self.browserIDs.contains($0.bundleIdentifier ?? "") } ?? false) || current?.kind == .website || watcher.verdict != .offTopic
        if !onTask || !onTopic { return (false, .offTask) }
        if !working { return (false, .notWorking) }
        return (Ladder.isEngaged(inputIdle: inputIdle, sinceProgress: sinceReported), .none)   // counted only when engaged
    }

    /// Start on interaction (24 Oct): 10 s of real input in a profile's app starts tracking at that profile's last
    /// length. Not after an emergency exit for 10 minutes, not on a break or after one (a tap starts those).
    /// When each app last reported progress itself (a contract start or activity ping), for engaged counting.
    private var lastReported: [String: Date] = [:]
    private var interact: (id: String, seconds: Double)?
    var autoStartAllowedAfter = Date.distantPast
    private func autoStart(_ now: Date) {
        guard [.idle, .armed].contains(state.phase), now >= autoStartAllowedAfter,
              let p = profileFor(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { interact = nil; return }
        if interact?.id != p.id { interact = (p.id, 0) }
        guard CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput) < 1.5 else { return }
        interact!.seconds += 1
        guard interact!.seconds >= Policy.interactToStart else { return }
        interact = nil
        let w = pending?.profile == p.id ? pending : nil
        start(p, task: w?.task, taskId: w?.taskId)
    }

    /// At the Mac with nothing tracked: say so at most every 5 minutes, and log the front app as an untagged L0
    /// record so the gap is visible later ("first open should give focus option... Pomo can't [track]", 23 Oct).
    private var lastUntrackedPrompt = Date()
    private func untrackedPrompt(_ now: Date) {
        guard [.idle, .armed].contains(state.phase), now.timeIntervalSince(lastUntrackedPrompt) > 300,
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInput) < 30 else { return }
        lastUntrackedPrompt = now
        db.event("untracked", app: nil, detail: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, at: now)
        say("Not tracking yet. Tap me to pick what you're focusing on.", for: 8)
    }

    func tick() {
        let now = Date()
        let (active, t) = assess(now)
        if state.phase == .focus && !state.paused {
            segElapsed += 1; if active { segActive += 1 } else if t == .offTask { segOff += 1 } else { segIdle += 1 }
        } else if state.isPaused { segPaused += 1 }
        updateLadder(t, now)
        // the Chrome watcher only runs where Chrome is allowed, while a session is running
        // the tab watcher reads the front browser tab: topic rules for Northstar and Other, the domain for websites
        watcher.app = state.app ?? "Other"
        watcher.task = [.focus, .armed].contains(state.phase) && (current?.kind == .website || state.app == "NorthstarViewer" || state.app == "Other") ? taskLabel : nil
        // a website profile's clock starts the first time one of its pages is in front
        if state.phase == .armed, current?.kind == .website, picked == current?.id, Policy.onTask(frontInfo(NSWorkspace.shared.frontmostApplication), profile: current),
           watcher.host != nil, let p = current { start(p) }
        // mutating a @Published struct publishes even when nothing changed, which redrew Tomo every second
        var next = state; let events = next.tick(now: now, active: active, d)
        if next != state { state = next }
        for e in events { handle(e, now) }
        if let u = bubbleUntil, now > u { bubble = nil; bubbleUntil = nil; offerSwitch = nil }
        enforceFront(now)
        presence(now)
        untrackedPrompt(now)
        autoStart(now)
        let shouldCompact = state.phase == .focus && !state.paused && stage == .calm && active && (calmSince.map { now.timeIntervalSince($0) > 6 } ?? false)
        if shouldCompact != compact { compact = shouldCompact }
        if now.timeIntervalSince(lastSave) > 15 { save() }
        onChange()
    }

    private func updateLadder(_ t: Ladder.Trouble, _ now: Date) {
        if t != trouble { trouble = t; troubleSince = t == .none ? nil : now }
        if t == .none { if calmSince == nil { calmSince = now } } else { calmSince = nil }
        let next = Ladder.stage(t, seconds: troubleSince.map { now.timeIntervalSince($0) } ?? 0)
        // the siren wails continuously while the stage lasts, and stops the moment it ends or sound must stop
        if next == .siren && soundAllowed { Sound.startSiren() } else { Sound.stopSiren() }
        if next == stage { return }
        let was = stage
        stage = next
        if next > was {
            let what = t == .notWorking ? "You've gone quiet." : "That's not \(taskLabel)."
            switch next {
            case .nudge: react(.wobble); cue(.nudge); say("Hm? \(what)", for: 4)
            case .hmmph: react(.puff); cue(.hmmph); say("Hmmph. \(what)", for: 6)
            case .simmer: cue(.simmer); say("Still off track... back to \(taskLabel)?", for: 6)
            case .boil: cue(.boil); say("BACK. TO. \(taskLabel.uppercased()).", for: 8)
            case .siren: say("WEE-WOO! \(taskLabel). Tap me when you're back.", for: 30)
            case .calm: break
            }
            db.event("stage-\(next)", app: state.app, detail: t.rawValue, at: now)
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
            store.log(["type": "focus", "app": state.app ?? "", "task": state.task ?? "", "count": "\(n)", "end": iso(now)])
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
    }

    /// The break's elapsed time between the once-a-second ticks, so the breath moves smoothly instead of in
    /// one-second steps (24 Oct: "laggy").
    func smoothElapsed(_ now: Date) -> Double { state.elapsed + min(1, max(0, state.lastTick.map { now.timeIntervalSince($0) } ?? 0)) }

    private var lastBreathCue = -1
    /// A soft breath sound as each inhale and each exhale begins; called every frame, so it lands on the motion.
    func breathCue(_ now: Date) {
        guard inBreathing else { return }
        let (cycle, outAt) = TomoArt.breathCycle(breathing)
        let e = smoothElapsed(now), pos = e.truncatingRemainder(dividingBy: cycle)
        let k = Int(e / cycle) * 2 + (pos >= outAt ? 1 : 0)
        guard k != lastBreathCue else { return }
        lastBreathCue = k
        if soundAllowed { Sound.play(k % 2 == 0 ? .inhale : .exhale) }
    }

    func save() { store.save(state, now: Date()); lastSave = Date() }

    // MARK: sessions

    /// Writes the current task's stretch of the session to the store and starts a fresh segment.
    private func recordSegment(completed: Bool, _ now: Date) {
        guard let start = segStart, let app = state.appName ?? state.app, segElapsed > 0 || segActive > 0 else { segStart = state.isTimed ? now : nil; return }
        db.add(.init(day: state.day, app: app, task: taskLabel, taskId: state.taskId, start: start, end: now,
                     active: segActive, elapsed: segElapsed, idle: segIdle, offTask: segOff, paused: segPaused, completed: completed))
        picked = nil; pending = nil; fights = [:]; tolerated = []
        segStart = now; segActive = 0; segElapsed = 0; segIdle = 0; segOff = 0; segPaused = 0
    }

    /// A study app is open (launched, switched to, or picked): arm Tomo; the clock waits for a task.
    func arm(_ p: Profile) {
        guard [.idle, .armed, .dayDone].contains(state.phase) else { return }
        let was = state.app
        state.arm(app: p.id, name: p.name)
        guard was != p.id else { onChange(); return }
        if p.kind == .website { say("\(p.name): I'll start when you open it in your browser.", for: 6) }
        else if picked == p.id || Date() >= autoStartAllowedAfter {
            say("\(p.name) is open. I'll start tracking once you get going (\(picked == p.id ? (nextMinutes ?? lastMinutes(p)) : lastMinutes(p)) min).", for: 6)
        } else { say("\(p.name) is open. Tap me when you want to start.", for: 6) }
        onChange()
    }

    // MARK: profiles

    var current: Profile? { state.app.flatMap { id in profiles.first { $0.id == id } } }
    func profile(_ id: String) -> Profile? { profiles.first { $0.id == id } }
    /// The length last used for this profile: a pick carries to its next session (24 Oct: offered 45 after a 5).
    func lastMinutes(_ p: Profile) -> Int { (UserDefaults.standard.object(forKey: "lastMinutes." + p.id) as? Int) ?? p.minutes }
    /// The app profile whose target this app is.
    func profileFor(bundleID: String?) -> Profile? {
        guard let id = bundleID else { return nil }
        return profiles.first { $0.kind == .app && $0.isTarget(id) }
    }
    /// The profile that matches a contract poster: by its contract name, else by profile name.
    func profileFor(contract app: String) -> Profile? {
        profiles.first { $0.contractApp == app } ?? profiles.first { $0.name.caseInsensitiveCompare(app) == .orderedSame }
    }

    func frontInfo(_ app: NSRunningApplication?) -> Policy.Front {
        let id = app?.bundleIdentifier
        let browser = id.map { Self.browserIDs.contains($0) } ?? false
        return Policy.Front(bundleID: id, path: app?.bundleURL?.path, isRegular: app?.activationPolicy == .regular,
                            isSelf: app?.processIdentifier == me, isBrowser: browser, host: browser ? watcher.host : nil)
    }

    /// Apps registered to open web pages: the browsers (Launch Services, no permission needed).
    /// AI apps that also register for web links (ChatGPT does) are treated as apps, not browsers.
    static let browserIDs: Set<String> = Set(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        .compactMap { url -> String? in
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            return AppCatalog.group(id: id, name: url.deletingPathExtension().lastPathComponent, url: url) == .ai ? nil : id
        })

    func saveProfiles(_ p: [Profile]) { profiles = p; profileStore.save(p) }

    func start(_ p: Profile, task: String? = nil, taskId: String? = nil) {
        let app = p.id
        let now = Date()
        let minutes = nextMinutes ?? lastMinutes(p)
        nextMinutes = nil
        UserDefaults.standard.set(minutes, forKey: "lastMinutes." + p.id)
        guard state.startFocus(app: app, name: p.name, task: task, taskId: taskId, target: Double(minutes) * 60, now: now, d) else { return }
        picked = nil; pending = nil
        segStart = now; segActive = 0; segElapsed = 0; segIdle = 0; segOff = 0; segPaused = 0
        stage = .calm; trouble = .none; troubleSince = nil; calmSince = now
        lastActivity[app] = now
        store.log(["type": "start", "app": app, "task": state.task ?? "", "at": iso(now)])
        showTomo()   // the session's clock lives on Tomo, so starting one always brings Tomo into view
        say("Started: \(taskLabel), \(minutes) min", for: 6)
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
        Sound.stopSiren()
        if state.phase == .focus { recordSegment(completed: false, Date()) }
        state.stop(d)
        picked = nil; pending = nil; fights = [:]; tolerated = []
        autoStartAllowedAfter = Date().addingTimeInterval(600)   // an exit means "not now": no auto-start for 10 min
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
        case .ready: if let p = current { nextMinutes = nextMinutes ?? Int(state.target / 60); start(p) }   // the length he picked carries on
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
    /// A study app outside this session's profile that was just hidden: Tomo offers Switch or Stay.
    @Published var offerSwitch: String?
    private var lastBlock = Date.distantPast
    /// Apps that came back after being hidden: after 3 re-hides one is let be for the rest of the session,
    /// rather than a hide loop that flickers and fights it.
    private var fights: [pid_t: Int] = [:]
    private var tolerated: Set<pid_t> = []

    /// Switch: the current session ends (saved) and the picker opens on the other app.
    func switchFocus() {
        guard let id = offerSwitch, let p = profile(id) else { return }
        offerSwitch = nil
        emergencyExit()
        autoStartAllowedAfter = .distantPast   // a switch is a choice to work on the other app
        store.log(["type": "switch", "to": id, "at": iso(Date())])
        NSWorkspace.shared.runningApplications.first { p.isTarget($0.bundleIdentifier ?? "") }?.activate()
        arm(p); showLauncher?()
    }
    func stay() { offerSwitch = nil; bubble = nil; bubbleUntil = nil }

    /// Activation alone misses some hides (an app that brings itself back, a Dock click mid-hide, a launch during
    /// the session): once a second the front app is checked, re-hidden, and the miss logged with its likely cause.
    private func enforceFront(_ now: Date) {
        guard Policy.isGuarding(state), now.timeIntervalSince(lastBlock) > 1.5,
              let f = NSWorkspace.shared.frontmostApplication, !mayFront(f) else { return }
        lastBlock = now
        let why = hidden.contains(f.processIdentifier) ? "came back after a hide" : "no activation seen"
        fights[f.processIdentifier, default: 0] += 1
        if fights[f.processIdentifier]! > 3 {
            tolerated.insert(f.processIdentifier)
            store.log(["type": "hide-gave-up", "blocked": f.bundleIdentifier ?? "?", "at": iso(now)])
            say("\(f.localizedName ?? "That app") keeps coming back, so I'll let it be this session.", for: 5)
            return
        }
        store.log(["type": "hide-poll", "blocked": f.bundleIdentifier ?? "?", "why": why, "at": iso(now)])
        db.event("hide-poll", app: state.app, detail: "\(f.bundleIdentifier ?? "?"): \(why)", at: now)
        bringSessionApp()
        hidden.insert(f.processIdentifier)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if !f.isHidden { f.hide() } }
    }
    /// The profile chosen in the launcher: its app's next task start may start the clock (consent).
    var picked: String?
    /// A task that opened with nothing picked; the launcher's Start for the same profile starts it at once.
    var pending: (profile: String, task: String?, taskId: String?)?

    /// Launcher: open the app and arm; the clock starts when its task opens (or right away for Other).
    /// Launcher: open the profile's app or site. Contract apps arm (their task start starts the clock);
    /// other apps start at once; websites start when one of their pages is in front; Other asks for the task.
    func launch(_ p: Profile, minutes: Int? = nil, task: String? = nil) {
        if let minutes { nextMinutes = minutes }
        autoStartAllowedAfter = .distantPast
        if let w = pending, w.profile == p.id { start(p, task: w.task, taskId: w.taskId); return }
        picked = p.id
        if p.kind == .other, let t = task?.trimmingCharacters(in: .whitespaces), !t.isEmpty { start(p, task: t); return }
        switch p.kind {
        case .other: beginField(.otherTask); return
        case .app:
            if let id = p.appID {
                if let running = NSWorkspace.shared.runningApplications.first(where: { p.isTarget($0.bundleIdentifier ?? "") }) { running.unhide(); running.activate() }
                else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        case .website:
            if let d = p.domains.first, let url = URL(string: "https://" + d) {
                if let b = p.browsers.first, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } else { NSWorkspace.shared.open(url) }
            }
        }
        if state.phase != .dayDone { state.phase = .idle }
        arm(p)
        if p.kind == .app && p.contractApp == nil { start(p) }
    }

    // MARK: guard (DESIGN.md section 5)

    /// Test runs only: `POMODORO_HIDE_ONLY=com.apple.calculator` hides just those ids and logs the rest,
    /// so a test run never hides the developer's own windows.
    let hideOnly = ProcessInfo.processInfo.environment["POMODORO_HIDE_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }

    func mayFront(_ app: NSRunningApplication) -> Bool {
        if tolerated.contains(app.processIdentifier) { return true }
        let verdict = Policy.mayFront(frontInfo(app), profile: current)
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
        if !names.isEmpty, !UserDefaults.standard.bool(forKey: "taughtExit") {
            UserDefaults.standard.set(true, forKey: "taughtExit")   // the first time apps get hidden, show the way out
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { MainActor.assumeIsolated { self.say("Need out? ⌃⌥⌘E brings every app back.", for: 8) } }
        }
        if !names.isEmpty {
            store.log(["type": "hid-at-start", "apps": names.joined(separator: ", "), "at": iso(Date())])
            db.event("hid-at-start", app: state.app, detail: names.joined(separator: ", "), at: Date())
        }
    }

    func activated(_ app: NSRunningApplication) {
        // A study app came forward: arm when idle; during a session it is always allowed (the task follows
        // the app's own start event).
        let study = profileFor(bundleID: app.bundleIdentifier)
        if let a = study, [.idle, .armed, .dayDone].contains(state.phase) { arm(a) }
        guard Policy.isGuarding(state), !mayFront(app) else { return }
        // another study app mid-session: hidden like the rest, with an offer to switch (never silently)
        offerSwitch = study.flatMap { $0.id == state.app ? nil : $0.id }
        lastBlock = Date()
        // Hiding inside the activation itself is undone by macOS (checked 23 Oct 2026), and hide()
        // returns false even when it works. So: give focus back to the study app, hide a beat later, verify, retry once.
        bringSessionApp()
        hidden.insert(app.processIdentifier)
        for delay in [0.15, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    guard !app.isHidden, Policy.isGuarding(self.state) else { return }
                    app.hide()
                    if delay > 0.5 { self.store.log(["type": "hide-retry", "blocked": app.bundleIdentifier ?? "?", "why": "first hide did not stick"]) }
                }
            }
        }
        nudgeUntil = Date().addingTimeInterval(2.5)
        react(.wobble); cue(.nudge)
        let name = app.localizedName ?? "That"
        let first = state.phase == .breakTime ? "Break time: stand up instead." : "Not now. \(taskLabel) first."
        if offerSwitch != nil { say("\(name) isn't in this focus. Switch focus to \(name)?", for: 10) }
        else { say("\(name) is hidden. \(first)", for: 4) }
        store.log(["type": "nudge", "blocked": app.bundleIdentifier ?? name, "app": state.app ?? "", "at": iso(Date())])
        db.event("hidden", app: state.app, detail: app.bundleIdentifier, at: Date())
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
                guard let a = self.profileFor(bundleID: id) else { return }
                if [.idle, .armed, .dayDone].contains(self.state.phase) { self.arm(a) }
                else if self.state.phase == .ready { self.say("\(a.name) is open. Tap me to start session \(self.state.done + 1).", for: 8) }
            }
        }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if self.state.isTimed && !self.state.isPaused { self.togglePause() } }
        }
        // Test copies listen on their own channel (POMODORO_EVENT_NAME), so a test can never retitle a real session.
        let channels = ProcessInfo.processInfo.environment["POMODORO_EVENT_NAME"].map { [$0] } ?? [FocusEvent.name, FocusEvent.publicName]
        for channel in channels {
            DistributedNotificationCenter.default().addObserver(forName: .init(channel), object: nil, queue: .main) { n in
                let info = n.userInfo
                MainActor.assumeIsolated { if let e = FocusEvent(userInfo: info) { self.focusEvent(e) } }
            }
        }
    }

    /// The contract. start: the clock begins (or the session follows a switch); end: a nod; activity: proof of work.
    /// "kind" means the session type on start and end, the action on activity; Pomodoro needs neither.
    func focusEvent(_ e: FocusEvent) {
        let now = Date()
        let taskId = e.extras["taskId"]
        db.event("contract-\(e.phase.rawValue)", app: e.app, detail: e.task, at: now)
        guard let p = profileFor(contract: e.app) else { return }   // an app with no profile: logged, not acted on
        switch e.phase {
        case .start:
            lastActivity[p.id] = now; lastReported[p.id] = now
            let task = e.task.isEmpty ? nil : e.task
            switch Policy.contractStart(phase: state.phase, picked: picked, profile: p.id, session: state.app, autoStart: now >= autoStartAllowedAfter) {
            case .retag:
                let changed = state.app != p.id || (task != nil && task != state.task)
                if changed { recordSegment(completed: false, now); state.retag(app: p.id, name: p.name, task: task, taskId: taskId)
                    say("\(task ?? p.name). Same tomato, new task.", for: 4) }
            case .ignore:
                break   // logged above; the session stays with its own app
            case .waitForBreak:
                say("Break first. Tap the ripe tomato when it's ready.", for: 5)
            case .start:
                start(p, task: task, taskId: taskId)
            case .ask:
                // nothing picked: show the picker pre-filled with this app and wait for one tap
                pending = (p.id, task, taskId)
                arm(p)
                say("\(p.name) is open. Pick a length, then Start.", for: 8)
                showLauncher?()
            }
        case .end:
            if state.app == p.id {
                if !e.task.isEmpty, state.phase == .focus { say("Nice, \(e.task) done.", for: 4) }   // not when nothing was running
                if state.phase == .focus { recordSegment(completed: false, now) }
                state.task = nil; state.taskId = nil          // back to the app's name until the next task starts
            }
        case .activity:
            lastActivity[p.id] = now; lastReported[p.id] = now
            // an activity ping that names its task keeps the label true (e.g. a new lesson opened without a start)
            if state.phase == .focus, state.app == p.id, !e.task.isEmpty, e.task != state.task {
                recordSegment(completed: false, now); state.retag(app: p.id, name: p.name, task: e.task, taskId: taskId)
            }
            onChange()
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
            start(profile("Other") ?? .other, task: text)
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
        Sound.stopSiren()
        if state.phase == .focus { recordSegment(completed: false, Date()) }
        for pid in hidden { NSRunningApplication(processIdentifier: pid)?.unhide() }
        hidden.removeAll()
        save()
    }

    func cancelParking() { parking = false; draft = ""; returnFocus() }

    func returnFocus() {
        panel?.resignKey()
        bringSessionApp()
    }

    /// Since macOS 14 an app that is not frontmost cannot reliably pull another forward with activate()
    /// (cooperative activation): hiding the Viewer left Finder in front, not HackerSolve (24 Oct live drive).
    /// Opening the app through Launch Services does bring it forward.
    func bringSessionApp() {
        guard let url = sessionApp()?.bundleURL else { return }
        let c = NSWorkspace.OpenConfiguration(); c.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: c)
    }

    func sessionApp() -> NSRunningApplication? {
        guard let p = current, p.kind == .app else { return nil }
        return NSWorkspace.shared.runningApplications.first { p.isTarget($0.bundleIdentifier ?? "") }
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
        // the update sprout sits left of Tomo; the leaves at the top of the drawing
        if updateCueVisible, location.x < 44, (100...175).contains(location.y) { showUpdate?(); return }
        tap(onLeaf: location.y < 72 && abs(location.x - 100) < 45)
    }
}

/// Drives Tomo's frames with a plain timer at the rate the model asks for. A SwiftUI TimelineView kept the
/// display link awake: about 3% CPU even at 4 fps with nothing to draw (measured 23 Oct).
/// `t` is animation time; it only advances while frames are drawn, so a still Tomo holds its pose.
@MainActor final class TomoClock: ObservableObject {
    @Published private(set) var t: Double = 0
    var rate: () -> Double = { 15 }
    private var last = Date()
    private var timer: Timer?

    func start() { schedule(0) }

    private func schedule(_ delay: Double) {
        let next = Timer(timeInterval: delay, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.fire() } }
        RunLoop.main.add(next, forMode: .common); timer = next
    }

    private func fire() {
        let now = Date(), r = rate()
        if r > 0 { t += min(now.timeIntervalSince(last), 0.1) }
        last = now
        schedule(r > 0 ? 1 / r : 0.25)   // still: re-check four times a second, draw nothing
    }
}
