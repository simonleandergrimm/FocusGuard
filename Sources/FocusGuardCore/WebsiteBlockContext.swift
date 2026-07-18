import Foundation

public struct WebsiteBlockContext: Equatable, Sendable {
    public let host: String
    public let title: String
    public let summary: String
    public let endsAt: Date
    public let strictness: Strictness

    public init(
        host: String,
        title: String,
        summary: String,
        endsAt: Date,
        strictness: Strictness
    ) {
        self.host = host
        self.title = title
        self.summary = summary
        self.endsAt = endsAt
        self.strictness = strictness
    }
}

public extension BlockScheduleDocument {
    func activeWebsiteBlock(
        for host: String,
        at date: Date = Date()
    ) -> WebsiteBlockContext? {
        guard let normalizedHost = DomainNormalizer.normalize(host) else { return nil }

        for plan in activePlans(at: date) {
            for domain in plan.domains {
                guard DomainBlockExpansion.matches(host: normalizedHost, blockedDomain: domain) else {
                    continue
                }

                return WebsiteBlockContext(
                    host: normalizedHost,
                    title: plan.title,
                    summary: plan.summary,
                    endsAt: plan.effectiveEnd,
                    strictness: plan.strictness
                )
            }
        }

        return nil
    }
}
