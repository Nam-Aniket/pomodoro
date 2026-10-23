import Charts
import SwiftUI
import UniformTypeIdentifiers
import PomodoroCore

/// The control panel's insights: where the active minutes went, white with Tomo's colours.
struct InsightsView: View {
    let db: SessionDB
    let store: Store
    enum Range: String, CaseIterable { case today = "Today", week = "Week", month = "Month" }
    @State var range = Range.today
    @State var refresh = 0

    static let ink = Color(hex: 0x3A1512)
    static func colour(_ app: String) -> Color {
        switch app {
        case "HackerSolve": Color(hex: 0xE8392B)
        case "SpeakFit": Color(hex: 0xFB8C00)
        case "NorthstarViewer": Color(hex: 0x3F8F3A)
        default: Color(hex: 0xC9A43A)
        }
    }
    static func name(_ app: String) -> String { app == "NorthstarViewer" ? "Northstar" : app }

    var days: (from: String, to: String, count: Int) {
        let now = Date(), today = DayState.dayKey(now)
        switch range {
        case .today: return (today, today, 1)
        case .week: return (DayState.dayKey(now.addingTimeInterval(-6 * 86400)), today, 7)
        case .month: return (DayState.dayKey(now.addingTimeInterval(-29 * 86400)), today, 30)
        }
    }

    var rows: [SessionDB.Record] { _ = refresh; return db.sessions(from: days.from, to: days.to) }

    struct TaskRow: Identifiable { let id: String; let app: String; let task: String; let active: Double; let elapsed: Double; let sessions: Int }

    var tasks: [TaskRow] {
        Dictionary(grouping: rows) { "\($0.app)|\($0.task.trimmingCharacters(in: .whitespaces).lowercased())" }
            .map { key, rs in TaskRow(id: key, app: rs[0].app, task: rs[0].task, active: rs.map(\.active).reduce(0, +),
                                      elapsed: rs.map(\.elapsed).reduce(0, +), sessions: rs.filter(\.completed).count) }
            .sorted { $0.active > $1.active }
    }

    var body: some View {
        let rs = rows
        let active = rs.map(\.active).reduce(0, +)
        let elapsed = rs.map(\.elapsed).reduce(0, +)
        let fullDays = store.fullHarvestDays().filter { $0 >= days.from && $0 <= days.to }.count
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Insights").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Self.ink)
                Spacer()
                Picker("", selection: $range) { ForEach(Range.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).frame(width: 240)
                Button("Export CSV") { export() }
            }
            HStack(spacing: 12) {
                tile("Active time", hm(active), "only minutes you were actually working")
                tile("Tomatoes", String(format: "%.1f", active / (45 * 60)), "45 active minutes each")
                tile("Focus quality", elapsed > 0 ? "\(Int(100 * active / elapsed))%" : "–", "active ÷ time in sessions")
                tile("Full harvests", "\(fullDays)", range == .today ? "today" : "days with 225 min")
            }
            if rs.isEmpty {
                Spacer()
                Text("No sessions here yet. Tap Tomo, pick what you're working on, and this fills in.")
                    .font(.system(size: 14, design: .rounded)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                chart(rs).frame(height: 220)
                taskTable
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 560)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear { refresh += 1 }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }

    func hm(_ s: Double) -> String { let m = Int(s / 60); return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }

    func tile(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0xC92A22))
            Text(note).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xFFF5F2)))
    }

    @ViewBuilder func chart(_ rs: [SessionDB.Record]) -> some View {
        if range == .today {
            Chart(tasks) { t in
                BarMark(x: .value("Active minutes", t.active / 60), y: .value("Task", t.task))
                    .foregroundStyle(Self.colour(t.app)).cornerRadius(5)
            }
            .chartXAxisLabel("Active minutes")
        } else {
            Chart(rs.indices, id: \.self) { i in
                BarMark(x: .value("Day", String(rs[i].day.suffix(5))), y: .value("Active minutes", rs[i].active / 60))
                    .foregroundStyle(by: .value("App", Self.name(rs[i].app))).cornerRadius(3)
            }
            .chartForegroundStyleScale(["HackerSolve": Self.colour("HackerSolve"), "SpeakFit": Self.colour("SpeakFit"),
                                        "Northstar": Self.colour("NorthstarViewer"), "Other": Self.colour("Other")])
            .chartYAxisLabel("Active minutes")
        }
    }

    var taskTable: some View {
        VStack(spacing: 0) {
            HStack { Text("Task").frame(maxWidth: .infinity, alignment: .leading); Text("Active").frame(width: 90); Text("Sessions").frame(width: 70); Text("Quality").frame(width: 70) }
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).padding(.vertical, 6)
            Divider()
            ScrollView {
                ForEach(tasks) { t in
                    HStack {
                        Circle().fill(Self.colour(t.app)).frame(width: 8, height: 8)
                        Text(t.task).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(hm(t.active)).frame(width: 90)
                        Text("\(t.sessions)").frame(width: 70)
                        Text(t.elapsed > 0 ? "\(Int(100 * t.active / t.elapsed))%" : "–").frame(width: 70)
                    }
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(Self.ink).padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "pomodoro-sessions.csv"; p.allowedContentTypes = [.commaSeparatedText]
        if p.runModal() == .OK, let url = p.url { try? db.csv().write(to: url, atomically: true, encoding: .utf8) }
    }
}
