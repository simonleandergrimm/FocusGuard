import Foundation

public enum StrictnessInterpreter {
    public static func explicitStrictness(in prompt: String) -> Strictness? {
        let normalized = prompt
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let patterns: [(Strictness, String)] = [
            (
                .flexible,
                #"\bflexible\b|\bflex mode\b|\bmode\s*[:=\-]?\s*flex(?:ible)?\b|\bgentle\b|\beasy to stop\b"#
            ),
            (
                .focused,
                #"\bfocused\b|\bfocus mode\b|\bmode\s*[:=\-]?\s*focus(?:ed)?\b"#
            ),
            (
                .locked,
                #"\b(?:locked|strict)\b|\block mode\b|\bhard mode\b|\bno early (?:exit|unlock)\b|\bmode\s*[:=\-]?\s*lock(?:ed)?\b"#
            ),
        ]

        var latest: (location: Int, strictness: Strictness)?
        let range = NSRange(normalized.startIndex..., in: normalized)
        for (strictness, pattern) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: normalized, range: range) {
                if latest == nil || match.range.location > latest!.location {
                    latest = (match.range.location, strictness)
                }
            }
        }
        return latest?.strictness
    }
}
