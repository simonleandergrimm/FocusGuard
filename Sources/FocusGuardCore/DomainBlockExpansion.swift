import Foundation

/// Expands domains that represent a single service across multiple first-party hosts.
/// Keep this deliberately small: broad category expansion belongs in the drafting layer.
public enum DomainBlockExpansion {
    private static let xRoots: Set<String> = ["x.com", "twitter.com"]
    private static let xServiceDomains: Set<String> = [
        "x.com",
        "twitter.com",
        "api.x.com",
        "api.twitter.com",
        "mobile.twitter.com",
        "abs.twimg.com",
        "pbs.twimg.com",
        "video.twimg.com",
        "ton.twimg.com",
        "t.co",
        "syndication.twitter.com",
        "platform.twitter.com"
    ]

    public static func expanding(_ domains: Set<String>) -> Set<String> {
        domains.reduce(into: Set<String>()) { result, domain in
            result.formUnion(expandedDomains(for: domain))
        }
    }

    public static func expandedDomains(for domain: String) -> Set<String> {
        guard let normalized = DomainNormalizer.normalize(domain) else { return [] }
        let unprefixed = normalized.hasPrefix("www.")
            ? String(normalized.dropFirst(4))
            : normalized

        var result = Set([normalized])
        if !normalized.hasPrefix("www.") {
            result.insert("www.\(normalized)")
        }

        if xRoots.contains(unprefixed) {
            result.formUnion(xServiceDomains)
            result.formUnion(xRoots.map { "www.\($0)" })
        }

        return result
    }

    /// True when `host` is covered by `blockedDomain`, including any
    /// subdomain of an expanded domain. The hosts file itself cannot
    /// wildcard, but callers that consult the policy directly — the browser
    /// extension and the landing page — can, so `old.reddit.com` is caught
    /// when `reddit.com` is blocked.
    public static func matches(host: String, blockedDomain: String) -> Bool {
        guard let normalizedHost = DomainNormalizer.normalize(host) else { return false }
        let expanded = expandedDomains(for: blockedDomain)
        if expanded.contains(normalizedHost) { return true }
        return expanded.contains { normalizedHost.hasSuffix(".\($0)") }
    }
}
