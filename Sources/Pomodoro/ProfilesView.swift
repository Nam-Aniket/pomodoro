import SwiftUI
import PomodoroCore

/// Setup and Edit for focus profiles (DESIGN.md section 14): pick any installed app; if it is a browser, add
/// links and the profile becomes a website profile; tick what else may stay visible; pick a default length.
struct ProfilesView: View {
    @ObservedObject var m: Model
    @State var selection: String?
    @State var apps: [CatalogApp] = []
    @State var search = ""
    @State var link = ""
    var firstRun = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selection) {
                    ForEach(m.profiles) { p in
                        Label(p.name, systemImage: p.kind == .website ? "globe" : p.kind == .other ? "pencil" : "app").tag(p.id)
                    }
                }
                HStack {
                    Button { addProfile() } label: { Image(systemName: "plus") }
                    Button { removeSelected() } label: { Image(systemName: "minus") }.disabled(selection == nil || selection == "Other")
                    Spacer()
                }.buttonStyle(.borderless).padding(8)
            }
            .frame(width: 190)
            Divider()
            if let i = m.profiles.firstIndex(where: { $0.id == selection }) {
                editor(i).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 10) {
                    Text(firstRun ? "What do you want to focus on?" : "Pick a profile, or add one with +")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("A profile is an app (or a website in your browser) plus the few apps allowed to stay open while you work.")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: 320)
                    Button("Add a profile") { addProfile() }.buttonStyle(.borderedProminent).tint(Color(hex: 0xE8392B))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear {
            apps = AppCatalog.installed()
            if firstRun { addProfile() } else { selection = selection ?? m.profiles.first?.id }
        }
    }

    func binding(_ i: Int) -> Binding<Profile> {
        Binding(get: { m.profiles[i] }, set: { var all = m.profiles; all[i] = $0; m.saveProfiles(all) })
    }

    func app(_ id: String?) -> CatalogApp? { apps.first { $0.id == id } }

    @ViewBuilder func editor(_ i: Int) -> some View {
        let p = binding(i)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Name", text: p.name).font(.system(size: 20, weight: .bold, design: .rounded)).textFieldStyle(.plain)
                if p.wrappedValue.kind == .other {
                    Text("Other: you type the task when you start. Browsers and Preview stay open.").foregroundStyle(.secondary)
                } else {
                    section("Focus on") { targetPicker(p) }
                    if p.wrappedValue.kind == .website { section("Sites to track") { links(p) } }
                    section("Also allowed while you focus") { allowed(p) }
                }
                section("Default length") {
                    Picker("", selection: p.minutes) { ForEach([15, 25, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) } }
                        .pickerStyle(.segmented).frame(width: 380)
                }
                if p.wrappedValue.contractApp != nil {
                    Text("This app reports its own tasks, so the clock starts when you open a task in it.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
    }

    func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            c()
        }
    }

    func row(_ a: CatalogApp, trailing: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: AppCatalog.icon(for: a)).resizable().frame(width: 20, height: 20)
            Text(a.name)
            if let t = trailing { Text(t).font(.caption).foregroundStyle(.secondary) }
        }
    }

    func tierNote(_ a: CatalogApp) -> String {
        switch Browsers.tier(bundleID: a.id, url: a.url) {
        case .full: "reads the page address"
        case .titleOnly: "can't read the page address: judged on time in the browser"
        case .unsupported: "not supported"
        }
    }

    @ViewBuilder func targetPicker(_ p: Binding<Profile>) -> some View {
        let targetID = p.wrappedValue.kind == .website ? p.wrappedValue.browsers.first : p.wrappedValue.appID
        if let a = app(targetID) {
            HStack { row(a, trailing: a.isBrowser ? "website mode · " + tierNote(a) : nil); Spacer(); Button("Change") { var v = p.wrappedValue; v.appID = nil; v.browsers = []; v.kind = .app; p.wrappedValue = v } }
        } else {
            TextField("Search apps", text: $search).textFieldStyle(.roundedBorder).frame(width: 260)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { a in
                        Button { choose(a, p) } label: { row(a, trailing: a.isBrowser ? "browser" : nil) }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 200)
        }
    }

    func choose(_ a: CatalogApp, _ p: Binding<Profile>) {
        var v = p.wrappedValue
        if a.isBrowser { v.kind = .website; v.browsers = [a.id]; v.appID = nil }
        else { v.kind = .app; v.appID = a.id; v.browsers = [] }
        if v.name.isEmpty || v.name == "New profile" { v.name = a.name }
        // a browser target suggests nothing; an app target suggests no extras: the user ticks what they need
        p.wrappedValue = v; search = ""
    }

    @ViewBuilder func links(_ p: Binding<Profile>) -> some View {
        HStack {
            TextField("Paste a link, e.g. github.com/you/repo", text: $link).textFieldStyle(.roundedBorder).frame(width: 300)
                .onSubmit { addLink(p) }
            Button("Add") { addLink(p) }
        }
        ForEach(p.wrappedValue.domains, id: \.self) { d in
            HStack { Image(systemName: "globe"); Text(d); Spacer()
                Button { var v = p.wrappedValue; v.domains.removeAll { $0 == d }; p.wrappedValue = v } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless) }
        }
        Toggle("Count subdomains too (e.g. gist.\(p.wrappedValue.domains.first ?? "github.com"))", isOn: p.includeSubdomains)
        Text("Any page on these sites counts. Any other site is off track.").font(.caption).foregroundStyle(.secondary)
    }

    func addLink(_ p: Binding<Profile>) {
        guard let d = Domain.extract(from: link), !p.wrappedValue.domains.contains(d) else { link = ""; return }
        var v = p.wrappedValue; v.domains.append(d); p.wrappedValue = v; link = ""
    }

    @ViewBuilder func allowed(_ p: Binding<Profile>) -> some View {
        let target = p.wrappedValue.kind == .website ? p.wrappedValue.browsers.first : p.wrappedValue.appID
        let suggested = apps.filter { ($0.isBrowser || $0.group == .ai) && $0.id != target }
        let chosen = apps.filter { p.wrappedValue.allowed.contains($0.id) && !suggested.contains($0) }
        ForEach(suggested + chosen) { a in
            Toggle(isOn: Binding(get: { p.wrappedValue.allowed.contains(a.id) },
                                 set: { on in var v = p.wrappedValue; if on { v.allowed.append(a.id) } else { v.allowed.removeAll { $0 == a.id } }; p.wrappedValue = v })) { row(a) }
        }
        Menu("Add another app") {
            ForEach(apps.filter { !suggested.contains($0) && !p.wrappedValue.allowed.contains($0.id) && $0.id != target }) { a in
                Button(a.name) { var v = p.wrappedValue; v.allowed.append(a.id); p.wrappedValue = v }
            }
        }.frame(width: 200)
        Text("Claude, Terminal, Finder and System Settings always stay reachable.").font(.caption).foregroundStyle(.secondary)
    }

    func addProfile() {
        let p = Profile(id: UUID().uuidString, name: "New profile", kind: .app, minutes: 45)
        var all = m.profiles; all.insert(p, at: max(0, all.count - 1)); m.saveProfiles(all)
        selection = p.id
    }

    func removeSelected() {
        guard let s = selection, s != "Other" else { return }
        m.saveProfiles(m.profiles.filter { $0.id != s }); selection = m.profiles.first?.id
    }
}
