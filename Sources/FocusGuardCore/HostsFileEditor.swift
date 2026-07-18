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

    /// Replaces the file at `path` atomically: the content is written to a
    /// temporary file in the same directory (so rename(2) stays on one
    /// filesystem) with mode 644, then renamed over the destination. Readers
    /// never observe a truncated or partially written file.
    public static func write(_ content: String, toPath path: String) throws {
        let destination = URL(fileURLWithPath: path)
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).focusguard.tmp")

        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: Data(content.utf8),
            attributes: [.posixPermissions: 0o644]
        ) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        guard rename(temporary.path, destination.path) == 0 else {
            let renameError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: temporary)
            throw renameError
        }
    }

    private static func expandedDomains(_ domains: Set<String>) -> [String] {
        DomainBlockExpansion.expanding(domains).sorted()
    }
}
