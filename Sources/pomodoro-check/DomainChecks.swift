import PomodoroCore

/// Website profile rules: registered domains, pasted links, and look-alike hosts that must never match.
func domainChecks() {
    let r = Domain.registered
    check(r("github.com") == "github.com", "bare domain unchanged")
    check(r("docs.github.com") == "github.com", "subdomain folds to registered")
    check(r("WWW.GitHub.COM") == "github.com", "lowercase and www stripped")
    check(r("github.com:8443") == "github.com", "port stripped")
    check(r("a.b.c.github.com.") == "github.com", "deep host and trailing dot")
    check(r("www.seek.com.au") == "seek.com.au", "com.au is a two-label suffix")
    check(r("jobs.careers.example.net.au") == "example.net.au", "net.au")
    check(r("bbc.co.uk") == "bbc.co.uk" && r("news.bbc.co.uk") == "bbc.co.uk", "co.uk")
    check(r("www.ox.ac.uk") == "ox.ac.uk", "ac.uk")
    check(r("shop.example.co.nz") == "example.co.nz", "co.nz")
    check(r("x.example.co.jp") == "example.co.jp" && r("x.example.com.br") == "example.com.br", "co.jp, com.br")
    check(r("aniket.github.io") == "aniket.github.io", "github.io sites belong to their owner")
    check(r("my-app.vercel.app") == "my-app.vercel.app" && r("preview.my-app.pages.dev") == "my-app.pages.dev", "hosting suffixes")
    check(r("192.168.1.10") == "192.168.1.10", "an IP is left whole")

    check(Domain.extract(from: "github.com/aniket/repo") == "github.com", "path without scheme")
    check(Domain.extract(from: "https://docs.github.com/x") == "github.com", "full URL with subdomain")
    check(Domain.extract(from: "  GitHub.com  ") == "github.com", "spaces and case")
    check(Domain.extract(from: "http://www.seek.com.au:80/jobs?q=data") == "seek.com.au", "port, query, multi-part suffix")
    check(Domain.extract(from: "") == nil && Domain.extract(from: "   ") == nil, "empty is nil")
    check(Domain.extract(from: "hello world") == nil, "words are nil")
    check(Domain.extract(from: "notaurl") == nil, "single label is nil")
    check(Domain.extract(from: "github..com") == nil && Domain.extract(from: "-bad-.com") == nil, "malformed labels are nil")
    check(Domain.extract(from: "co.uk") == nil, "a bare public suffix is not a site")
    check(Domain.extract(from: "10.0.0.1") == nil, "an IP is not a website target")

    let gh = ["github.com"]
    check(Domain.matches(host: "github.com", domains: gh, includeSubdomains: false), "exact host")
    check(Domain.matches(host: "www.github.com", domains: gh, includeSubdomains: false), "www counts as the site")
    check(!Domain.matches(host: "gist.github.com", domains: gh, includeSubdomains: false), "subdomain needs the switch")
    check(Domain.matches(host: "gist.github.com", domains: gh, includeSubdomains: true), "gist with subdomains")
    check(Domain.matches(host: "Docs.GitHub.com:443", domains: gh, includeSubdomains: true), "docs with case and port")
    check(!Domain.matches(host: "github.io", domains: gh, includeSubdomains: true), "github.io is another site")
    check(!Domain.matches(host: "notgithub.com", domains: gh, includeSubdomains: true), "look-alike prefix")
    check(!Domain.matches(host: "github.com.evil.com", domains: gh, includeSubdomains: true), "look-alike suffix trick")
    check(!Domain.matches(host: "evilgithub.com", domains: gh, includeSubdomains: true), "glued look-alike")
    check(!Domain.matches(host: "", domains: gh, includeSubdomains: true), "no host")
    check(!Domain.matches(host: "github.com", domains: [], includeSubdomains: true), "no domains")
    check(Domain.matches(host: "careers.seek.com.au", domains: ["claude.ai", "seek.com.au"], includeSubdomains: true), "any of several")
    check(!Domain.matches(host: "seek.com.au.attacker.net", domains: ["seek.com.au"], includeSubdomains: true), "multi-part look-alike")
}
