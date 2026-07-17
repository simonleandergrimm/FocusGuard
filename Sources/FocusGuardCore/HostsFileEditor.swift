import Foundation

public enum HostsFileEditor {
    public static let beginMarker = "# BEGIN FOCUSGUARD MANAGED BLOCK"
    public static let endMarker = "# END FOCUSGUARD MANAGED BLOCK"

    public static func updating(_ original: String, blockedDomains: Set<String>) -> String {
        let cleaned = removingManagedSection(from: original)
        let domains = expandedDomains(blockedDomains)
        guard !domains.isEmpty else { return cleaned }

        let entries = domains.map { domain in
            "127.0.0.1 \(domain)"
        }

        let section = ([beginMarker] + entries + [endMarker]).joined(separator: "\n")
        let separator = cleaned.hasSuffix("\n") ? "" : "\n"
        return cleaned + separator + section + "\n"
    }

    public static func removingManagedSection(from original: String) -> String {
        guard let beginRange = original.range(of: beginMarker) else { return original }
        guard let endRange = original.range(of: endMarker, range: beginRange.upperBound..<original.endIndex) else {
            return original
        }

        var removalEnd = endRange.upperBound
        if removalEnd < original.endIndex, original[removalEnd] == "\n" {
            removalEnd = original.index(after: removalEnd)
        }

        var result = original
        result.removeSubrange(beginRange.lowerBound..<removalEnd)
        return result
    }

    private static func expandedDomains(_ domains: Set<String>) -> [String] {
        DomainBlockExpansion.expanding(domains).sorted()
    }
}
