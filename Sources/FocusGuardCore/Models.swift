import Foundation

public enum Strictness: String, Codable, CaseIterable, Sendable {
    case flexible
    case focused
    case locked

    public var displayName: String {
        switch self {
        case .flexible: "Flexible"
        case .focused: "Focused"
        case .locked: "Locked"
        }
    }

    public var explanation: String {
        switch self {
        case .flexible: "Can be ended immediately in the app."
        case .focused: "Ending requires a 90-second cooling-off period."
        case .locked: "Emergency unlock requires confirmation and a 10-minute cooling-off period."
        }
    }

    public var unlockDelay: TimeInterval {
        switch self {
        case .flexible: 0
        case .focused: 90
        case .locked: 600
        }
    }

    public var strengthRank: Int {
        switch self {
        case .flexible: 0
        case .focused: 1
        case .locked: 2
        }
    }
}

public struct BlockedApplication: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let displayName: String
    public let bundleIdentifier: String
    public let executableName: String

    public init(displayName: String, bundleIdentifier: String, executableName: String) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
    }
}

public struct BlockPlan: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let domains: [String]
    public let applications: [BlockedApplication]
    public let startsAt: Date
    public var endsAt: Date
    public let strictness: Strictness
    public let summary: String
    public var endRequestedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        domains: [String],
        applications: [BlockedApplication],
        startsAt: Date,
        endsAt: Date,
        strictness: Strictness,
        summary: String,
        endRequestedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.domains = domains
        self.applications = applications
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.strictness = strictness
        self.summary = summary
        self.endRequestedAt = endRequestedAt
    }

    public var effectiveEnd: Date {
        guard let endRequestedAt else { return endsAt }
        return min(endsAt, endRequestedAt.addingTimeInterval(strictness.unlockDelay))
    }

    public func isActive(at date: Date = Date()) -> Bool {
        startsAt <= date && date < effectiveEnd
    }

    public func isUpcoming(at date: Date = Date()) -> Bool {
        date < startsAt
    }
}

public enum Weekday: String, Codable, CaseIterable, Hashable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public static let ordered: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
    ]

    public var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}

public struct RecurringBlockPlan: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let domains: [String]
    public let applications: [BlockedApplication]
    public let weekdays: [Weekday]
    public let startHour: Int
    public let startMinute: Int
    public let durationMinutes: Int
    public let timeZoneIdentifier: String
    public let strictness: Strictness
    public let summary: String
    public let createdAt: Date
    public var isEnabled: Bool
    public var endRequestedAt: Date?
    public var endRequestedOccurrenceStartsAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        domains: [String],
        applications: [BlockedApplication],
        weekdays: [Weekday],
        startHour: Int,
        startMinute: Int,
        durationMinutes: Int,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        strictness: Strictness,
        summary: String,
        createdAt: Date = Date(),
        isEnabled: Bool = true,
        endRequestedAt: Date? = nil,
        endRequestedOccurrenceStartsAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.domains = domains
        self.applications = applications
        self.weekdays = Weekday.ordered.filter(Set(weekdays).contains)
        self.startHour = max(0, min(startHour, 23))
        self.startMinute = max(0, min(startMinute, 59))
        self.durationMinutes = max(1, min(durationMinutes, 10_080))
        self.timeZoneIdentifier = timeZoneIdentifier
        self.strictness = strictness
        self.summary = summary
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.endRequestedAt = endRequestedAt
        self.endRequestedOccurrenceStartsAt = endRequestedOccurrenceStartsAt
    }

    public func activeOccurrence(at date: Date = Date()) -> BlockPlan? {
        guard isEnabled, !weekdays.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        let daysToInspect = min(8, Int(ceil(Double(durationMinutes) / 1_440.0)) + 1)
        for daysBack in 0...daysToInspect {
            guard let candidateDay = calendar.date(byAdding: .day, value: -daysBack, to: date),
                  let weekday = Weekday(calendarWeekday: calendar.component(.weekday, from: candidateDay)),
                  weekdays.contains(weekday),
                  let startsAt = calendar.date(
                      bySettingHour: startHour,
                      minute: startMinute,
                      second: 0,
                      of: candidateDay
                  )
            else { continue }

            let endsAt = startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
            guard startsAt <= date, date < endsAt else { continue }
            let occurrence = occurrence(startsAt: startsAt, endsAt: endsAt)
            return occurrence.isActive(at: date) ? occurrence : nil
        }
        return nil
    }

    public func nextStart(after date: Date = Date()) -> Date? {
        guard isEnabled, !weekdays.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        for daysAhead in 0...14 {
            guard let candidateDay = calendar.date(byAdding: .day, value: daysAhead, to: date),
                  let weekday = Weekday(calendarWeekday: calendar.component(.weekday, from: candidateDay)),
                  weekdays.contains(weekday),
                  let startsAt = calendar.date(
                      bySettingHour: startHour,
                      minute: startMinute,
                      second: 0,
                      of: candidateDay
                  ),
                  startsAt > date
            else { continue }
            return startsAt
        }
        return nil
    }

    private func occurrence(startsAt: Date, endsAt: Date) -> BlockPlan {
        let matchingEndRequest = endRequestedOccurrenceStartsAt == startsAt
            ? endRequestedAt
            : nil
        return BlockPlan(
            title: title,
            domains: domains,
            applications: applications,
            startsAt: startsAt,
            endsAt: endsAt,
            strictness: strictness,
            summary: summary,
            endRequestedAt: matchingEndRequest
        )
    }
}

public struct BlockScheduleDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var plans: [BlockPlan]
    public var recurringPlans: [RecurringBlockPlan]

    public init(
        version: Int = 3,
        plans: [BlockPlan] = [],
        recurringPlans: [RecurringBlockPlan] = []
    ) {
        self.version = version
        self.plans = plans
        self.recurringPlans = recurringPlans
    }

    public func activePlans(at date: Date = Date()) -> [BlockPlan] {
        plans.filter { $0.isActive(at: date) }
            + recurringPlans.compactMap { $0.activeOccurrence(at: date) }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case plans
        case recurringPlans
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        plans = try container.decodeIfPresent([BlockPlan].self, forKey: .plans) ?? []
        recurringPlans = try container.decodeIfPresent([RecurringBlockPlan].self, forKey: .recurringPlans) ?? []
    }
}

public enum LLMPlanKind: String, Codable, CaseIterable, Sendable {
    case oneTime = "one_time"
    case recurring
}

public enum PlanDraftMode: String, Sendable {
    case oneTime
    case recurring
}

public struct LLMBlockDraft: Codable, Equatable, Sendable {
    public let kind: LLMPlanKind
    public let title: String
    public let domains: [String]
    public let applications: [String]
    public let startDelayMinutes: Int
    public let durationMinutes: Int
    public let strictness: Strictness
    public let summary: String
    public let interpretation: String
    public let needsClarification: Bool
    public let clarificationQuestion: String
    public let recurrenceDays: [Weekday]
    public let recurrenceStartHour: Int
    public let recurrenceStartMinute: Int

    enum CodingKeys: String, CodingKey {
        case kind
        case title
        case domains
        case applications
        case startDelayMinutes = "start_delay_minutes"
        case durationMinutes = "duration_minutes"
        case strictness
        case summary
        case interpretation
        case needsClarification = "needs_clarification"
        case clarificationQuestion = "clarification_question"
        case recurrenceDays = "recurrence_days"
        case recurrenceStartHour = "recurrence_start_hour"
        case recurrenceStartMinute = "recurrence_start_minute"
    }
}
