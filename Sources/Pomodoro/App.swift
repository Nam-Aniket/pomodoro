import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import WebKit
import PomodoroCore

/// Borderless, always on top, on every Space; can take keys only for the idea field.
final class TomoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onHelp: (() -> Void)?
    override func keyDown(with e: NSEvent) { if e.characters == "?" { onHelp?() } else { super.keyDown(with: e) } }
}

/// The launcher panel: takes keys (Other task, Escape), closes itself when focus moves elsewhere.
final class LauncherPanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); onResign?() }
}

/// Tomo's app is never the active one, and AppKit swallows the first click on an inactive window
/// unless the view opts in. Without this, taps and holds did nothing (found in the 23 Oct live run).
final class FirstMouseHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PanelView: View {
    @ObservedObject var m: Model
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                if let b = m.bubble { Bubble(text: b, dark: scheme == .dark).transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom))) }
            }
            .frame(width: 240, height: 66, alignment: .bottom)
            .animation(.spring(duration: 0.35), value: m.bubble)
            TomoLive(m: m, clock: m.clock, dark: scheme == .dark)
            // working well: Tomo shrinks to stay out of the way; any trouble and it grows back (anchored at its feet)
            .scaleEffect(m.compact ? 0.62 : 1, anchor: .bottom)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.75), value: m.compact)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                // closing the overlay only hides Tomo; Pomodoro keeps running in the menu bar and Dock
                Button { m.hideTomo() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain).help("Hide Tomo (Pomodoro keeps running)")
                .opacity(m.hovering ? 0.8 : 0).padding(6)
            }
            .onHover { m.hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in m.pressChanged() }.onEnded { m.pressEnded(at: $0.startLocation) })
            ZStack {
                if m.offerSwitch != nil {
                    HStack(spacing: 6) {
                        PChip(title: "Switch", on: true) { m.switchFocus() }
                        PChip(title: "Stay", on: false) { m.stay() }
                    }
                } else if m.parking {
                    IdeaField(m: m)
                } else {
                    Text(m.info)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(scheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.85)))
                        .opacity(m.hovering ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: m.hovering)
                }
            }
            .frame(width: 240, height: 30)
        }
        .frame(width: 240, height: 340)
    }
}

/// Tomo redrawn on each clock tick (and when the model changes), never more often than the model asks.
struct TomoLive: View {
    @ObservedObject var m: Model
    @ObservedObject var clock: TomoClock
    var dark: Bool
    var body: some View { TomoCanvas(scene: m.scene(at: Date(), dark: dark), time: clock.t) }
}

struct IdeaField: View {
    @ObservedObject var m: Model
    @FocusState private var focused: Bool
    var body: some View {
        TextField(m.fieldMode == .idea ? "Park an idea, then Enter" : "What are you working on? Enter starts", text: $m.draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)).shadow(radius: 3, y: 1))
            .frame(width: 220)
            .focused($focused)
            .onSubmit { m.park() }
            .onExitCommand { m.cancelParking() }
            .onAppear { focused = true }
    }
}

/// Google results only (D2): every main-frame navigation that is not a results page is cancelled.
final class SearchWindow: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let web: WKWebView = {
        let c = WKWebViewConfiguration()
        c.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"   // without it Google serves its basic layout
        return WKWebView(frame: .zero, configuration: c)
    }()
    let field = NSSearchField()
    let onBlocked: () -> Void

    init(onBlocked: @escaping () -> Void) {
        self.onBlocked = onBlocked
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Search with Tomo (Google results only)"
        window.isReleasedWhenClosed = false
        field.placeholderString = "Search Google"
        field.target = self; field.action = #selector(search)
        web.navigationDelegate = self
        let stack = NSStackView(views: [field, web])
        stack.orientation = .vertical; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 0, right: 10)
        window.contentView = stack
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    @objc func search() {
        if let url = SearchRules.searchURL(field.stringValue), !field.stringValue.isEmpty { web.load(URLRequest(url: url)) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // a nil target frame means "open in a new window": also a way out, so it is blocked
        let ok = action.targetFrame != nil && SearchRules.allows(action.request.url, isMainFrame: action.targetFrame?.isMainFrame ?? true)
        decisionHandler(ok ? .allow : .cancel)
        if !ok { onBlocked() }
    }
}

enum HotKeys {
    nonisolated(unsafe) static var actions: [UInt32: () -> Void] = [:]

    /// Carbon hotkeys need no Accessibility or Input Monitoring permission, so the emergency exit
    /// works on a fresh install with nothing granted.
    static func register(_ id: UInt32, key: Int, _ action: @escaping () -> Void) {
        if actions.isEmpty {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                HotKeys.actions[hk.id]?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        actions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey | controlKey), EventHotKeyID(signature: OSType(0x544F_4D4F), id: id), GetApplicationEventTarget(), 0, &ref)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let m = Model()
    var panel: TomoPanel!
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var searchWindow = SearchWindow { [weak self] in
        MainActor.assumeIsolated { self?.m.nudgeUntil = Date().addingTimeInterval(2.5); self?.m.say("Results only. Read the snippet, then back to it.", for: 3) }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = TomoPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 340), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        // canJoinAllApplications: with Stage Manager on, a regular app's windows are swept into the side strip when
        // another app comes forward, and Tomo went with them ("jumped to a corner and disappeared", 23 Oct live run).
        // Apple's header: for "floating windows and system overlays"; it joins every app's set instead.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .canJoinAllApplications]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = FirstMouseHost(rootView: PanelView(m: m))
        if !panel.setFrameUsingName("Tomo"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 260, y: screen.minY + 40))
        }
        panel.setFrameAutosaveName("Tomo")
        panel.orderFrontRegardless()
        m.panel = panel
        m.hideTomo = { [weak self] in self?.panel.orderOut(nil); self?.m.frozen = true }
        m.showTomo = { [weak self] in self?.showTomo() }
        panel.onHelp = { [weak self] in self?.openHelp() }
        m.showUpdate = { [weak self] in self?.openUpdate() }
        Updater.atLaunch(m)

        // A normal Mac app too: Dock icon (optional in Settings), app menu, Cmd-Q.
        NSApp.setActivationPolicy(UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true ? .regular : .accessory)
        NSApp.mainMenu = mainMenu()
        Chrome.applyAppearance()
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in MainActor.assumeIsolated { self.m.frozen = true } }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in MainActor.assumeIsolated { self.m.frozen = !self.panel.isVisible } }

        let menu = NSMenu(); menu.delegate = self
        status.menu = menu
        m.onChange = { [weak self] in self?.refreshStatus() }
        m.showLauncher = { [weak self] in self?.popLauncher() }
        refreshStatus()

        // Without a session nothing is tracked, so every launch opens on the focus picker; the very first launch
        // goes straight to making a first profile.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !self.m.profileStore.exists { self.showProfiles(firstRun: true) }
            else if [.idle, .armed].contains(self.m.state.phase) { self.popLauncher() }
        }
        HotKeys.register(1, key: kVK_ANSI_E) { MainActor.assumeIsolated { self.m.emergencyExit() } }
        HotKeys.register(2, key: kVK_ANSI_I) { MainActor.assumeIsolated { self.panel.orderFrontRegardless(); self.m.beginField(.idea) } }
    }

    func applicationWillTerminate(_ n: Notification) { m.quitCleanly() }

    /// Quitting always works (it is also a way out). Mid-session it asks once, with Quit as the default button.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard m.state.isTimed, !m.state.isPaused, !Updater.installing else { return .terminateNow }
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Quit Pomodoro?"
        a.informativeText = "Tomo will remember where you were: \(m.clock(m.state.active)) active in \(m.state.task ?? m.state.appName ?? "this session"). Hidden apps come back."
        a.addButton(withTitle: "Quit"); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTomo(); return true
    }

    /// Fronts Tomo, pulled back onto a screen if a display change left it off every screen.
    func showTomo() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame.insetBy(dx: 60, dy: 60)) }), let s = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: s.maxX - 260, y: s.minY + 40))
        }
        panel.orderFrontRegardless(); m.frozen = false
    }

    func mainMenu() -> NSMenu {
        let bar = NSMenu(), appItem = NSMenuItem(), app = NSMenu()
        appItem.submenu = app; bar.addItem(appItem)
        app.addItem(withTitle: "About Pomodoro", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self
        app.addItem(settings)
        let show = NSMenuItem(title: "Show Tomo", action: #selector(showTomoAction), keyEquivalent: "t"); show.target = self
        app.addItem(show)
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Pomodoro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let helpItem = NSMenuItem(), help = NSMenu(title: "Help")
        helpItem.submenu = help; bar.addItem(helpItem)
        let h = NSMenuItem(title: "Shortcuts & Help", action: #selector(openHelp), keyEquivalent: "?"); h.target = self
        help.addItem(h)
        let u = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""); u.target = self
        help.addItem(u); NSApp.helpMenu = help
        return bar
    }

    @objc func showTomoAction() { showTomo() }

    var updateWindow: NSWindow?
    func openUpdate() {
        if updateWindow?.contentView == nil {
            updateWindow = pageWindow("Update", NSSize(width: 480, height: 520), min: NSSize(width: 440, height: 420),
                                      UpdateView(m: m, close: { [weak self] in self?.updateWindow?.close() }))
        }
        NSApp.activate(); updateWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func checkForUpdates() { Task { await Updater.check(m, manual: true) } }

    var helpWindow: NSWindow?
    @objc func openHelp() {
        if helpWindow?.contentView == nil {
            helpWindow = pageWindow("Shortcuts & Help", NSSize(width: 520, height: 640), min: NSSize(width: 460, height: 520), HelpView(m: m))
        }
        NSApp.activate(); helpWindow?.makeKeyAndOrderFront(nil)
    }

    var settingsWindow: NSWindow?
    @objc func openSettings() {
        if settingsWindow?.contentView == nil {
            settingsWindow = pageWindow("Pomodoro Settings", NSSize(width: 460, height: 560), min: NSSize(width: 420, height: 480), SettingsView(m: m, openHelp: { [weak self] in self?.openHelp() }))
        }
        NSApp.activate(); settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func refreshStatus() {
        status.button?.title = "🍅" + (m.menuTitle.isEmpty ? "" : " " + m.menuTitle)
    }

    func item(_ title: String, _ key: String = "", mods: NSEvent.ModifierFlags = [], enabled: Bool = true, checked: Bool = false, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: key)
        i.keyEquivalentModifierMask = mods; i.target = self; i.representedObject = action; i.isEnabled = enabled
        i.state = checked ? .on : .off
        return i
    }

    /// The launcher: what are we working on, and for how long. Opening an app arms Tomo; the clock starts when
    /// the app's task opens. Other starts at once with the typed task.
    /// Menu bar entries for starting: one door to the launcher panel, plus a quick start when armed.
    func launcherItems() -> [NSMenuItem] {
        var items = [item("Start a session…", "s", mods: .command) { self.popLauncher() }]
        if m.state.phase == .armed, let p = m.current { items.append(item("Start \(p.name) now") { self.m.start(p) }) }
        items.append(item("Focus profiles…") { self.openProfiles() })
        return items
    }

    /// The launcher panel, beside Tomo; it closes on Start, Escape, or a click elsewhere.
    var launcherPanel: LauncherPanel?
    func popLauncher() {
        launcherPanel?.close()
        let p = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = .floating
        p.contentView = NSHostingView(rootView: LauncherView(m: m, close: { [weak self] in self?.launcherPanel?.close(); self?.launcherPanel = nil },
                                                            openInsights: { [weak self] in self?.openInsights() },
                                                            openProfiles: { [weak self] in self?.openProfiles() },
                                                            openSettings: { [weak self] in self?.openSettings() }).padding(10))
        p.setContentSize(p.contentView!.fittingSize)
        // beside Tomo: to its left if there is room, else to its right; kept on screen
        let f = panel.frame, size = p.frame.size, screen = (panel.screen ?? NSScreen.main)!.visibleFrame
        var x = f.minX - size.width + 20
        if x < screen.minX { x = f.maxX - 20 }
        let y = min(max(f.minY + 20, screen.minY), screen.maxY - size.height)
        p.setFrameOrigin(NSPoint(x: min(x, screen.maxX - size.width), y: y))
        p.onResign = { [weak self] in self?.launcherPanel?.close(); self?.launcherPanel = nil }
        launcherPanel = p
        p.makeKeyAndOrderFront(nil)
    }

    /// A normal window for a SwiftUI page. The hosting view must not size the window: by default it shrinks it
    /// to the page's ideal size, and a scrolling page's ideal size is tiny (0.4.0 opened Insights at 78 x 100 pt).
    func pageWindow<V: View>(_ title: String, _ size: NSSize, min: NSSize, _ view: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title; w.isReleasedWhenClosed = false
        // Content runs under the transparent title bar (headers pad for the traffic lights). Without this the
        // safe area pushes pages down 28 pt and their bottom 28 pt clip at minimum size (Profiles footer, 23 Oct).
        let host = NSHostingView(rootView: view.ignoresSafeArea())
        host.sizingOptions = []
        w.contentView = host
        w.contentMinSize = min
        w.setContentSize(size)
        // a closed page drops its view: kept alive, it still observed the model and re-laid itself out off screen
        // on every change (0.5.0 used 31-39% CPU with no window open, 23 Oct)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { w.contentView = nil }
        }
        Chrome.style(w)
        w.center()
        return w
    }

    var profilesWindow: NSWindow?
    @objc func openProfiles() { showProfiles(firstRun: false) }
    func showProfiles(firstRun: Bool) {
        if profilesWindow?.contentView == nil {
            profilesWindow = pageWindow("Focus profiles", NSSize(width: 820, height: 600), min: NSSize(width: 720, height: 520), ProfilesView(m: m, firstRun: firstRun))
        }
        NSApp.activate(); profilesWindow?.makeKeyAndOrderFront(nil)
    }

    var insightsWindow: NSWindow?
    @objc func openInsights() {
        if insightsWindow?.contentView == nil {
            insightsWindow = pageWindow("Pomodoro Insights", NSSize(width: 860, height: 760), min: NSSize(width: 760, height: 640), InsightsView(db: m.db, store: m.store))
        }
        NSApp.activate(); insightsWindow?.makeKeyAndOrderFront(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ key: String = "", mods: NSEvent.ModifierFlags = [], enabled: Bool = true, _ action: @escaping () -> Void) {
            menu.addItem(item(title, key, mods: mods, enabled: enabled, action))
        }
        let s = m.state
        menu.addItem(withTitle: m.info, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        if s.isTimed { add(s.isPaused ? "Resume" : "Pause") { self.m.togglePause() } }
        if s.phase == .ready, let p = m.current { add("Start session \(s.done + 1) (\(p.name))") { self.m.start(p) } }
        if !s.isTimed { launcherItems().forEach(menu.addItem); menu.addItem(.separator()) }
        add("Insights…", "i", mods: .command) { self.openInsights() }
        add("Focus profiles…") { self.openProfiles() }
        let searchOK = !(Policy.isGuarding(s) && s.app == "SpeakFit")
        add("Search Google…", enabled: searchOK) { self.searchWindow.show() }
        add("Park an idea…  ⌃⌥⌘I") { self.panel.orderFrontRegardless(); self.m.beginField(.idea) }
        add(panel.isVisible ? "Hide Tomo" : "Show Tomo") { self.panel.isVisible ? self.m.hideTomo() : self.showTomo() }
        add("Settings…", ",", mods: .command) { self.openSettings() }
        add("Shortcuts & help…") { self.openHelp() }
        if m.update != nil { add("Pomodoro \(m.update!.version) is ripe…") { self.openUpdate() } }
        else { add("Check for updates…") { self.checkForUpdates() } }
        menu.addItem(.separator())
        add("Emergency exit  ⌃⌥⌘E", enabled: s.isTimed) { self.m.emergencyExit() }
        add("Quit Pomodoro", "q", mods: .command) { NSApp.terminate(nil) }
    }

    @objc func run(_ sender: NSMenuItem) { (sender.representedObject as? () -> Void)?() }
}

struct SettingsView: View {
    @ObservedObject var m: Model
    var openHelp: () -> Void = {}
    @AppStorage("showInDock") var showInDock = true
    @AppStorage("soundVolume") var volume = 0.7
    @AppStorage("soundMuted") var muted = false
    @AppStorage("breathing") var breathing = "cyclic"
    @AppStorage("soundPalette") var palette = "mix"
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("checkForUpdates") var checkUpdates = true
    @State var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: T.s4) {
                WindowHeader(title: "Settings", subtitle: "Pomodoro \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") { EmptyView() }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Sound")
                        PToggle(label: "Mute Tomo", detail: "Silent anyway while a mic records or SpeakFit is in front", isOn: $muted)
                        Text("Volume").font(T.callout()).foregroundStyle(T.ink2)
                        HStack(spacing: T.s2) { ForEach([(0.3, "Quiet"), (0.55, "Soft"), (0.7, "Normal"), (1.0, "Loud")], id: \.0) { v, n in PChip(title: n, on: abs(volume - v) < 0.01) { volume = v } } }
                            .disabled(muted).opacity(muted ? 0.4 : 1)
                        PButton(title: "Play a test sound", symbol: "speaker.wave.2.fill", kind: .secondary) { m.testSound() }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Tomo's voice")
                        HStack(spacing: T.s2) { ForEach([("mix", "Voice + juice"), ("voice", "Babble"), ("boops", "Boops"), ("juicy", "Juicy")], id: \.0) { k, n in PChip(title: n, on: palette == k) { palette = k } } }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Breaks")
                        HStack(spacing: T.s2) {
                            PChip(title: "Cyclic sighing", on: breathing == "cyclic") { breathing = "cyclic" }
                            PChip(title: "Box breathing", on: breathing == "box") { breathing = "box" }
                        }
                        Text(breathing == "box" ? "In 4, hold 4, out 4, hold 4." : "Two short breaths in through the nose, one long breath out, for up to a minute at the start of each break. Done daily, it lifted mood more than mindfulness in one trial.")
                            .font(T.caption()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Appearance")
                        HStack(spacing: T.s2) { ForEach([("system", "Match Mac"), ("light", "Light"), ("dark", "Dark")], id: \.0) { k, n in PChip(title: n, on: appearance == k) { appearance = k; Chrome.applyAppearance() } } }
                        Divider().overlay(T.line)
                        PToggle(label: "Show in Dock", isOn: $showInDock)
                            .onChange(of: showInDock) { _, on in NSApp.setActivationPolicy(on ? .regular : .accessory) }
                        PToggle(label: "Open at login", detail: "So Tomo is there when your apps open", isOn: $login)
                            .onChange(of: login) { _, on in
                                do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                                catch { m.say("Open at login failed: \(error.localizedDescription)", for: 6); login = !on }
                            }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s2) {
                        Overline(text: "Shortcuts and files")
                        row("Emergency exit", "⌃⌥⌘E"); row("Park an idea", "⌃⌥⌘I")
                        row("Ideas inbox", m.lot.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        PButton(title: "All shortcuts & help", symbol: "questionmark.circle", kind: .secondary) { openHelp() }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Updates")
                        PToggle(label: "Check for updates", detail: "Once a day at most: one request to GitHub that carries nothing about you", isOn: $checkUpdates)
                        PButton(title: "Check now", symbol: "arrow.triangle.2.circlepath", kind: .secondary) { Task { await Updater.check(m, manual: true) } }
                    }
                }
            }
            .padding(.horizontal, T.s5).padding(.bottom, T.s5)
        }
        .frame(minWidth: 420, minHeight: 480)
        .background(T.paper)
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(T.body()).foregroundStyle(T.ink)
            Spacer(minLength: T.s3)
            Text(v).font(T.callout()).foregroundStyle(T.ink2).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}
