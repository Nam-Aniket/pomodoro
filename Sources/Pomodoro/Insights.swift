import Charts
import SQLite3
import SwiftUI
import UniformTypeIdentifiers
import PomodoroCore

/// The control panel: where the active minutes went, white with Tomo's colours.
struct InsightsView: View {
    let db: SessionDB
    let store: Store
    /// ImageRenderer cannot draw a ScrollView, so the `--insights` render lays the page out flat.
    var forRender = false
    enum Range: String, CaseIterable { case today = "Today", week = "Week", month = "Month" }
    @State var range: Range
    @State var refresh = 0

    init(db: SessionDB, store: Store, range: Range = .today, forRender: Bool = false) {
        self.db = db; self.store = store; self.forRender = forRender
        _range = State(initialValue: range)
    }

    // MARK: palette and type

    static let red = T.tomatoBright, deep = T.tomato, leaf = T.leaf
    static let cream = T.blush, ink = T.ink, muted = T.ink2
    static let goalMinutes = 225.0, tomatoMinutes = 45.0

    static let warm: [UInt32] = [0xC9A43A, 0xD4775A, 0xB5651D, 0xE07A8F, 0x9C6B4E, 0xD99A2B, 0xA8455A]
    static func colour(_ app: String) -> Color {
        switch app {
        case "HackerSolve": return Color(hex: 0xE8392B)
        case "SpeakFit": return Color(hex: 0xFB8C00)
        case "NorthstarViewer", "Northstar": return Color(hex: 0x3F8F3A)
        default:
            // djb2: stable across launches, unlike hashValue
            let h = app.unicodeScalars.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ $1.value }
            return Color(hex: warm[Int(h % UInt32(warm.count))])
        }
    }
    static func name(_ app: String) -> String { app == "NorthstarViewer" ? "Northstar" : app }
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }

    // MARK: days

    /// Noon of the app's current day (the day starts at 4:00), so stepping back by days never trips on DST.
    static func dayNoon(_ now: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: now.addingTimeInterval(-4 * 3600)) ?? now
    }
    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    /// Day noons in the range, oldest first.
    var dates: [Date] {
        let n = range == .today ? 1 : range == .week ? 7 : 30, base = Self.dayNoon()
        return (0..<n).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: base) }
    }
    var span: (from: String, to: String) { (Self.key(dates.first!), Self.key(dates.last!)) }

    // MARK: derived data

    struct TaskRow: Identifiable { let id: String; let app: String; let task: String; let taskId: String?; let active: Double; let sessions: Int }

    static func tasks(_ rows: [SessionDB.Record]) -> [TaskRow] {
        Dictionary(grouping: rows) { "\($0.app)|\($0.task.trimmingCharacters(in: .whitespaces).lowercased())" }
            .map { key, rs in TaskRow(id: key, app: rs[0].app, task: rs[0].task.isEmpty ? "Untitled" : rs[0].task,
                                      taskId: rs.compactMap(\.taskId).last, active: rs.map(\.active).reduce(0, +), sessions: rs.count) }
            .sorted { $0.active > $1.active }
    }

    /// A session as you lived it: consecutive segments of one app and task (a retitle, a pause) joined when the
    /// gap is under 2 minutes. 0.5.0 listed every 2-second segment as its own "0 active min" row (24 Oct).
    struct Session: Identifiable { var id: Date { start }; let app: String; let task: String; let start: Date; var end: Date; var active: Double }
    static func merged(_ rows: [SessionDB.Record]) -> [Session] {
        var out: [Session] = []
        for r in rows.sorted(by: { $0.start < $1.start }) {
            let task = r.task.isEmpty ? name(r.app) : r.task
            if var last = out.last, last.app == r.app, last.task == task, r.start.timeIntervalSince(last.end) < 120 {
                last.end = max(last.end, r.end); last.active += r.active; out[out.count - 1] = last
            } else { out.append(Session(app: r.app, task: task, start: r.start, end: r.end, active: r.active)) }
        }
        return out
    }

    /// Apps Tomo had to hide mid-session, most often first: what actually pulled you away.
    static func distractions(_ url: URL, from: String, to: String) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:], handle: OpaquePointer?, st: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(handle); return [] }
        defer { sqlite3_close(handle) }
        guard sqlite3_prepare_v2(handle, "SELECT detail FROM events WHERE type IN ('hidden', 'hide-poll') AND day >= ? AND day <= ?", -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(st, 1, from, -1, transient); sqlite3_bind_text(st, 2, to, -1, transient)
        while sqlite3_step(st) == SQLITE_ROW {
            guard let d = sqlite3_column_text(st, 0).map({ String(cString: $0) }) else { continue }
            let id = String(d.split(separator: ":").first ?? "")
            counts[id, default: 0] += 1
        }
        return counts.map { id, n in
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
            return (name, n)
        }.sorted { $0.count > $1.count }
    }

    struct Reactions { var nudges = 0, hmmphs = 0, boils = 0, sirens = 0, hidden = 0 }

    /// Reaction counts from the events table, opened read-only so the app's own connection is untouched.
    static func reactions(_ url: URL, from: String, to: String) -> Reactions {
        var r = Reactions(), handle: OpaquePointer?, st: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(handle); return r }
        defer { sqlite3_close(handle) }
        guard sqlite3_prepare_v2(handle, "SELECT type, detail FROM events WHERE day >= ? AND day <= ?", -1, &st, nil) == SQLITE_OK else { return r }
        defer { sqlite3_finalize(st) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(st, 1, from, -1, transient); sqlite3_bind_text(st, 2, to, -1, transient)
        while sqlite3_step(st) == SQLITE_ROW {
            let type = sqlite3_column_text(st, 0).map { String(cString: $0) } ?? ""
            let detail = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            switch type {
            case "stage-nudge": r.nudges += 1
            case "stage-hmmph": r.hmmphs += 1
            case "stage-boil": r.boils += 1
            case "stage-siren": r.sirens += 1
            case "hidden": r.hidden += 1
            case "hid-at-start": r.hidden += max(1, detail.split(separator: ",").count)   // one event lists every app it hid
            default: break
            }
        }
        return r
    }

    // MARK: body

    var body: some View {
        _ = refresh
        let rows = db.sessions(from: span.from, to: span.to)
        let page = content(rows).padding(24).padding(.top, forRender ? 0 : 20).frame(maxWidth: .infinity, alignment: .topLeading)   // room for the traffic lights
        return Group {
            if forRender { page.frame(width: 760).fixedSize(horizontal: false, vertical: true) }
            else { ScrollView(.vertical) { page } }
        }
        .frame(minWidth: 760, minHeight: forRender ? 0 : 640)
        .background(T.paper)
        .onAppear { refresh += 1 }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }

    @ViewBuilder func content(_ rows: [SessionDB.Record]) -> some View {
        let today = range == .today ? rows : db.sessions(from: Self.key(Self.dayNoon()), to: Self.key(Self.dayNoon()))
        VStack(alignment: .leading, spacing: 16) {
            header
            if !rows.isEmpty { answer(rows) }
            hero(rows, today: today)
            if rows.isEmpty {
                emptyState
            } else if range == .today {
                pair { byTask(rows) } _: { leaks(rows) }
                sessionsToday(rows)
            } else {
                dailyBars(rows)
                pair { byTask(rows) } _: { leaks(rows) }
                if range == .month { heatCalendar }
            }
        }
    }

    /// Two cards side by side, stretched to the taller one.
    func pair<A: View, B: View>(@ViewBuilder _ a: () -> A, @ViewBuilder _ b: () -> B) -> some View {
        HStack(alignment: .top, spacing: 16) { a().frame(maxHeight: .infinity, alignment: .top); b().frame(maxHeight: .infinity, alignment: .top) }
            .fixedSize(horizontal: false, vertical: true)
    }

    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights").font(Self.font(28, .bold)).foregroundStyle(Self.ink)
                Text(subtitle).font(Self.font(12)).foregroundStyle(Self.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(Range.allCases, id: \.self) { r in
                    Text(r.rawValue).font(Self.font(13, .semibold))
                        .foregroundStyle(range == r ? T.onTomato : Self.ink)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(range == r ? Self.red : Color.clear))
                        .contentShape(Capsule())
                        .onTapGesture { range = r }
                }
            }
            .padding(4).background(Capsule().fill(Self.cream))
            Text("Export CSV").font(Self.font(13, .semibold)).foregroundStyle(Self.deep)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().strokeBorder(Self.red.opacity(0.4), lineWidth: 1))
                .contentShape(Capsule())
                .onTapGesture { export() }
        }
    }

    var subtitle: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return range == .today ? "Today, \(f.string(from: dates[0])) · finished sessions only"
            : "\(f.string(from: dates.first!)) to \(f.string(from: dates.last!)) · finished sessions only"
    }

    // MARK: cards

    /// The page's answer in one sentence, before any chart (one question per card, the answer first).
    func answer(_ rows: [SessionDB.Record]) -> some View {
        let active = rows.map(\.active).reduce(0, +) / 60, off = rows.map(\.offTask).reduce(0, +) / 60
        let idle = rows.map(\.idle).reduce(0, +) / 60, top = Self.tasks(rows).first
        let leak = off >= idle ? ("time off task", off) : ("idle time", idle)
        var text: String
        if range == .today {
            text = "\(Int(active)) active minutes today, \(Int(100 * active / Self.goalMinutes))% of your \(Int(Self.goalMinutes))-minute goal."
        } else {
            let n = Double(dates.count), avg = active / n
            let prev = db.sessions(from: Self.key(Calendar.current.date(byAdding: .day, value: -dates.count, to: dates.first!)!),
                                   to: Self.key(Calendar.current.date(byAdding: .day, value: -1, to: dates.first!)!))
            let prevAvg = prev.map(\.active).reduce(0, +) / 60 / n
            text = "\(Int(avg)) active minutes a day on average"
            text += prev.isEmpty ? "." : avg >= prevAvg ? ", up \(Int(avg - prevAvg)) on the \(range == .week ? "week" : "month") before." : ", down \(Int(prevAvg - avg)) on the \(range == .week ? "week" : "month") before."
        }
        if let t = top, t.active >= 60 { text += " Most went to \(t.task == Self.name(t.app) ? t.task : "\(t.task) (\(Self.name(t.app)))")." }
        if leak.1 >= 1 { text += " The biggest leak was \(leak.0): \(Int(leak.1)) min." }
        return Text(text).font(Self.font(16, .semibold)).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    func card<C: View>(_ title: String, _ note: String? = nil, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Self.font(15, .bold)).foregroundStyle(Self.ink).fixedSize()
                Spacer()
                if let note { Text(note).font(Self.font(11)).foregroundStyle(Self.muted).lineLimit(1) }
            }
            body()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface)
            .shadow(color: Self.ink.opacity(0.08), radius: 8, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Self.red.opacity(0.08), lineWidth: 1))
    }

    func stat(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Self.font(12, .semibold)).foregroundStyle(Self.muted)
            Text(value).font(Self.font(26, .bold)).foregroundStyle(Self.deep).lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(Self.font(11)).foregroundStyle(Self.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.cream))
    }

    func hero(_ rows: [SessionDB.Record], today: [SessionDB.Record]) -> some View {
        let todayMin = today.map(\.active).reduce(0, +) / 60
        let active = rows.map(\.active).reduce(0, +), elapsed = rows.map(\.elapsed).reduce(0, +)
        let full = store.fullHarvestDays().filter { $0 >= span.from && $0 <= span.to }.count
        let n = Double(dates.count)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's harvest").font(Self.font(12, .semibold)).foregroundStyle(Self.muted)
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { i in
                        TomatoSlot(fill: min(1, max(0, (todayMin - Double(i) * Self.tomatoMinutes) / Self.tomatoMinutes)))
                            .frame(width: 34, height: 38)
                    }
                }
                Text("\(Int(todayMin)) of \(Int(Self.goalMinutes)) active min · \(String(format: "%.1f", todayMin / Self.tomatoMinutes)) tomatoes")
                    .font(Self.font(11)).foregroundStyle(Self.muted)
            }
            .padding(16).frame(width: 250, height: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.cream))
            stat("Active time", hm(active), range == .today ? "goal \(Int(Self.goalMinutes)) min a day"
                 : "avg \(Int(active / 60 / n)) min a day · goal \(Int(Self.goalMinutes))")
            stat("Kept on task", elapsed > 0 ? "\(Int((100 * active / elapsed).rounded()))%" : "–",
                 elapsed > 0 ? "\(hm(active)) of \(hm(elapsed)) was real work" : "shows after your first session")
            if range != .today { stat("Full days", "\(full)", "days all 5 tomatoes grew") }
        }
    }

    func sessionsToday(_ rows: [SessionDB.Record]) -> some View {
        let f = DateFormatter(); f.dateFormat = "H:mm"
        let all = Self.merged(rows), shown = all.filter { $0.active >= 60 }, short = all.count - shown.count
        return card("Sessions today", short > 0 ? "\(short) under a minute not shown" : nil) {
            if shown.isEmpty {
                Text("No session reached a full active minute yet.").font(Self.font(12)).foregroundStyle(Self.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shown) { r in
                    HStack(spacing: 8) {
                        Circle().fill(Self.colour(r.app)).frame(width: 8, height: 8)
                        Text("\(f.string(from: r.start))–\(f.string(from: r.end))").font(Self.font(12, .semibold).monospacedDigit())
                            .foregroundStyle(Self.ink).frame(width: 84, alignment: .leading)
                        Text(r.task).font(Self.font(12)).foregroundStyle(Self.ink).lineLimit(1)
                        if r.task != Self.name(r.app) { Text(Self.name(r.app)).font(Self.font(11)).foregroundStyle(Self.muted) }
                        Spacer()
                        Text("\(Int(r.active / 60)) active min").font(Self.font(12).monospacedDigit()).foregroundStyle(Self.ink)
                    }
                }
            }
        }
    }

    func dailyBars(_ rows: [SessionDB.Record]) -> some View {
        let f = DateFormatter(); f.dateFormat = range == .week ? "EEE d" : "d"
        let labels = dates.map { (Self.key($0), f.string(from: $0)) }
        let apps = Array(Set(rows.map(\.app))).sorted()
        let byDayApp = Dictionary(grouping: rows) { "\($0.day)|\($0.app)" }.mapValues { $0.map(\.active).reduce(0, +) / 60 }
        let dayTotal = Dictionary(grouping: rows, by: \.day).mapValues { $0.map(\.active).reduce(0, +) / 60 }
        let bars = labels.flatMap { k, label in apps.compactMap { a in byDayApp["\(k)|\(a)"].map { DayBar(id: k + a, day: label, app: Self.name(a), minutes: $0) } } }
        return card("Active minutes per day", "dashed line = 225 min goal") {
            Chart {
                ForEach(bars) { b in
                    BarMark(x: .value("Day", b.day), y: .value("Active minutes", b.minutes))
                        .foregroundStyle(by: .value("App", b.app)).cornerRadius(3)
                }
                RuleMark(y: .value("Goal", Self.goalMinutes))
                    .foregroundStyle(Self.deep.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("goal").font(Self.font(10, .semibold)).foregroundStyle(Self.deep) }
            }
            .chartXScale(domain: labels.map(\.1))
            .chartYScale(domain: 0...max(Self.goalMinutes + 30, (dayTotal.values.max() ?? 0) * 1.1))
            .chartForegroundStyleScale(domain: apps.map(Self.name), range: apps.map(Self.colour))
            .chartXAxis {
                // a month of day numbers is too dense: label every third day, no vertical grid
                AxisMarks(values: labels.enumerated().filter { range == .week || $0.offset % 3 == 2 }.map(\.element.1)) { _ in
                    AxisValueLabel(centered: true).font(Self.font(10))
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 220)
        }
    }

    struct DayBar: Identifiable { let id: String; let day: String; let app: String; let minutes: Double }

    func byTask(_ rows: [SessionDB.Record]) -> some View {
        let real = Self.tasks(rows).filter { $0.active >= 60 }, short = Self.tasks(rows).count - real.count
        let top = Array(real.prefix(6)), most = max(1, top.first?.active ?? 1)
        let note = [real.count > 6 ? "top 6 of \(real.count)" : nil, short > 0 ? "+\(short) under a minute" : nil].compactMap { $0 }.joined(separator: " · ")
        return card("What you worked on", note.isEmpty ? nil : note) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(top) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(t.task).font(Self.font(13, .semibold)).foregroundStyle(Self.ink).lineLimit(1)
                            if t.task != Self.name(t.app) { Text(Self.name(t.app)).font(Self.font(11)).foregroundStyle(Self.muted) }
                            Spacer()
                            Text(hm(t.active))
                                .font(Self.font(12).monospacedDigit()).foregroundStyle(Self.ink)
                        }
                        Segments(parts: [(t.active / most, Self.colour(t.app))], track: Self.cream).frame(height: 10)
                    }
                }
            }
        }
    }

    var heatCalendar: some View {
        // Last 30 days on a Monday-first calendar, so the weeks line up.
        let base = Self.dayNoon(), cal = Calendar.current
        let first = cal.date(byAdding: .day, value: -29, to: base)!
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: first)!
        let total = lead + 30, weeks = (total + 6) / 7
        let rows = db.sessions(from: Self.key(first), to: Self.key(base))
        let minutes = Dictionary(grouping: rows, by: \.day).mapValues { $0.map(\.active).reduce(0, +) / 60 }
        return card("Last 30 days") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                        Text(d).font(Self.font(10, .semibold)).foregroundStyle(Self.muted).frame(width: 28)
                    }
                }
                ForEach(0..<weeks, id: \.self) { w in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let i = w * 7 + d, date = cal.date(byAdding: .day, value: i, to: start)!
                            let inRange = i >= lead && i < total, m = minutes[Self.key(date)] ?? 0
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(inRange ? Self.heat(m) : Color.clear)
                                .overlay(Text(inRange ? "\(cal.component(.day, from: date))" : "")
                                    .font(Self.font(10, .semibold)).foregroundStyle(m >= Self.goalMinutes * 0.6 ? Color.white : Self.muted))
                                .frame(width: 28, height: 24)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("0").font(Self.font(10)).foregroundStyle(Self.muted)
                    ForEach([0, 45, 112, 180, 225], id: \.self) { m in
                        RoundedRectangle(cornerRadius: 3).fill(Self.heat(Double(m))).frame(width: 14, height: 10)
                    }
                    Text("225+ min").font(Self.font(10)).foregroundStyle(Self.muted)
                }.padding(.top, 4)
            }
        }
        .frame(width: 260)
    }

    static func heat(_ minutes: Double) -> Color {
        minutes <= 0 ? Color(hex: 0xF4EDEA) : minutes >= goalMinutes ? deep : red.opacity(0.18 + 0.72 * minutes / goalMinutes)
    }

    func leaks(_ rows: [SessionDB.Record]) -> some View {
        let a = rows.map(\.active).reduce(0, +), i = rows.map(\.idle).reduce(0, +)
        let o = rows.map(\.offTask).reduce(0, +), p = rows.map(\.paused).reduce(0, +)
        let total = max(1, a + i + o)   // paused time is not a leak: it is shown in the note, not the bar
        let parts: [(String, Double, Color)] = [("Working", a, Self.red), ("Off task", o, Color(hex: 0xFB8C00)), ("Idle", i, Color(hex: 0xF2A99F))]
        let away = Self.distractions(db.url, from: span.from, to: span.to).prefix(3)
        let r = Self.reactions(db.url, from: span.from, to: span.to)
        return card("Where session time went", p >= 60 ? "\(hm(total)) · \(hm(p)) paused" : hm(total)) {
            Segments(parts: parts.map { ($0.1 / total, $0.2) }, track: Self.cream).frame(height: 14)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(parts, id: \.0) { name, sec, c in
                    HStack(spacing: 6) {
                        Circle().fill(c).frame(width: 8, height: 8)
                        Text(name).font(Self.font(12)).foregroundStyle(Self.ink)
                        Spacer()
                        Text("\(hm(sec)) · \(Int((100 * sec / total).rounded()))%").font(Self.font(12).monospacedDigit()).foregroundStyle(Self.ink)
                    }
                }
            }
            if !away.isEmpty {
                Text("What pulled you away").font(Self.font(12, .semibold)).foregroundStyle(Self.muted).padding(.top, 4)
                Text(away.map { "\($0.name) \($0.count)×" }.joined(separator: " · ")).font(Self.font(12)).foregroundStyle(Self.ink)
            }
            if r.nudges + r.sirens > 0 {
                Text("Tomo nudged you \(r.nudges) time\(r.nudges == 1 ? "" : "s") and reached the siren \(r.sirens).")
                    .font(Self.font(11)).foregroundStyle(Self.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var emptyState: some View {
        card("Nothing to show yet") {
            HStack(alignment: .top, spacing: 16) {
                TomatoSlot(fill: 0).frame(width: 56, height: 62)
                VStack(alignment: .leading, spacing: 8) {
                    Text(range == .today ? "No finished sessions today." : "No finished sessions in the last \(dates.count) days.")
                        .font(Self.font(14, .semibold)).foregroundStyle(Self.ink)
                    step(1, "Tap Tomo, pick what you're focusing on, twist the timer and press Start.")
                    step(2, "Work. Tomo counts only active minutes: 45 grow one tomato, 225 fill the day.")
                    step(3, "When a session ends it lands here. This page refreshes every 30 seconds.")
                }
            }
        }
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(Self.font(11, .bold)).foregroundStyle(.white).frame(width: 18, height: 18).background(Circle().fill(Self.red))
            Text(text).font(Self.font(12)).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    func hm(_ s: Double) -> String { let m = Int(s / 60); return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }

    func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "pomodoro-sessions.csv"; p.allowedContentTypes = [.commaSeparatedText]
        if p.runModal() == .OK, let url = p.url { try? db.csv().write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// A rounded horizontal bar of coloured parts (fractions of the full width) over a track.
struct Segments: View {
    let parts: [(Double, Color)]
    let track: Color
    var body: some View {
        Canvas { ctx, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            ctx.fill(shape, with: .color(track))
            ctx.clip(to: shape)
            var x: CGFloat = 0
            for (f, c) in parts where f > 0 {
                let w = size.width * min(1, f)
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(c))
                x += w
            }
        }
    }
}

/// One harvest slot: an empty tomato outline whose red fill rises with active minutes.
struct TomatoSlot: View {
    let fill: Double
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height * 0.9) / 2
            let c = CGPoint(x: size.width / 2, y: size.height - r - 1)
            let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.92, width: 2 * r, height: 1.84 * r))
            ctx.fill(body, with: .color(.white))
            var inner = ctx
            inner.clip(to: body)
            let top = c.y + r * 0.92 - 1.84 * r * fill
            inner.fill(Path(CGRect(x: 0, y: top, width: size.width, height: size.height)), with: .color(InsightsView.red))
            if fill >= 1 {
                inner.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.35, height: r * 0.22)), with: .color(.white.opacity(0.45)))
            }
            ctx.stroke(body, with: .color(fill > 0 ? InsightsView.deep : InsightsView.red.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1.5, dash: fill > 0 ? [] : [3, 2.5]))
            // leaf crown and stem
            let leafY = c.y - r * 0.92
            var leaf = Path()
            for dx in [-0.42, 0.0, 0.42] {
                leaf.addEllipse(in: CGRect(x: c.x + r * dx - r * 0.24, y: leafY - r * 0.12, width: r * 0.48, height: r * 0.24))
            }
            let green = fill > 0 ? InsightsView.leaf : InsightsView.leaf.opacity(0.35)
            ctx.fill(leaf, with: .color(green))
            ctx.fill(Path(roundedRect: CGRect(x: c.x - 1.5, y: leafY - r * 0.42, width: 3, height: r * 0.36), cornerRadius: 1.5), with: .color(green))
        }
    }
}
