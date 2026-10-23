import Foundation

/// A focus profile: what a session is for, and what may stay visible while it runs (DESIGN.md section 14).
/// The target is an app, a website (registered domains, used in a browser), or Other (a typed task).
public struct Profile: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case app, website, other }
    public var id: String
    public var name: String
    public var kind: Kind
    /// The target app's bundle id (kind == .app).
    public var appID: String?
    /// Registered domains (kind == .website), e.g. ["github.com"].
    public var domains: [String] = []
    /// Also count subdomains (gist.github.com) as on task.
    public var includeSubdomains = true
    /// Browsers allowed for a website profile; empty means any browser.
    public var browsers: [String] = []
    /// Other apps that stay visible during the session and count as on task.
    public var allowed: [String] = []
    public var minutes = 45
    /// If the target app posts the focus contract under this name, the clock waits for its `phase=start`.
    public var contractApp: String?

    public init(id: String, name: String, kind: Kind, appID: String? = nil, domains: [String] = [], includeSubdomains: Bool = true,
                browsers: [String] = [], allowed: [String] = [], minutes: Int = 45, contractApp: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.appID = appID; self.domains = domains
        self.includeSubdomains = includeSubdomains; self.browsers = browsers; self.allowed = allowed
        self.minutes = minutes; self.contractApp = contractApp
    }

    /// Typed task, worked on in a browser or Preview.
    public static let other = Profile(id: "Other", name: "Other", kind: .other, allowed: ["com.google.Chrome", "com.apple.Safari", "com.apple.Preview"])

    /// Presets for apps that post the focus contract. Offered only when the app is installed, so a fresh Mac
    /// starts with just Other and the setup screen.
    public static let contractPresets: [Profile] = [
        Profile(id: "HackerSolve", name: "HackerSolve", kind: .app, appID: "com.aniketnamjoshi.hackersolve", contractApp: "HackerSolve"),
        Profile(id: "SpeakFit", name: "SpeakFit", kind: .app, appID: "com.aniketnamjoshi.speakfit", contractApp: "SpeakFit"),
        Profile(id: "NorthstarViewer", name: "Northstar", kind: .app, appID: "com.aniket.northstar.viewer",
                allowed: ["com.google.Chrome", "com.apple.Preview", "com.anthropic.claudefordesktop"], contractApp: "NorthstarViewer"),
    ]

    /// Whether this bundle id is the profile's target app (copies of an app share a prefix, e.g. ".v111").
    public func isTarget(_ bundleID: String) -> Bool {
        guard kind == .app, let t = appID else { return false }
        return bundleID == t || bundleID.hasPrefix(t + ".")
    }
}

/// Profiles live in `profiles.json` next to the day's state.
public struct ProfileStore: Sendable {
    public let url: URL
    public init(root: URL) { url = root.appendingPathComponent("profiles.json") }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Saved profiles; on first run, presets for whichever contract apps are installed, plus Other.
    public func load(installed: (String) -> Bool) -> [Profile] {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode([Profile].self, from: d), !p.isEmpty { return p }
        return Profile.contractPresets.filter { installed($0.appID!) } + [Profile.other]
    }

    public func save(_ profiles: [Profile]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(profiles).write(to: url, options: .atomic)
    }
}
