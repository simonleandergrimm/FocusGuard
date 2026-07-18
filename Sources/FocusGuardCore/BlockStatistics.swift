import Foundation

/// Counters the helper accumulates while enforcing blocks: landing-page hits
/// per blocked plan domain and forced application closes per display name.
public struct BlockStatistics: Codable, Equatable, Sendable {
    public var websiteHits: [String: Int]
    public var applicationTerminations: [String: Int]
    public var since: Date
    public var updatedAt: Date

    public init(
        websiteHits: [String: Int] = [:],
        applicationTerminations: [String: Int] = [:],
        since: Date,
        updatedAt: Date
    ) {
        self.websiteHits = websiteHits
        self.applicationTerminations = applicationTerminations
        self.since = since
        self.updatedAt = updatedAt
    }
}

/// Reads and writes `stats.json` next to the policy file. The helper writes
/// it as root with mode 644 so the unprivileged app can read it.
public struct BlockStatisticsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        PolicyStore.defaultFileURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("stats.json")
    }

    public func load() throws -> BlockStatistics? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BlockStatistics.self, from: data)
    }

    public func save(_ statistics: BlockStatistics) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(statistics), toPath: fileURL.path)
    }
}
