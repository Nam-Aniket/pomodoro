import Foundation

/// Website profiles store registered domains ("github.com"), so one rule covers every page and,
/// when asked, every subdomain, in any browser (DESIGN.md section 10).
public enum Domain {
    /// Two-label public suffixes where the registrable name is three labels deep. Hosting suffixes are here
    /// because each customer owns a subdomain: aniket.github.io is not github.io.
    // ponytail: compact list, not the full Public Suffix List; swap in the PSL if profiles meet an odd ccTLD.
    static let multiPart: Set<String> = [
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk",
        "co.nz", "org.nz", "net.nz", "ac.nz", "govt.nz",
        "co.in", "net.in", "org.in", "ac.in", "gov.in",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp",
        "com.br", "com.cn", "com.sg", "com.hk", "com.my", "co.za", "co.kr", "com.mx", "com.tr",
        "github.io", "vercel.app", "netlify.app", "pages.dev", "herokuapp.com", "web.app", "firebaseapp.com",
    ]

    /// Lowercased host with no port, trailing dot or leading "www.".
    static func clean(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // ponytail: drops everything after the first colon, so bare IPv6 hosts are not supported.
        if let colon = h.firstIndex(of: ":") { h = String(h[..<colon]) }
        while h.hasSuffix(".") { h.removeLast() }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// The registrable domain (eTLD+1): docs.github.com and www.github.com both give github.com,
    /// shop.example.com.au gives example.com.au.
    public static func registered(_ host: String) -> String {
        let h = clean(host)
        let labels = h.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count <= 2 || labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return h }   // already short, or an IP
        let lastTwo = labels.suffix(2).joined(separator: ".")
        return labels.suffix(multiPart.contains(lastTwo) ? 3 : 2).joined(separator: ".")
    }

    /// The registered domain in whatever the user pasted: a bare host, a path, a full URL. Nil when it is not a host.
    public static func extract(from link: String) -> String? {
        let s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        guard let host = URLComponents(string: s.contains("://") ? s : "https://" + s)?.host else { return nil }
        let h = clean(host)
        let labels = h.split(separator: ".", omittingEmptySubsequences: false)
        let ok = labels.count >= 2 && labels.allSatisfy { l in
            !l.isEmpty && !l.hasPrefix("-") && !l.hasSuffix("-") && l.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        guard ok, labels.last!.contains(where: \.isLetter) else { return nil }   // a TLD has letters; IPs are not website targets
        let r = registered(h)
        return multiPart.contains(r) ? nil : r                                    // "co.uk" alone is a suffix, not a site
    }

    /// Whether a page's host belongs to one of the profile's domains. Label boundaries only, so github.com
    /// never matches notgithub.com, github.io or github.com.evil.com.
    public static func matches(host: String, domains: [String], includeSubdomains: Bool) -> Bool {
        let h = clean(host)
        guard !h.isEmpty else { return false }
        return domains.contains { d in
            let d = clean(d)
            return !d.isEmpty && (h == d || (includeSubdomains && h.hasSuffix("." + d)))
        }
    }
}
