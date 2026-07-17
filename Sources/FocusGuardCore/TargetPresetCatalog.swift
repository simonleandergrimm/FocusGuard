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
        "mail.superhuman.com",
    ]

    public static let majorGermanNewsDomains = [
        "tagesschau.de",
        "spiegel.de",
        "zeit.de",
        "faz.net",
        "handelsblatt.com",
        "sueddeutsche.de",
        "welt.de",
        "n-tv.de",
        "bild.de",
    ]

    public static let majorSwissNewsDomains = [
        "srf.ch",
        "nzz.ch",
        "tagesanzeiger.ch",
        "blick.ch",
        "20min.ch",
        "watson.ch",
        "nau.ch",
        "republik.ch",
    ]

    public static let newsDomains =
        majorGermanNewsDomains + majorSwissNewsDomains

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
        - "news", including German or Swiss news, means: \(newsDomains.joined(separator: ", ")).
        Use the corresponding exact set when the person requests one of these categories or an obvious equivalent, unless they explicitly narrow it.
        """
    }
}
