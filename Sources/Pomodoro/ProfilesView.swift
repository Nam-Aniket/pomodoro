import SwiftUI
import PomodoroCore

/// Setup and Edit for focus profiles, on the design system (DESIGN.md sections 14 and 15): a sidebar of
/// profiles with their real icons, and a detail of cards. Pick any app; pick a browser and add links to make a
/// website profile; tick what may stay open; twist the dial for the default length.
struct ProfilesView: View {
    @ObservedObject var m: Model
    @State var selection: String?
    @State var apps: [CatalogApp] = []
    @State var search = ""
    @State var moreSearch = ""
    @State var showMore = false
    @State var link = ""
    /// A profile being created: it lives only here until Save, so a half-made one never reaches the launcher.
    @State var draft: Profile?
    @State var step = 0
    @State var savedAt: Date?
    var firstRun = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232).disabled(draft != nil).opacity(draft != nil ? 0.5 : 1)
            Rectangle().fill(T.line).frame(width: 1)
            if draft != nil {
                creator
            } else if let i = m.profiles.firstIndex(where: { $0.id == selection }) {
                ScrollView { detail(i).padding(.horizontal, T.s5).padding(.bottom, T.s5) }
            } else {
                empty.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(T.paper)
        .onAppear {
            apps = AppCatalog.installed()
            if firstRun { addProfile() } else { selection = selection ?? m.profiles.first { $0.kind != .other }?.id }
        }
    }

    // MARK: sidebar

    var sidebar: some View {
        VStack(alignment: .leading, spacing: T.s1) {
            Text("Profiles").font(T.title()).foregroundStyle(T.ink).padding(.top, 40).padding(.horizontal, T.s4).padding(.bottom, T.s2)
            ScrollView {
                VStack(spacing: 2) { ForEach(m.profiles) { p in sidebarRow(p) } }.padding(.horizontal, T.s2)
            }
            Spacer(minLength: 0)
            PButton(title: "New profile", symbol: "plus", kind: .ghost) { addProfile() }.padding(T.s3)
        }
        .background(T.fill.opacity(0.55))
    }

    func sidebarRow(_ p: Profile) -> some View {
        let on = selection == p.id
        return Button { selection = p.id } label: {
            HStack(spacing: T.s2 + 2) {
                profileIcon(p, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(T.body()).fontWeight(on ? .semibold : .regular).foregroundStyle(T.ink).lineLimit(1)
                    Text(kindLabel(p)).font(T.caption()).foregroundStyle(T.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, T.s2 + 2).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: T.rRow, style: .continuous).fill(on ? T.blush : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder func profileIcon(_ p: Profile, size: CGFloat) -> some View {
        switch p.kind {
        case .app: AppIcon(bundleID: p.appID, symbol: "app.dashed", size: size)
        case .website: AppIcon(bundleID: nil, symbol: "globe", size: size)
        case .other: AppIcon(bundleID: nil, symbol: "pencil.line", size: size)
        }
    }

    func kindLabel(_ p: Profile) -> String {
        switch p.kind {
        case .other: "type your task"
        case .website: p.domains.isEmpty ? "website · add links" : p.domains.joined(separator: ", ")
        case .app: p.appID == nil ? "pick an app" : "\(m.lastMinutes(p)) min"
        }
    }

    var empty: some View {
        VStack(spacing: T.s3) {
            AppIcon(bundleID: nil, symbol: "leaf", size: 56)
            Text(m.profiles.allSatisfy { $0.kind == .other } ? "No focus profiles yet" : "Pick a profile, or make a new one").font(T.title()).foregroundStyle(T.ink)
            Text("A profile is one app, or one website in your browser, plus the few apps allowed to stay open while you work.")
                .font(T.body()).foregroundStyle(T.ink2).multilineTextAlignment(.center).frame(maxWidth: 360)
            PButton(title: "New profile", symbol: "plus", kind: .primary) { addProfile() }
        }.padding(T.s6)
    }

    // MARK: detail

    func binding(_ i: Int) -> Binding<Profile> {
        Binding(get: { m.profiles[min(i, m.profiles.count - 1)] }, set: {
            var all = m.profiles
            if i < all.count, all[i] != $0 { all[i] = $0; m.saveProfiles(all); savedAt = Date() }
        })
    }

    func app(_ id: String?) -> CatalogApp? { apps.first { $0.id == id } }

    @ViewBuilder func detail(_ i: Int) -> some View {
        let p = binding(i)
        VStack(alignment: .leading, spacing: T.s4) {
            HStack(alignment: .center, spacing: T.s3) {
                profileIcon(p.wrappedValue, size: 40)
                TextField("Name", text: p.name).textFieldStyle(.plain).font(T.display()).foregroundStyle(T.ink)
                Spacer(minLength: T.s2)
                savedBadge
                if p.wrappedValue.kind != .other { PButton(title: "Remove", symbol: "trash", kind: .ghost) { removeSelected() }.fixedSize() }
            }
            .padding(.top, 40)
            if p.wrappedValue.kind == .other {
                Card { Text("Other: you type the task when you start. Browsers and Preview stay open.").font(T.body()).foregroundStyle(T.ink2) }
            } else {
                Card { VStack(alignment: .leading, spacing: T.s3) { Overline(text: "Focus on"); targetPicker(p) } }
                if p.wrappedValue.kind == .website { Card { VStack(alignment: .leading, spacing: T.s3) { Overline(text: "Sites that count"); links(p) } } }
                Card { VStack(alignment: .leading, spacing: T.s3) { Overline(text: "Also allowed while you focus"); allowed(p) } }
            }
            Card {
                HStack(alignment: .center, spacing: T.s5) {
                    TimerDial(minutes: Binding(get: { min(60, max(5, p.wrappedValue.minutes)) }, set: { p.wrappedValue.minutes = $0 }), size: 176)
                    VStack(alignment: .leading, spacing: T.s2) {
                        Overline(text: "Default length")
                        Text("\(p.wrappedValue.minutes) minutes").font(T.title()).foregroundStyle(T.ink)
                        Text("Twist the leaf, or use the arrow keys. You can change it each time in the launcher.")
                            .font(T.callout()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                        if p.wrappedValue.contractApp != nil {
                            Text("This app reports its own tasks, so the clock starts when you open one in it.")
                                .font(T.caption()).foregroundStyle(T.leaf).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text("Claude, Terminal, Finder and System Settings always stay reachable. Everything else is hidden, never quit.")
                .font(T.caption()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }


    // MARK: create (a guided flow; Save lives in a fixed footer)

    enum Step { case focus, sites, allowed, length
        var title: String {
            switch self {
            case .focus: "What will you focus on?"
            case .sites: "Which sites count?"
            case .allowed: "What else may stay open?"
            case .length: "How long, usually?"
            }
        }
    }

    var steps: [Step] { draft?.kind == .website ? [.focus, .sites, .allowed, .length] : [.focus, .allowed, .length] }

    /// Why Save is off, in one line; nil when the profile is complete enough to save.
    var saveBlocker: String? {
        guard let d = draft else { return nil }
        if d.kind == .app && d.appID == nil || d.kind == .website && d.browsers.isEmpty { return "Pick what to focus on first" }
        if d.kind == .website && d.domains.isEmpty { return "Add at least one site" }
        if d.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give it a name" }
        return nil
    }

    var draftBinding: Binding<Profile> {
        Binding(get: { draft ?? .other }, set: { draft = $0 })
    }

    var creator: some View {
        let p = draftBinding, cur = steps[min(step, steps.count - 1)], last = step >= steps.count - 1
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: T.s2) {
                Text("NEW PROFILE · STEP \(step + 1) OF \(steps.count)").font(T.overline()).tracking(0.6).foregroundStyle(T.ink2)
                Text(cur.title).font(T.display()).foregroundStyle(T.ink)
                HStack(spacing: T.s1) {
                    ForEach(steps.indices, id: \.self) { i in
                        Capsule().fill(i <= step ? T.tomato : T.line).frame(height: 4)
                    }
                }
            }
            .padding(.top, 40).padding(.horizontal, T.s5).padding(.bottom, T.s3)
            ScrollView {
                VStack(alignment: .leading, spacing: T.s3) { stepBody(cur, p) }
                    .padding(.horizontal, T.s5).padding(.vertical, T.s2)
            }
            Rectangle().fill(T.line).frame(height: 1)
            HStack(spacing: T.s2) {
                if step == 0 { PButton(title: "Cancel", kind: .ghost) { cancelDraft() }.keyboardShortcut(.cancelAction) }
                else {
                    PButton(title: "Back", symbol: "chevron.left", kind: .ghost) { withAnimation(.snappy(duration: 0.2)) { step -= 1 } }
                    Button("") { cancelDraft() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0)   // Esc still cancels
                }
                Spacer(minLength: T.s2)
                if let why = saveBlocker { Text(why).font(T.caption()).foregroundStyle(T.ink2).lineLimit(1) }
                if !last {
                    PButton(title: "Next", kind: .secondary) { withAnimation(.snappy(duration: 0.2)) { step += 1 } }
                        .disabled(cur == .focus && saveBlocker == "Pick what to focus on first")
                        .opacity(cur == .focus && saveBlocker == "Pick what to focus on first" ? 0.45 : 1).fixedSize()
                }
                PButton(title: "Save profile", symbol: "checkmark", kind: .primary) { saveDraft() }
                    .keyboardShortcut(.defaultAction).disabled(saveBlocker != nil).opacity(saveBlocker != nil ? 0.45 : 1).fixedSize()
            }
            .padding(.horizontal, T.s5).padding(.vertical, T.s3)
            .background(T.surface)
        }
    }

    @ViewBuilder func stepBody(_ s: Step, _ p: Binding<Profile>) -> some View {
        switch s {
        case .focus:
            Card { VStack(alignment: .leading, spacing: T.s3) { Overline(text: "An app, or a browser for websites"); targetPicker(p) } }
            if saveBlocker != "Pick what to focus on first" {
                Card { VStack(alignment: .leading, spacing: T.s2) { Overline(text: "Name"); PField(placeholder: "e.g. Thesis", text: p.name) } }
            }
            if firstRun {   // the way out, taught before the first session ever hides anything
                HStack(spacing: T.s3) {
                    Keys(["⌃", "⌥", "⌘", "E"])
                    Text("During a session, other apps are hidden. This brings them all back, any time.")
                        .font(T.callout()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, T.s1)
            }
        case .sites: Card { VStack(alignment: .leading, spacing: T.s3) { links(p) } }
        case .allowed: Card { VStack(alignment: .leading, spacing: T.s3) { allowed(p) } }
        case .length:
            Card {
                HStack(spacing: T.s5) {
                    TimerDial(minutes: p.minutes, size: 176)
                    Text("Twist the leaf, or use the arrow keys. You can still change it each time in the launcher.")
                        .font(T.callout()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func cancelDraft() { draft = nil; selection = selection ?? m.profiles.first { $0.kind != .other }?.id }

    func saveDraft() {
        guard var d = draft, saveBlocker == nil else { return }
        d.name = d.name.trimmingCharacters(in: .whitespaces)
        var all = m.profiles
        all.insert(d, at: all.firstIndex { $0.kind == .other } ?? all.count)   // Other stays last
        m.saveProfiles(all)
        draft = nil; selection = d.id; savedAt = Date()
    }

    /// Edits save as they happen (the Mac norm for settings); this shows that they did.
    @ViewBuilder var savedBadge: some View {
        if savedAt != nil {
            Label("Saved", systemImage: "checkmark.circle.fill").font(T.callout()).foregroundStyle(T.leaf).fixedSize()
                .task(id: savedAt) { try? await Task.sleep(for: .seconds(2)); savedAt = nil }
        }
    }

    func tierNote(_ a: CatalogApp) -> String {
        switch Browsers.tier(bundleID: a.id, url: a.url) {
        case .full: "Reads the page address"
        case .titleOnly: "Can't read the page address: counts time in the browser"
        case .unsupported: "Not supported"
        }
    }

    @ViewBuilder func targetPicker(_ p: Binding<Profile>) -> some View {
        let targetID = p.wrappedValue.kind == .website ? p.wrappedValue.browsers.first : p.wrappedValue.appID
        if let a = app(targetID) {
            HStack(spacing: T.s3) {
                AppIcon(bundleID: a.id, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(T.headline()).foregroundStyle(T.ink)
                    Text(a.isBrowser ? "Website mode · " + tierNote(a) : "Time counts while it's in front")
                        .font(T.caption()).foregroundStyle(a.isBrowser && Browsers.tier(bundleID: a.id, url: a.url) != .full ? T.tomato : T.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: T.s2)
                PButton(title: "Change", kind: .secondary) { var v = p.wrappedValue; v.appID = nil; v.browsers = []; v.kind = .app; p.wrappedValue = v }
                    .fixedSize()
            }
        } else {
            PField(placeholder: "Search your apps", text: $search, symbol: "magnifyingglass")
            appGrid(apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, height: 220) { a in
                Button { choose(a, p) } label: { appTile(a, on: false, trailing: a.isBrowser ? "browser" : nil) }.buttonStyle(.plain)
            }
        }
    }

    func appGrid<V: View>(_ list: [CatalogApp], height: CGFloat, @ViewBuilder cell: @escaping (CatalogApp) -> V) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: T.s2)], spacing: T.s2) { ForEach(list) { cell($0) } }
        }.frame(height: height)
    }

    func appTile(_ a: CatalogApp, on: Bool, check: Bool = false, trailing: String? = nil) -> some View {
        HStack(spacing: T.s2) {
            if check { PCheck(on: on) }
            AppIcon(bundleID: a.id, size: 22)
            Text(a.name).font(T.callout()).foregroundStyle(T.ink).lineLimit(1)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(T.caption()).foregroundStyle(T.ink2) }
        }
        .padding(.horizontal, T.s2 + 2).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: T.rRow, style: .continuous).fill(on ? T.blush : T.fill.opacity(0.7)))
        .contentShape(Rectangle())
    }

    func choose(_ a: CatalogApp, _ p: Binding<Profile>) {
        var v = p.wrappedValue
        if a.isBrowser { v.kind = .website; v.browsers = [a.id]; v.appID = nil }
        else { v.kind = .app; v.appID = a.id; v.browsers = [] }
        if v.name.isEmpty || v.name == "New profile" { v.name = a.isBrowser ? "Website" : a.name }
        p.wrappedValue = v; search = ""
    }

    @ViewBuilder func links(_ p: Binding<Profile>) -> some View {
        HStack(spacing: T.s2) {
            PField(placeholder: "Paste a link, e.g. github.com/you/repo", text: $link, symbol: "link") { addLink(p) }
            PButton(title: "Add", kind: .secondary) { addLink(p) }.fixedSize()
        }
        if !p.wrappedValue.domains.isEmpty {
            FlowChips(items: p.wrappedValue.domains) { d in
                var v = p.wrappedValue; v.domains.removeAll { $0 == d }; p.wrappedValue = v
            }
        }
        PToggle(label: "Count subdomains too", detail: "e.g. gist.\(p.wrappedValue.domains.first ?? "github.com") and docs.\(p.wrappedValue.domains.first ?? "github.com")", isOn: p.includeSubdomains)
        Text("Any page on these sites counts. Any other site is off track.").font(T.caption()).foregroundStyle(T.ink2)
    }

    func addLink(_ p: Binding<Profile>) {
        guard let d = Domain.extract(from: link), !p.wrappedValue.domains.contains(d) else { link = ""; return }
        var v = p.wrappedValue; v.domains.append(d); p.wrappedValue = v; link = ""
    }

    @ViewBuilder func allowed(_ p: Binding<Profile>) -> some View {
        let target = p.wrappedValue.kind == .website ? p.wrappedValue.browsers.first : p.wrappedValue.appID
        let suggested = apps.filter { ($0.isBrowser || $0.group == .ai) && $0.id != target }
        let chosenOthers = apps.filter { p.wrappedValue.allowed.contains($0.id) && !suggested.contains($0) }
        let toggle: (CatalogApp) -> Void = { a in
            var v = p.wrappedValue
            if v.allowed.contains(a.id) { v.allowed.removeAll { $0 == a.id } } else { v.allowed.append(a.id) }
            p.wrappedValue = v
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: T.s2)], spacing: T.s2) {
            if let t = app(target) {   // the focus app itself: always allowed, so shown ticked and locked
                appTile(t, on: true, check: true, trailing: "focus").opacity(0.75).help("The app you focus on is always allowed")
            }
            ForEach(suggested + chosenOthers) { a in
                Button { toggle(a) } label: { appTile(a, on: p.wrappedValue.allowed.contains(a.id), check: true) }.buttonStyle(.plain)
            }
        }
        Button { withAnimation(.snappy(duration: 0.2)) { showMore.toggle() } } label: {
            HStack(spacing: T.s1) {
                Image(systemName: showMore ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold))
                Text(showMore ? "Fewer apps" : "More apps").font(T.callout())
            }.foregroundStyle(T.tomato)
        }.buttonStyle(.plain)
        if showMore {
            PField(placeholder: "Search your apps", text: $moreSearch, symbol: "magnifyingglass")
            appGrid(apps.filter { !suggested.contains($0) && $0.id != target && (moreSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(moreSearch)) }, height: 200) { a in
                Button { toggle(a) } label: { appTile(a, on: p.wrappedValue.allowed.contains(a.id), check: true) }.buttonStyle(.plain)
            }
        }
    }

    func addProfile() {
        draft = Profile(id: UUID().uuidString, name: "", kind: .app, minutes: 45)
        step = 0; search = ""; link = ""; moreSearch = ""; showMore = false
    }

    func removeSelected() {
        guard let s = selection, s != "Other" else { return }
        m.saveProfiles(m.profiles.filter { $0.id != s }); selection = m.profiles.first?.id
    }
}

/// Removable chips that wrap onto new lines (the domains of a website profile).
struct FlowChips: View {
    var items: [String]
    var remove: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: T.s2, alignment: .leading)], alignment: .leading, spacing: T.s2) {
            ForEach(items, id: \.self) { d in
                HStack(spacing: T.s1 + 2) {
                    Image(systemName: "globe").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.tomato)
                    Text(d).font(T.callout()).foregroundStyle(T.ink).lineLimit(1)
                    Button { remove(d) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(T.ink2) }.buttonStyle(.plain)
                }
                .padding(.horizontal, T.s3).padding(.vertical, 6)
                .background(Capsule().fill(T.blush))
            }
        }
    }
}
