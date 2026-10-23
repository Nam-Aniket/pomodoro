import Foundation

/// Update check (24 Oct, after HackerSolve's UpdateCheck): one GET to GitHub's latest-release record of the
/// public repo; the request carries nothing about the person. Pure parts here, so they are checked offline.
public enum Update {
    /// Permanent: every installed copy asks this address, so the repo must never be renamed.
    public static let latestURL = URL(string: "https://api.github.com/repos/Nam-Aniket/pomodoro/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/Nam-Aniket/pomodoro/releases")!

    public struct Release: Equatable, Sendable {
        public var version: String, notes: String, dmg: URL?, page: URL
        public init(version: String, notes: String, dmg: URL?, page: URL) { self.version = version; self.notes = notes; self.dmg = dmg; self.page = page }
    }

    public enum Outcome: Equatable, Sendable { case newer(Release), upToDate, failed(String) }

    /// "v1.2.3" or "1.2.3" as whole numbers; nil for anything else (pre-releases included).
    public static func parts(_ version: String) -> [Int]? {
        let core = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let nums = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !nums.isEmpty, nums.allSatisfy({ $0 != nil }) else { return nil }
        return nums.compactMap { $0 }
    }

    /// True when `latest` is later than `current`; missing places count as 0.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let a = parts(latest), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Reads GitHub's answer: `tag_name`, `body` (the notes), `html_url`, and the first `.dmg` asset.
    public static func outcome(status: Int, body: Data, current: String) -> Outcome {
        if status == 404 { return .upToDate }   // nothing published yet
        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tag = json["tag_name"] as? String, parts(tag) != nil
        else { return .failed("GitHub gave an answer Pomodoro could not read (status \(status)).") }
        guard isNewer(tag, than: current) else { return .upToDate }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".dmg") }.flatMap(URL.init(string:))
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        return .newer(Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                              notes: json["body"] as? String ?? "", dmg: dmg, page: page))
    }

    /// At most one automatic check a day.
    public static func due(last: Date?, now: Date) -> Bool { last.map { now.timeIntervalSince($0) >= 86_400 } ?? true }
}
