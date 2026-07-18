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
        var result = original
        while let beginRange = result.range(of: beginMarker) {
            guard let endRange = result.range(of: endMarker, range: beginRange.upperBound..<result.endIndex) else {
                break
            }

            var removalEnd = endRange.upperBound
            if removalEnd < result.endIndex, result[removalEnd] == "\n" {
                removalEnd = result.index(after: removalEnd)
            }

            result.removeSubrange(beginRange.lowerBound..<removalEnd)
        }
        return result
    }

    /// Replaces the file at `path` atomically (temp file + rename(2), mode
    /// 644) so a crash mid-write can never leave a truncated hosts file.
    public static func write(_ content: String, toPath path: String) throws {
        try AtomicFile.write(Data(content.utf8), toPath: path)
    }

    private static func expandedDomains(_ domains: Set<String>) -> [String] {
        DomainBlockExpansion.expanding(domains).sorted()
    }
}
