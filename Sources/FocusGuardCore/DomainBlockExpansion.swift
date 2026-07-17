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
}
