import Foundation

public enum DomainNormalizer {
    public static func normalize(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard let components = URLComponents(string: value), var host = components.host?.lowercased() else {
            return nil
        }

        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host.hasPrefix("*.") {
            host.removeFirst(2)
        }

        guard host.contains("."), host.count <= 253 else { return nil }
        let pattern = #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$"#
        guard host.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return host
    }

    public static func normalizeAll(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalize))).sorted()
    }
}
