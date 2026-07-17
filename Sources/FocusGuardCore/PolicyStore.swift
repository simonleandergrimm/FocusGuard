import Foundation

public enum PolicyStoreError: LocalizedError {
    case planNotFound
    case oneTimePlanActive
    case recurringPlanActive
    case planNotActive
    case invalidStrengthening

    public var errorDescription: String? {
        switch self {
        case .planNotFound: "That block plan no longer exists."
        case .oneTimePlanActive: "An active commitment cannot be edited. Wait for it to finish before changing it."
        case .recurringPlanActive: "This recurring plan cannot be changed during an active occurrence."
        case .planNotActive: "That commitment is no longer active."
        case .invalidStrengthening: "Active commitments can only be extended, given more targets, or moved to a stricter mode."
        }
    }
}

public struct PolicyStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusGuard", isDirectory: true)
        return base.appendingPathComponent("policy.json")
    }

    public func ensureExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try save(BlockScheduleDocument())
    }

    public func load() throws -> BlockScheduleDocument {
        try ensureExists()
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(BlockScheduleDocument.self, from: data)
    }

    public func save(_ document: BlockScheduleDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }

    @discardableResult
    public func pruneOneTimePlans(endingBefore cutoff: Date) throws -> BlockScheduleDocument {
        var document = try load()
        let originalCount = document.plans.count
        document.plans.removeAll { $0.effectiveEnd < cutoff }
        if document.plans.count != originalCount {
            try save(document)
        }
        return document
    }

    @discardableResult
    public func add(_ plan: BlockPlan) throws -> BlockScheduleDocument {
        var document = try load()
        document.plans.append(plan)
        document.plans.sort { $0.startsAt < $1.startsAt }
        try save(document)
        return document
    }

    @discardableResult
    public func add(_ plan: RecurringBlockPlan) throws -> BlockScheduleDocument {
        var document = try load()
        document.recurringPlans.append(plan)
        document.recurringPlans.sort { $0.createdAt < $1.createdAt }
        try save(document)
        return document
    }

    /// Removes a plan that the app has just auto-activated. The app exposes this
    /// only during its short post-activation undo window.
    @discardableResult
    public func cancelNewOneTimePlan(planID: UUID) throws -> BlockScheduleDocument {
        var document = try load()
        guard document.plans.contains(where: { $0.id == planID }) else {
            throw PolicyStoreError.planNotFound
        }
        document.plans.removeAll { $0.id == planID }
        try save(document)
        return document
    }

    /// Removes a recurring plan that the app has just auto-activated. This is
    /// deliberately separate from normal deletion, which rejects active plans.
    @discardableResult
    public func cancelNewRecurringPlan(planID: UUID) throws -> BlockScheduleDocument {
        var document = try load()
        guard document.recurringPlans.contains(where: { $0.id == planID }) else {
            throw PolicyStoreError.planNotFound
        }
        document.recurringPlans.removeAll { $0.id == planID }
        try save(document)
        return document
    }

    @discardableResult
    public func update(
        _ plan: BlockPlan,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.plans.firstIndex(where: { $0.id == plan.id }) else {
            throw PolicyStoreError.planNotFound
        }
        guard !document.plans[index].isActive(at: date), !plan.isActive(at: date) else {
            throw PolicyStoreError.oneTimePlanActive
        }
        document.plans[index] = plan
        document.plans.sort { $0.startsAt < $1.startsAt }
        try save(document)
        return document
    }

    @discardableResult
    public func update(
        _ plan: RecurringBlockPlan,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.recurringPlans.firstIndex(where: { $0.id == plan.id }) else {
            throw PolicyStoreError.planNotFound
        }
        guard document.recurringPlans[index].activeOccurrence(at: date) == nil,
              plan.activeOccurrence(at: date) == nil
        else {
            throw PolicyStoreError.recurringPlanActive
        }
        document.recurringPlans[index] = plan
        document.recurringPlans.sort { $0.createdAt < $1.createdAt }
        try save(document)
        return document
    }

    @discardableResult
    public func strengthen(
        _ plan: BlockPlan,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.plans.firstIndex(where: { $0.id == plan.id }) else {
            throw PolicyStoreError.planNotFound
        }
        let existing = document.plans[index]
        guard existing.isActive(at: date) else {
            throw PolicyStoreError.planNotActive
        }
        guard Self.isValidStrengthening(from: existing, to: plan) else {
            throw PolicyStoreError.invalidStrengthening
        }
        document.plans[index] = plan
        try save(document)
        return document
    }

    @discardableResult
    public func strengthen(
        _ plan: RecurringBlockPlan,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.recurringPlans.firstIndex(where: { $0.id == plan.id }) else {
            throw PolicyStoreError.planNotFound
        }
        let existing = document.recurringPlans[index]
        guard existing.activeOccurrence(at: date) != nil else {
            throw PolicyStoreError.planNotActive
        }
        guard Self.isValidStrengthening(from: existing, to: plan),
              plan.activeOccurrence(at: date) != nil
        else {
            throw PolicyStoreError.invalidStrengthening
        }
        document.recurringPlans[index] = plan
        try save(document)
        return document
    }

    @discardableResult
    public func setRecurringPlanEnabled(
        planID: UUID,
        enabled: Bool,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.recurringPlans.firstIndex(where: { $0.id == planID }) else {
            throw PolicyStoreError.planNotFound
        }
        guard document.recurringPlans[index].activeOccurrence(at: date) == nil else {
            throw PolicyStoreError.recurringPlanActive
        }
        document.recurringPlans[index].isEnabled = enabled
        try save(document)
        return document
    }

    @discardableResult
    public func deleteRecurringPlan(
        planID: UUID,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let plan = document.recurringPlans.first(where: { $0.id == planID }) else {
            throw PolicyStoreError.planNotFound
        }
        guard plan.activeOccurrence(at: date) == nil else {
            throw PolicyStoreError.recurringPlanActive
        }
        document.recurringPlans.removeAll { $0.id == planID }
        try save(document)
        return document
    }

    @discardableResult
    public func requestEnd(planID: UUID, at date: Date = Date()) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.plans.firstIndex(where: { $0.id == planID }) else {
            throw PolicyStoreError.planNotFound
        }

        if document.plans[index].endRequestedAt == nil {
            document.plans[index].endRequestedAt = date
        }
        try save(document)
        return document
    }

    @discardableResult
    public func requestEnd(
        recurringPlanID: UUID,
        at date: Date = Date()
    ) throws -> BlockScheduleDocument {
        var document = try load()
        guard let index = document.recurringPlans.firstIndex(where: { $0.id == recurringPlanID }) else {
            throw PolicyStoreError.planNotFound
        }
        guard let occurrence = document.recurringPlans[index].activeOccurrence(at: date) else {
            throw PolicyStoreError.planNotFound
        }

        if occurrence.endRequestedAt == nil {
            document.recurringPlans[index].endRequestedAt = date
            document.recurringPlans[index].endRequestedOccurrenceStartsAt = occurrence.startsAt
        }
        try save(document)
        return document
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func isValidStrengthening(from existing: BlockPlan, to updated: BlockPlan) -> Bool {
        updated.id == existing.id
            && updated.title == existing.title
            && updated.startsAt == existing.startsAt
            && updated.summary == existing.summary
            && updated.endRequestedAt == existing.endRequestedAt
            && updated.endsAt >= existing.endsAt
            && updated.strictness.strengthRank >= existing.strictness.strengthRank
            && Set(updated.domains).isSuperset(of: Set(existing.domains))
            && Set(updated.applications).isSuperset(of: Set(existing.applications))
    }

    private static func isValidStrengthening(
        from existing: RecurringBlockPlan,
        to updated: RecurringBlockPlan
    ) -> Bool {
        updated.id == existing.id
            && updated.title == existing.title
            && updated.weekdays == existing.weekdays
            && updated.startHour == existing.startHour
            && updated.startMinute == existing.startMinute
            && updated.timeZoneIdentifier == existing.timeZoneIdentifier
            && updated.summary == existing.summary
            && updated.createdAt == existing.createdAt
            && updated.isEnabled == existing.isEnabled
            && updated.endRequestedAt == existing.endRequestedAt
            && updated.endRequestedOccurrenceStartsAt == existing.endRequestedOccurrenceStartsAt
            && updated.durationMinutes >= existing.durationMinutes
            && updated.strictness.strengthRank >= existing.strictness.strengthRank
            && Set(updated.domains).isSuperset(of: Set(existing.domains))
            && Set(updated.applications).isSuperset(of: Set(existing.applications))
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
