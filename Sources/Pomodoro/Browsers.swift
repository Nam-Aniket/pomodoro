import AppKit

/// How much of a browser Tomo can see. full: the front tab's address and title through AppleScript (one
/// Automation prompt per browser). titleOnly: a browser with no tab address in its dictionary, so only the
/// window title, read another way. unsupported: not a browser.
enum BrowserTier: String { case full, titleOnly, unsupported }

enum Browsers {
    /// The two tab dictionaries in the wild: Chromium's `active tab` + `title`, Safari's `current tab` + `name`.
    enum Family: String { case chromium, safari }

    /// Used only when the dictionary cannot be read from the bundle.
    static let known: [String: Family] = [
        "com.google.Chrome": .chromium, "com.brave.Browser": .chromium, "com.microsoft.edgemac": .chromium,
        "com.vivaldi.Vivaldi": .chromium, "company.thebrowser.Browser": .chromium, "com.operasoftware.Opera": .chromium,
        "com.apple.Safari": .safari, "com.kagi.kagimacOS": .safari,
    ]
    /// No tab address in their dictionaries (Firefox has kept AppleScript out for years); listed so they skip the probe.
    static let titleOnly: Set<String> = ["org.mozilla.firefox", "app.zen-browser.zen"]

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: (Family?, BrowserTier)] = [:]
    private nonisolated(unsafe) static var browserIDs: Set<String>?

    static func tier(bundleID: String, url: URL) -> BrowserTier { probe(bundleID, url).1 }
    static func family(bundleID: String, url: URL) -> Family? { probe(bundleID, url).0 }

    /// Decided from the scripting dictionary on disk, never by scripting the browser: an Automation prompt
    /// would block the first time and the user may not be there to answer it.
    private static func probe(_ id: String, _ url: URL) -> (Family?, BrowserTier) {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[id] { return hit }
        let result: (Family?, BrowserTier)
        if titleOnly.contains(id) { result = (nil, .titleOnly) }
        else if let xml = dictionary(url) { result = family(in: xml).map { ($0, .full) } ?? (nil, isBrowser(id) ? .titleOnly : .unsupported) }
        else if let f = known[id] { result = (f, .full) }
        else { result = (nil, isBrowser(id) ? .titleOnly : .unsupported) }
        cache[id] = result
        return result
    }

    /// Full means a window property pointing at the front tab AND a tab class with a URL property.
    static func family(in xml: XMLDocument) -> Family? {
        func has(_ xpath: String) -> Bool { ((try? xml.nodes(forXPath: xpath)) ?? []).isEmpty == false }
        guard has("//class[@name='tab']/property[@name='URL']") else { return nil }
        let window = "//class[@name='window']/property | //class-extension[@extends='window']/property"
        if has("(\(window))[@name='active tab']") { return .chromium }
        if has("(\(window))[@name='current tab']") { return .safari }
        return nil
    }

    /// The bundled .sdef file named in Info.plist; `/usr/bin/sdef` only for old bundles that keep it elsewhere.
    static func dictionary(_ app: URL) -> XMLDocument? {
        let key = Bundle(url: app)?.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String
        if key == "dynamic" { return nil }      // built at run time by asking the app: that would launch it
        var data: Data?
        if let key { data = try? Data(contentsOf: app.appendingPathComponent("Contents/Resources").appendingPathComponent(key)) }
        else {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/sdef"); p.arguments = [app.path]
            p.standardOutput = out; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            if p.terminationStatus != 0 { data = nil }
        }
        return data.flatMap { try? XMLDocument(data: $0) }
    }

    /// Registered to open https links, the same test the app catalogue uses. Caller holds the lock.
    private static func isBrowser(_ id: String) -> Bool {
        if browserIDs == nil {
            browserIDs = Set(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
        return browserIDs!.contains(id)
    }
}

/// Reads a browser's front tab off the main thread (generalises ChromeWatcher's read to any full-tier browser).
@MainActor final class BrowserReader {
    private let queue = DispatchQueue(label: "browser-reader")
    private nonisolated(unsafe) var scripts: [String: NSAppleScript] = [:]   // touched only on `queue`

    /// denied is AppleScript error -1743: the user has not granted Automation for that browser.
    func read(bundleID: String, completion: @escaping @MainActor (_ url: String?, _ title: String?, _ denied: Bool) -> Void) {
        // Only a running browser: `tell application id` would launch a closed one.
        guard bundleID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL,
              let family = Browsers.family(bundleID: bundleID, url: appURL) else { completion(nil, nil, false); return }
        queue.async {
            let script = self.scripts[bundleID] ?? {
                let (tab, title) = family == .chromium ? ("active tab", "title") : ("current tab", "name")
                let s = NSAppleScript(source: "tell application id \"\(bundleID)\" to if (count of windows) > 0 then return (URL of \(tab) of front window) & \"\\n\" & (\(title) of \(tab) of front window)")
                s?.compileAndReturnError(nil)      // compiled once per browser; the dictionary lookup is the slow part
                self.scripts[bundleID] = s
                return s
            }()
            var err: NSDictionary?
            let out = script?.executeAndReturnError(&err).stringValue
            let denied = (err?[NSAppleScript.errorNumber] as? Int) == -1743
            let parts = out?.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init) ?? []
            let url = parts.first.flatMap { $0.isEmpty ? nil : $0 }, title = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(url, title, denied) } }
        }
    }
}
