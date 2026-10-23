import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import WebKit
import PomodoroCore

/// Borderless, always on top, on every Space; can take keys only for the idea field.
final class TomoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
            TimelineView(.animation(minimumInterval: m.lively ? 1.0 / 30 : 1.0 / 15, paused: m.frozen)) { tl in
                TomoCanvas(scene: m.scene(at: tl.date, dark: scheme == .dark), time: tl.date.timeIntervalSince(m.launched))
            }
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
                if m.parking {
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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

        // A normal Mac app too: Dock icon (optional in Settings), app menu, Cmd-Q.
        NSApp.setActivationPolicy(UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true ? .regular : .accessory)
        NSApp.mainMenu = mainMenu()
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in MainActor.assumeIsolated { self.m.frozen = true } }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in MainActor.assumeIsolated { self.m.frozen = !self.panel.isVisible } }

        let menu = NSMenu(); menu.delegate = self
        status.menu = menu
        m.onChange = { [weak self] in self?.refreshStatus() }
        m.showLauncher = { [weak self] in self?.popLauncher() }
        refreshStatus()

        HotKeys.register(1, key: kVK_ANSI_E) { MainActor.assumeIsolated { self.m.emergencyExit() } }
        HotKeys.register(2, key: kVK_ANSI_I) { MainActor.assumeIsolated { self.panel.orderFrontRegardless(); self.m.beginField(.idea) } }
    }

    func applicationWillTerminate(_ n: Notification) { m.quitCleanly() }

    /// Quitting always works (it is also a way out). Mid-session it asks once, with Quit as the default button.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard m.state.isTimed, !m.state.isPaused else { return .terminateNow }
        NSApp.activate()
        let a = NSAlert()
        a.messageText = "Quit Pomodoro?"
        a.informativeText = "Tomo will remember where you were: \(m.clock(m.state.active)) active in \(m.state.task ?? m.state.app?.title ?? "this session"). Hidden apps come back."
        a.addButton(withTitle: "Quit"); a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTomo(); return true
    }

    func showTomo() { panel.orderFrontRegardless(); m.frozen = false }

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
        return bar
    }

    @objc func showTomoAction() { showTomo() }

    var settingsWindow: NSWindow?
    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Pomodoro Settings"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(m: m))
            w.center(); settingsWindow = w
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
    func launcherItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let header = NSMenuItem(title: "Work on…", action: nil, keyEquivalent: ""); header.isEnabled = false
        items.append(header)
        for a in FocusApp.launchable { items.append(item("  \(a.title)") { self.m.launch(a) }) }
        items.append(item("  Other…") { self.panel.orderFrontRegardless(); self.m.beginField(.otherTask) })
        let len = NSMenu()
        for mins in [25, 30, 45, 60] { len.addItem(item("\(mins) minutes", checked: m.sessionMinutes == mins) { self.m.sessionMinutes = mins }) }
        let lenItem = NSMenuItem(title: "Session length: \(m.sessionMinutes) min", action: nil, keyEquivalent: ""); lenItem.submenu = len
        items.append(lenItem)
        if m.state.phase == .armed, let a = m.state.app {
            items.append(item("Start \(a.title) now, without a task") { self.m.start(a) })
        }
        return items
    }

    func popLauncher() {
        let menu = NSMenu()
        launcherItems().forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(item("Insights…") { self.openInsights() })
        let mouse = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY), in: panel.contentView)
    }

    var insightsWindow: NSWindow?
    @objc func openInsights() {
        if insightsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Pomodoro Insights"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: InsightsView(db: m.db, store: m.store))
            w.center(); insightsWindow = w
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
        if s.phase == .ready, let a = s.app { add("Start session \(s.done + 1) (\(a.title))") { self.m.start(a) } }
        if !s.isTimed { launcherItems().forEach(menu.addItem); menu.addItem(.separator()) }
        add("Insights…", "i", mods: .command) { self.openInsights() }
        let searchOK = !(Policy.isGuarding(s) && s.app == .speakFit)
        add("Search Google…", enabled: searchOK) { self.searchWindow.show() }
        add("Park an idea…  ⌃⌥⌘I") { self.panel.orderFrontRegardless(); self.m.beginField(.idea) }
        add(panel.isVisible ? "Hide Tomo" : "Show Tomo") { self.panel.isVisible ? self.m.hideTomo() : self.showTomo() }
        add("Settings…", ",", mods: .command) { self.openSettings() }
        menu.addItem(.separator())
        add("Emergency exit  ⌃⌥⌘E", enabled: s.isTimed) { self.m.emergencyExit() }
        add("Quit Pomodoro", "q", mods: .command) { NSApp.terminate(nil) }
    }

    @objc func run(_ sender: NSMenuItem) { (sender.representedObject as? () -> Void)?() }
}

struct SettingsView: View {
    @ObservedObject var m: Model
    @AppStorage("showInDock") var showInDock = true
    @AppStorage("soundVolume") var volume = 0.35
    @AppStorage("soundMuted") var muted = false
    @AppStorage("breathing") var breathing = "cyclic"
    @State var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Show in Dock", isOn: $showInDock)
                .onChange(of: showInDock) { _, on in NSApp.setActivationPolicy(on ? .regular : .accessory) }
            Toggle("Open at login", isOn: $login)
                .onChange(of: login) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { m.say("Open at login failed: \(error.localizedDescription)", for: 6); login = !on }
                }
            Toggle("Mute Tomo", isOn: $muted)
            Slider(value: $volume, in: 0...1) { Text("Volume") }.disabled(muted)
            Picker("Break breathing", selection: $breathing) {
                Text("Cyclic sighing (2 in, long out)").tag("cyclic")
                Text("Box breathing (4-4-4-4)").tag("box")
            }
            LabeledContent("Ideas inbox", value: m.lot.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            LabeledContent("Emergency exit", value: "⌃⌥⌘E")
            LabeledContent("Park an idea", value: "⌃⌥⌘I")
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
