import Foundation

public struct TargetPresetMatch: Equatable, Sendable {
    public let name: String
    public let domains: [String]

    public init(name: String, domains: [String]) {
        self.name = name
        self.domains = domains
    }
}

public enum TargetPresetCatalog {
    public static let emailDomains = [
        "mail.google.com",
        "gmail.com",
        "outlook.live.com",
        "outlook.office.com",
        "mail.yahoo.com",
        "icloud.com",
    ]

    public static let newsDomains = [
        "nytimes.com",
        "washingtonpost.com",
        "wsj.com",
        "bbc.com",
        "theguardian.com",
        "cnn.com",
        "reuters.com",
        "apnews.com",
        "ft.com",
        "economist.com",
    ]

    public static func match(prompt: String) -> TargetPresetMatch? {
        matches(prompt: prompt).first
    }

    public static func matches(prompt: String) -> [TargetPresetMatch] {
        let normalized = prompt
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let words = Set(
            normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        var results: [TargetPresetMatch] = []

        if words.contains("email") {
            results.append(
                TargetPresetMatch(
                    name: "email",
                    domains: emailDomains
                )
            )
        }

        let refersToNews = ["news", "nachrichten", "newspaper", "zeitung", "presse"]
            .contains { normalized.contains($0) }

        if refersToNews {
            results.append(
                TargetPresetMatch(
                    name: "news sites",
                    domains: newsDomains
                )
            )
        }

        return results
    }

    public static var modelGuidance: String {
        """
        Curated category presets:
        - "email" means: \(emailDomains.joined(separator: ", ")).
        - "news" means: \(newsDomains.joined(separator: ", ")).
        Use the corresponding exact set when the person requests one of these categories or an obvious equivalent, unless they explicitly narrow it.
        """
    }
}
