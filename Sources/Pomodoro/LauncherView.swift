import SwiftUI
import PomodoroCore

/// The launcher Tomo opens on a tap: what to work on, for how long, and one-click doors to Insights,
/// Profiles and Settings. Drawn in Tomo's style instead of a native menu (23 Oct: "options appear as mac
/// dropdown - which is not great").
struct LauncherView: View {
    @ObservedObject var m: Model
    var close: () -> Void
    var openInsights: () -> Void
    var openProfiles: () -> Void
    var openSettings: () -> Void

    @State var picked: String?
    @State var minutes = 45
    @State var custom = false
    @State var task = ""
    @FocusState var taskFocused: Bool

    static let red = T.tomato, deep = T.tomato, cream = T.blush, ink = T.ink
    static let presets = [15, 25, 30, 45, 60, 90]

    var profile: Profile? { m.profiles.first { $0.id == picked } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("What are we growing?").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Self.ink)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(T.ink2) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(m.profiles) { p in tile(p) }
            }
            if profile?.kind == .other {
                TextField("What are you working on?", text: $task)
                    .textFieldStyle(.plain).font(.system(size: 14, design: .rounded))
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Self.cream))
                    .focused($taskFocused).onSubmit(go)
            }
            VStack(spacing: 6) {
                Text("How long? Twist the leaf.").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(T.ink2)
                TimerDial(minutes: $minutes, size: 200)
                Text("Eaten over \(minutes) active minutes · \(minutes * 100 / 45)% of a crate tomato")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(T.ink2)
            }.frame(maxWidth: .infinity)
            Button(action: go) {
                Text(startLabel).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(T.onTomato)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(canStart ? Self.red : Color.gray.opacity(0.4)))
            }
            .buttonStyle(.plain).disabled(!canStart).keyboardShortcut(.defaultAction)
            Divider()
            HStack(spacing: 8) {
                door("chart.bar.fill", "Insights", openInsights)
                door("square.grid.2x2.fill", "Profiles", openProfiles)
                door("gearshape.fill", "Settings", openSettings)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface).shadow(color: .black.opacity(0.18), radius: 18, y: 6))
        .onAppear {
            picked = m.current?.id ?? m.profiles.first?.id
            minutes = min(60, max(5, m.nextMinutes ?? profile.map(m.lastMinutes) ?? 45))
        }
        .onChange(of: picked) { _, _ in
            if let p = profile { minutes = min(60, max(5, m.lastMinutes(p))) }
            if profile?.kind == .other { taskFocused = true }
        }
    }

    var canStart: Bool { profile != nil && (profile?.kind != .other || !task.trimmingCharacters(in: .whitespaces).isEmpty) }

    var startLabel: String {
        guard let p = profile else { return "Pick something" }
        if let w = m.pending, w.profile == p.id { return "Start \(w.task ?? p.name) · \(minutes) min" }   // its task is already open
        switch p.kind {
        case .other: return "Start \(minutes) minutes"
        case .website: return "Open \(p.domains.first ?? p.name) · \(minutes) min"
        case .app: return p.contractApp != nil ? "Open \(p.name) · \(minutes) min" : "Start \(p.name) · \(minutes) min"
        }
    }

    func go() {
        guard canStart, let p = profile else { return }
        m.launch(p, minutes: minutes, task: task)
        close()
    }

    func tile(_ p: Profile) -> some View {
        let on = picked == p.id
        return Button { picked = p.id } label: {
            HStack(spacing: 10) {
                icon(p).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Self.ink).lineLimit(1)
                    Text(subtitle(p)).font(.system(size: 10.5, design: .rounded)).foregroundStyle(T.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Self.cream : T.fill))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Self.red : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder func icon(_ p: Profile) -> some View {
        if p.kind == .app, let id = p.appID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: p.kind == .website ? "globe" : "pencil.line")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Self.deep)
                .frame(width: 30, height: 30).background(Circle().fill(Self.cream))
        }
    }

    func subtitle(_ p: Profile) -> String {
        switch p.kind {
        case .other: "type your task"
        case .website: p.domains.isEmpty ? "add sites in Profiles" : p.domains.joined(separator: ", ")
        case .app: p.contractApp != nil ? "starts with a task" : "\(p.minutes) min default"
        }
    }

    func chip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(on ? T.onTomato : Self.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(on ? Self.red : T.fill))
        }.buttonStyle(.plain)
    }

    func roundButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Self.deep)
                .frame(width: 30, height: 30).background(Circle().fill(Self.cream))
        }.buttonStyle(.plain)
    }

    func door(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { close(); action() } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Self.deep)
                Text(label).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(Self.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(T.fill))
        }.buttonStyle(.plain)
    }
}
