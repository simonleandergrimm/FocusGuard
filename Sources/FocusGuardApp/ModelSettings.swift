import Foundation

enum ModelSettings {
    static let defaultModel = "gpt-5.6-terra"
    private static let defaultsKey = "openAIModel"
    private static let legacyDefaults: Set<String> = ["gpt-5-mini"]

    static func current() -> String {
        guard let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty,
              !legacyDefaults.contains(stored)
        else { return defaultModel }
        return stored
    }

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? defaultModel : trimmed, forKey: defaultsKey)
    }
}
