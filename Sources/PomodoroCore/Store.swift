import Foundation

/// state.json (the day) and sessions.jsonl (one line per finished session or nudge: the evidence log).
public struct Store: Sendable {
    public let root: URL
    public init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Pomodoro")) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var stateURL: URL { root.appendingPathComponent("state.json") }
    var logURL: URL { root.appendingPathComponent("sessions.jsonl") }

    public func save(_ s: DayState, now: Date) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(s.snapshot(at: now)).write(to: stateURL, options: .atomic)
    }

    /// Loads today's state, always paused. A different day or a missing file starts fresh;
    /// an unreadable file is kept as state.json.bad for a look later.
    public func load(now: Date) -> DayState {
        let today = DayState.dayKey(now)
        guard let data = try? Data(contentsOf: stateURL) else { return DayState(day: today) }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard var s = try? dec.decode(DayState.self, from: data) else {
            let bad = root.appendingPathComponent("state.json.bad")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: stateURL, to: bad)
            return DayState(day: today)
        }
        if s.day != today { return DayState(day: today) }
        if s.isTimed { s.paused = true }
        s.lastTick = nil
        return s
    }

    var harvestURL: URL { root.appendingPathComponent("full-harvests.json") }

    /// Days with all 5 tomatoes. A plain count, never a streak: a missed day subtracts nothing.
    public func fullHarvestDays() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(contentsOf: harvestURL))) ?? []
    }

    @discardableResult
    public func recordFullHarvest(day: String) -> Int {
        var days = fullHarvestDays()
        if !days.contains(day) { days.append(day); try? JSONEncoder().encode(days).write(to: harvestURL, options: .atomic) }
        return days.count
    }

    public func log(_ fields: [String: String]) {
        guard let line = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(line + Data("\n".utf8)); try? h.close()
        } else {
            try? (line + Data("\n".utf8)).write(to: logURL)
        }
    }
}
