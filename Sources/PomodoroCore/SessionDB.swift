import Foundation
import SQLite3

/// Every session, kept locally in SQLite (`sessions.sqlite`), for insights and export. No network, ever.
public final class SessionDB: @unchecked Sendable {
    public struct Record: Equatable, Sendable {
        public var day: String, app: String, task: String, taskId: String?
        public var start: Date, end: Date
        public var active: Double, elapsed: Double, idle: Double, offTask: Double, paused: Double
        public var completed: Bool
        public init(day: String, app: String, task: String, taskId: String? = nil, start: Date, end: Date,
                    active: Double, elapsed: Double, idle: Double = 0, offTask: Double = 0, paused: Double = 0, completed: Bool) {
            self.day = day; self.app = app; self.task = task; self.taskId = taskId; self.start = start; self.end = end
            self.active = active; self.elapsed = elapsed; self.idle = idle; self.offTask = offTask; self.paused = paused; self.completed = completed
        }
    }

    private var db: OpaquePointer?
    public let url: URL

    public init(url: URL) {
        self.url = url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        sqlite3_open(url.path, &db)
        exec("""
        CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, day TEXT, app TEXT, task TEXT, task_id TEXT,
          start REAL, end REAL, active REAL, elapsed REAL, idle REAL, off_task REAL, paused REAL, completed INTEGER);
        CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, at REAL, day TEXT, type TEXT, app TEXT, detail TEXT);
        CREATE INDEX IF NOT EXISTS sessions_day ON sessions(day);
        """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public func add(_ r: Record) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO sessions (day, app, task, task_id, start, end, active, elapsed, idle, off_task, paused, completed) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, r.day, -1, transient); sqlite3_bind_text(st, 2, r.app, -1, transient); sqlite3_bind_text(st, 3, r.task, -1, transient)
        if let t = r.taskId { sqlite3_bind_text(st, 4, t, -1, transient) } else { sqlite3_bind_null(st, 4) }
        sqlite3_bind_double(st, 5, r.start.timeIntervalSince1970); sqlite3_bind_double(st, 6, r.end.timeIntervalSince1970)
        for (i, v) in [r.active, r.elapsed, r.idle, r.offTask, r.paused].enumerated() { sqlite3_bind_double(st, Int32(7 + i), v) }
        sqlite3_bind_int(st, 12, r.completed ? 1 : 0)
        sqlite3_step(st)
    }

    public func event(_ type: String, app: String?, detail: String?, at: Date) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO events (at, day, type, app, detail) VALUES (?,?,?,?,?)", -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, at.timeIntervalSince1970); sqlite3_bind_text(st, 2, DayState.dayKey(at), -1, transient)
        sqlite3_bind_text(st, 3, type, -1, transient)
        if let a = app { sqlite3_bind_text(st, 4, a, -1, transient) } else { sqlite3_bind_null(st, 4) }
        if let d = detail { sqlite3_bind_text(st, 5, d, -1, transient) } else { sqlite3_bind_null(st, 5) }
        sqlite3_step(st)
    }

    /// Sessions whose day falls in [from, to] (day keys, inclusive), oldest first.
    public func sessions(from: String, to: String) -> [Record] {
        var st: OpaquePointer?
        var out: [Record] = []
        guard sqlite3_prepare_v2(db, "SELECT day, app, task, task_id, start, end, active, elapsed, idle, off_task, paused, completed FROM sessions WHERE day >= ? AND day <= ? ORDER BY start", -1, &st, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, from, -1, transient); sqlite3_bind_text(st, 2, to, -1, transient)
        func text(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(Record(day: text(0) ?? "", app: text(1) ?? "", task: text(2) ?? "", taskId: text(3),
                              start: Date(timeIntervalSince1970: sqlite3_column_double(st, 4)), end: Date(timeIntervalSince1970: sqlite3_column_double(st, 5)),
                              active: sqlite3_column_double(st, 6), elapsed: sqlite3_column_double(st, 7), idle: sqlite3_column_double(st, 8),
                              offTask: sqlite3_column_double(st, 9), paused: sqlite3_column_double(st, 10), completed: sqlite3_column_int(st, 11) == 1))
        }
        return out
    }

    /// CSV of every session, for export.
    public func csv() -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["day,app,task,task_id,start,end,active_min,elapsed_min,idle_min,off_task_min,paused_min,completed"]
        for r in sessions(from: "0000", to: "9999") {
            let task = "\"" + r.task.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            lines.append([r.day, r.app, task, r.taskId ?? "", iso.string(from: r.start), iso.string(from: r.end),
                          String(format: "%.1f", r.active / 60), String(format: "%.1f", r.elapsed / 60), String(format: "%.1f", r.idle / 60),
                          String(format: "%.1f", r.offTask / 60), String(format: "%.1f", r.paused / 60), r.completed ? "1" : "0"].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
