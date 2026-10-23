import AppKit

enum AppGroup: String { case browser, ai, code, chat, notes, other }

/// One installed app a profile can target.
struct CatalogApp: Identifiable, Hashable {
    let id: String          // bundle id
    let name: String
    let url: URL
    let group: AppGroup
    let isBrowser: Bool
}

/// The installed apps, read from bundle metadata on disk; nothing is launched.
enum AppCatalog {
    /// Names the App Store categories miss: Claude ships as developer-tools, Notes as productivity.
    static let known: [String: AppGroup] = [
        "claude": .ai, "chatgpt": .ai, "chatgpt classic": .ai, "perplexity": .ai, "copilot": .ai, "microsoft copilot": .ai,
        "xcode": .code, "visual studio code": .code, "cursor": .code, "terminal": .code, "iterm": .code,
        "slack": .chat, "discord": .chat, "messages": .chat, "whatsapp": .chat, "telegram": .chat, "microsoft teams": .chat,
        "notes": .notes, "notion": .notes, "obsidian": .notes, "bear": .notes,
    ]

    static func installed() -> [CatalogApp] {
        let fm = FileManager.default
        let roots = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path, "/System/Applications"]
        // Bundle ids, not paths: Safari's real path is inside a Cryptex, not /Applications.
        let browsers = Set(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { Bundle(url: $0)?.bundleIdentifier })
        var seen = Set<String>(), apps: [CatalogApp] = []
        func add(_ url: URL) {
            guard let id = Bundle(url: url)?.bundleIdentifier, !id.hasPrefix("com.aniketnamjoshi.pomodoro"), seen.insert(id).inserted else { return }
            let name = url.deletingPathExtension().lastPathComponent   // what Finder and the Dock show
            // AI apps that also open web links (ChatGPT registers https) are AI apps, not browsers.
            let g = group(id: id, name: name, url: url)
            let isBrowser = browsers.contains(id) && g != .ai
            apps.append(CatalogApp(id: id, name: name, url: url, group: isBrowser ? .browser : g, isBrowser: isBrowser))
        }
        // Not .skipsHiddenFiles: /Applications/Safari.app is a hidden-flagged symlink into the Cryptex.
        func list(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }
        }
        for root in roots {
            for url in list(URL(fileURLWithPath: root)) {
                if url.pathExtension == "app" { add(url); continue }
                // One folder deep (Utilities, vendor folders), never inside an app bundle.
                for inner in list(url) where inner.pathExtension == "app" { add(inner) }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func group(id: String, name: String, url: URL) -> AppGroup {
        if id == "com.microsoft.VSCode" || id.hasPrefix("com.jetbrains.") { return .code }
        if let g = known[name.lowercased()] { return g }
        switch Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
        case "public.app-category.developer-tools": return .code
        case "public.app-category.social-networking": return .chat
        default: return .other
        }
    }

    static func icon(for app: CatalogApp) -> NSImage { NSWorkspace.shared.icon(forFile: app.url.path) }
}
