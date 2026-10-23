import Foundation

public enum Phase: String, Codable, Sendable {
    case idle        // nothing open
    case armed       // a study app is open; the clock waits until a task actually starts
    case focus       // counting active seconds toward the session length
    case breakTime   // breathing, then rest
    case ready       // break over, ripe tomato waits for a tap
    case dayDone     // 225 active minutes reached (sessions can still run)
}

public struct Durations: Codable, Equatable, Sendable {
    /// Default session length; each session may pick its own (launcher).
    public var focus: TimeInterval = 45 * 60
    /// The day's harvest: 5 tomatoes x 45 active minutes.
    public var dayGoal: TimeInterval = 5 * 45 * 60
    public var perDay = 5
    /// Test runs only: shrinks every break to this many seconds.
    public var restOverride: TimeInterval?

    public init(focus: TimeInterval = 45 * 60, dayGoal: TimeInterval = 5 * 45 * 60, perDay: Int = 5, restOverride: TimeInterval? = nil) {
        self.focus = focus; self.dayGoal = dayGoal; self.perDay = perDay; self.restOverride = restOverride
    }

    /// Breaks scale with the session: 10 min after 45, 7 after 30, 1 after 5 (sessions start at 5 minutes).
    public func rest(after target: TimeInterval) -> TimeInterval {
        restOverride ?? max(60, (target * 10 / 45 / 60).rounded() * 60)
    }

    /// One tomato is 45 active minutes, whatever session lengths fill it.
    public var minutesPerTomato: TimeInterval { dayGoal / Double(perDay) }

    public static func fromEnvironment() -> Durations {
        let env = ProcessInfo.processInfo.environment
        var d = Durations()
        if let f = env["POMODORO_FOCUS_SECONDS"].flatMap(Double.init) { d.focus = f }
        if let g = env["POMODORO_DAY_SECONDS"].flatMap(Double.init) { d.dayGoal = g }
        if let b = env["POMODORO_BREAK_SECONDS"].flatMap(Double.init) { d.restOverride = b }
        return d
    }
}

public enum ScheduleEvent: Equatable, Sendable {
    case focusStarted, focusEnded(count: Int), breakEnded, dayDone, newDay
}

/// The whole day. Pure value: time moves only through `tick`, which is told each second whether the person
/// is actually working, so only active seconds fill the tomato (the clock cannot be fooled by an open window).
public struct DayState: Codable, Equatable, Sendable {
    public var day: String
    public var phase: Phase = .idle
    /// The session's profile id; `appName` is its display name.
    public var app: String?
    public var appName: String?
    public var task: String?
    public var taskId: String?
    /// Finished sessions today.
    public var done = 0
    /// Seconds of wall time in the current focus or break.
    public var elapsed: TimeInterval = 0
    /// Seconds actually worked in the current session.
    public var active: TimeInterval = 0
    /// Session length chosen for this session.
    public var target: TimeInterval = 45 * 60
    /// Active seconds across today's sessions: fills the harvest.
    public var dayActive: TimeInterval = 0
    public var celebrated = false
    public var paused = false
    public var lastTick: Date?
    public var focusStartedAt: Date?
    /// Titles of today's finished sessions, for the 5-of-5 summary.
    public var tasks: [String]?

    public init(day: String) { self.day = day }

    /// Tolerant of older state files (0.1 and 0.2 had no active clock): missing fields take defaults, so an
    /// upgrade mid-day keeps the day's sessions instead of starting over.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        phase = (try? c.decodeIfPresent(Phase.self, forKey: .phase)) ?? .idle
        app = try? c.decodeIfPresent(String.self, forKey: .app)
        appName = (try? c.decodeIfPresent(String.self, forKey: .appName)) ?? app
        task = try? c.decodeIfPresent(String.self, forKey: .task)
        taskId = try? c.decodeIfPresent(String.self, forKey: .taskId)
        done = (try? c.decodeIfPresent(Int.self, forKey: .done)) ?? 0
        elapsed = (try? c.decodeIfPresent(Double.self, forKey: .elapsed)) ?? 0
        target = (try? c.decodeIfPresent(Double.self, forKey: .target)) ?? 45 * 60
        // 0.2 counted wall time as the session's progress: carry it over as active time.
        active = (try? c.decodeIfPresent(Double.self, forKey: .active)) ?? (phase == .focus ? elapsed : 0)
        dayActive = (try? c.decodeIfPresent(Double.self, forKey: .dayActive)) ?? (Double(done) * 45 * 60 + (phase == .focus ? elapsed : 0))
        celebrated = (try? c.decodeIfPresent(Bool.self, forKey: .celebrated)) ?? false
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? (phase == .focus || phase == .breakTime)
        lastTick = nil
        focusStartedAt = try? c.decodeIfPresent(Date.self, forKey: .focusStartedAt)
        tasks = try? c.decodeIfPresent([String].self, forKey: .tasks)
    }

    public var isTimed: Bool { phase == .focus || phase == .breakTime }
    public var isPaused: Bool { isTimed && paused }

    public func rest(_ d: Durations) -> TimeInterval { d.rest(after: target) }

    /// 0...1 through the current focus (by active time) or break (by wall time).
    public func progress(_ d: Durations) -> Double {
        switch phase {
        case .focus: min(1, active / max(1, target))
        case .breakTime: min(1, elapsed / rest(d))
        default: 0
        }
    }

    public func remaining(_ d: Durations) -> TimeInterval {
        switch phase {
        case .focus: max(0, target - active)
        case .breakTime: max(0, rest(d) - elapsed)
        default: 0
        }
    }

    /// Tomatoes in the crate, fractional: 30 active minutes = two-thirds of one.
    public func harvest(_ d: Durations) -> Double { min(Double(d.perDay), dayActive / d.minutesPerTomato) }

    /// The day a moment belongs to: 4:00 local starts a new one, so a late night still counts as the same day.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-4 * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    // MARK: transitions

    /// A study app is open: arm, but do not start the clock.
    public mutating func arm(app: String, name: String? = nil) {
        guard phase == .idle || phase == .armed || phase == .dayDone else { return }
        if phase != .dayDone { phase = .armed }
        self.app = app; appName = name ?? app
    }

    /// Starts a session from anywhere but a running one. Returns false if a session is already under way.
    @discardableResult
    public mutating func startFocus(app: String, name: String? = nil, task: String?, taskId: String? = nil, target: TimeInterval? = nil, now: Date, _ d: Durations) -> Bool {
        guard phase != .focus else { return false }
        phase = .focus; self.app = app; appName = name ?? app; self.task = task; self.taskId = taskId
        self.target = target ?? d.focus
        elapsed = 0; active = 0; paused = false; lastTick = now; focusStartedAt = now
        return true
    }

    /// Moves the running session to another app or task without restarting the clock.
    public mutating func retag(app: String, name: String? = nil, task: String?, taskId: String?) {
        self.app = app; appName = name ?? app
        if let task, !task.isEmpty { self.task = task }
        if taskId != nil { self.taskId = taskId }
    }

    public mutating func pause(now: Date) {
        guard isTimed, !paused else { return }
        advance(to: now, working: false)
        paused = true; lastTick = nil
    }

    public mutating func resume(now: Date) {
        guard isPaused else { return }
        paused = false; lastTick = now
    }

    /// Emergency exit: stop the session; minutes already worked stay in the harvest.
    public mutating func stop(_ d: Durations) {
        phase = dayActive >= d.dayGoal ? .dayDone : .idle
        elapsed = 0; active = 0; paused = false; lastTick = nil; focusStartedAt = nil
    }

    /// Adds the seconds since the last tick: wall time always, active time only when working.
    /// A gap longer than 5 s (sleep, a stalled timer) counts as wall time but never as work.
    private mutating func advance(to now: Date, working: Bool) {
        guard let last = lastTick else { lastTick = now; return }
        let dt = max(0, now.timeIntervalSince(last))
        lastTick = now
        elapsed += dt
        if phase == .focus && working && dt <= 5 { active += dt; dayActive += dt }
    }

    public mutating func tick(now: Date, active working: Bool, _ d: Durations) -> [ScheduleEvent] {
        if DayState.dayKey(now) != day { self = DayState(day: DayState.dayKey(now)); return [.newDay] }
        guard isTimed, !paused else { return [] }
        var events: [ScheduleEvent] = []
        advance(to: now, working: working)
        if phase == .focus, active >= target {
            done += 1; events.append(.focusEnded(count: done))
            tasks = (tasks ?? []) + [task?.isEmpty == false ? task! : appName ?? app ?? "Focus"]
            focusStartedAt = nil
            phase = .breakTime; elapsed = 0; lastTick = now
            if dayActive >= d.dayGoal && !celebrated { celebrated = true; events.append(.dayDone) }
        }
        if phase == .breakTime, elapsed >= rest(d) {
            phase = celebrated ? .dayDone : .ready; elapsed = 0; lastTick = nil; events.append(.breakEnded)
        }
        return events
    }

    /// What gets written to disk: stopped, so a crash or quit reopens as paused at the last save.
    public func snapshot(at now: Date) -> DayState {
        var s = self
        if s.isTimed && !s.paused { s.paused = true; s.lastTick = nil }
        return s
    }
}

/// How cross Tomo gets, and when (D12 strict, D13 siren).
public enum Ladder {
    /// Test runs only (POMODORO_LADDER_SCALE): shrinks every threshold, so a live check takes seconds.
    public nonisolated(unsafe) static var timeScale = 1.0

    public enum Trouble: String, Sendable { case none, offTask, notWorking }
    public enum Stage: Int, Comparable, Sendable {
        case calm, nudge, hmmph, simmer, boil, siren
        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    /// `seconds` is how long the trouble has lasted. Off task: 10 s grace, nudge, hmmph at 22 s, simmer 44 s,
    /// boil 66 s, siren 116 s. Not working is only declared after 3 quiet minutes (the reading allowance, unchanged),
    /// so it starts at hmmph: simmer +80 s, boil +160 s, siren +330 s. (23 Oct: every gap 8 to 10 s shorter.)
    public static func stage(_ t: Trouble, seconds raw: Double) -> Stage {
        let s = raw / timeScale
        switch t {
        case .none: return .calm
        case .offTask: return s < 10 ? .calm : s < 22 ? .nudge : s < 44 ? .hmmph : s < 66 ? .simmer : s < 116 ? .boil : .siren
        case .notWorking: return s < 80 ? .hmmph : s < 160 ? .simmer : s < 330 ? .boil : .siren
        }
    }

    /// Not working means no keyboard or mouse for 60 s AND no progress for 3 min. Progress is the app's
    /// contract `activity` pings; an app that sends none is judged on input alone (3 min), so reading a
    /// slide while scrolling now and then still counts as work.
    public static func isWorking(inputIdle: Double, sinceProgress: Double?) -> Bool {
        let quiet = sinceProgress ?? inputIdle
        return !(inputIdle > 60 * timeScale && quiet > 180 * timeScale)
    }
}
