import Darwin
import Foundation
import Testing
@testable import FocusGuardCore

@Test
func openAITransportRetriesOnlyTransientFailures() {
    #expect(OpenAIRetryPolicy.shouldRetry(statusCode: 429))
    #expect(OpenAIRetryPolicy.shouldRetry(statusCode: 503))
    #expect(!OpenAIRetryPolicy.shouldRetry(statusCode: 400))
    #expect(!OpenAIRetryPolicy.shouldRetry(statusCode: 401))

    #expect(OpenAIRetryPolicy.shouldRetry(urlErrorCode: .networkConnectionLost))
    #expect(OpenAIRetryPolicy.shouldRetry(urlErrorCode: .dnsLookupFailed))
    #expect(!OpenAIRetryPolicy.shouldRetry(urlErrorCode: .badURL))
    #expect(!OpenAIRetryPolicy.shouldRetry(urlErrorCode: .cancelled))

    #expect(OpenAIRetryPolicy.delay(afterAttempt: 1, retryAfter: nil) == 1)
    #expect(OpenAIRetryPolicy.delay(afterAttempt: 2, retryAfter: nil) == 2)
    #expect(OpenAIRetryPolicy.delay(afterAttempt: 1, retryAfter: "60") == 8)
}

@Test
func recurringWarningTimeRollsIntoThePreviousDay() {
    #expect(
        RecurringWarningCalculator.warningTime(
            weekday: .monday,
            startHour: 9,
            startMinute: 0,
            leadMinutes: 5
        ) == WeeklyClockTime(weekday: .monday, hour: 8, minute: 55)
    )
    #expect(
        RecurringWarningCalculator.warningTime(
            weekday: .monday,
            startHour: 0,
            startMinute: 3,
            leadMinutes: 5
        ) == WeeklyClockTime(weekday: .sunday, hour: 23, minute: 58)
    )
}

@Test
func policyStoreEditsUpcomingPlansButRejectsActivePlans() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardEditTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let now = Date(timeIntervalSince1970: 20_000)
    let upcoming = BlockPlan(
        title: "Upcoming",
        domains: ["example.com"],
        applications: [],
        startsAt: now.addingTimeInterval(600),
        endsAt: now.addingTimeInterval(1_200),
        strictness: .locked,
        summary: ""
    )
    let active = BlockPlan(
        title: "Active",
        domains: ["active.example"],
        applications: [],
        startsAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: ""
    )
    try store.save(BlockScheduleDocument(plans: [upcoming, active]))

    let editedUpcoming = BlockPlan(
        id: upcoming.id,
        title: "Edited",
        domains: ["example.com", "another.example"],
        applications: [],
        startsAt: upcoming.startsAt,
        endsAt: upcoming.endsAt,
        strictness: .focused,
        summary: "Updated"
    )
    let updated = try store.update(editedUpcoming, at: now)
    #expect(updated.plans.first(where: { $0.id == upcoming.id })?.title == "Edited")
    #expect(updated.plans.first(where: { $0.id == upcoming.id })?.domains.count == 2)

    let editedActive = BlockPlan(
        id: active.id,
        title: "Should fail",
        domains: active.domains,
        applications: [],
        startsAt: active.startsAt,
        endsAt: active.endsAt,
        strictness: active.strictness,
        summary: active.summary
    )
    #expect(throws: PolicyStoreError.self) {
        try store.update(editedActive, at: now)
    }
}

@Test
func policyStoreEditsRecurringPlansOnlyBetweenOccurrences() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardRecurringEditTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let formatter = ISO8601DateFormatter()
    let mondayAtTen = formatter.date(from: "2026-07-13T10:00:00Z")!
    let mondayAtNoon = formatter.date(from: "2026-07-13T12:00:00Z")!
    let original = RecurringBlockPlan(
        title: "Monday writing",
        domains: ["example.com"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 120,
        timeZoneIdentifier: "UTC",
        strictness: .locked,
        summary: ""
    )
    try store.save(BlockScheduleDocument(recurringPlans: [original]))

    let edited = RecurringBlockPlan(
        id: original.id,
        title: "Edited Mondays",
        domains: ["example.com", "another.example"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 120,
        timeZoneIdentifier: "UTC",
        strictness: .focused,
        summary: "Updated",
        createdAt: original.createdAt
    )
    let updated = try store.update(edited, at: mondayAtNoon)
    #expect(updated.recurringPlans[0].title == "Edited Mondays")

    #expect(throws: PolicyStoreError.self) {
        try store.update(edited, at: mondayAtTen)
    }
}

@Test
func activeOneTimePlansAcceptOnlyStrongerUpdates() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardStrengthenTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let now = Date(timeIntervalSince1970: 30_000)
    let original = BlockPlan(
        title: "Active writing",
        domains: ["example.com"],
        applications: [],
        startsAt: now.addingTimeInterval(-300),
        endsAt: now.addingTimeInterval(900),
        strictness: .flexible,
        summary: "Write."
    )
    try store.save(BlockScheduleDocument(plans: [original]))

    let stronger = BlockPlan(
        id: original.id,
        title: original.title,
        domains: ["example.com", "another.example"],
        applications: [],
        startsAt: original.startsAt,
        endsAt: original.endsAt.addingTimeInterval(600),
        strictness: .locked,
        summary: original.summary
    )
    let updated = try store.strengthen(stronger, at: now)
    #expect(updated.plans[0].strictness == .locked)
    #expect(updated.plans[0].domains.count == 2)
    #expect(updated.plans[0].endsAt == stronger.endsAt)

    let weaker = BlockPlan(
        id: original.id,
        title: original.title,
        domains: ["example.com"],
        applications: [],
        startsAt: original.startsAt,
        endsAt: original.endsAt,
        strictness: .focused,
        summary: original.summary
    )
    #expect(throws: PolicyStoreError.self) {
        try store.strengthen(weaker, at: now)
    }
}

@Test
func activeRecurringPlansAcceptOnlyStrongerUpdates() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardRecurringStrengthenTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let formatter = ISO8601DateFormatter()
    let mondayAtTen = formatter.date(from: "2026-07-13T10:00:00Z")!
    let createdAt = formatter.date(from: "2026-07-01T12:00:00Z")!
    let original = RecurringBlockPlan(
        title: "Monday writing",
        domains: ["example.com"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 120,
        timeZoneIdentifier: "UTC",
        strictness: .focused,
        summary: "Write.",
        createdAt: createdAt
    )
    try store.save(BlockScheduleDocument(recurringPlans: [original]))

    let stronger = RecurringBlockPlan(
        id: original.id,
        title: original.title,
        domains: ["example.com", "another.example"],
        applications: [],
        weekdays: original.weekdays,
        startHour: original.startHour,
        startMinute: original.startMinute,
        durationMinutes: 180,
        timeZoneIdentifier: original.timeZoneIdentifier,
        strictness: .locked,
        summary: original.summary,
        createdAt: original.createdAt,
        isEnabled: original.isEnabled
    )
    let updated = try store.strengthen(stronger, at: mondayAtTen)
    #expect(updated.recurringPlans[0].durationMinutes == 180)
    #expect(updated.recurringPlans[0].domains.count == 2)

    let weaker = RecurringBlockPlan(
        id: original.id,
        title: original.title,
        domains: original.domains,
        applications: [],
        weekdays: original.weekdays,
        startHour: original.startHour,
        startMinute: original.startMinute,
        durationMinutes: original.durationMinutes,
        timeZoneIdentifier: original.timeZoneIdentifier,
        strictness: .focused,
        summary: original.summary,
        createdAt: original.createdAt,
        isEnabled: original.isEnabled
    )
    #expect(throws: PolicyStoreError.self) {
        try store.strengthen(weaker, at: mondayAtTen)
    }
}

@Test
func domainNormalization() {
    #expect(DomainNormalizer.normalize("https://WWW.Example.com/news?q=1") == "www.example.com")
    #expect(DomainNormalizer.normalize("example.com") == "example.com")
    #expect(DomainNormalizer.normalize("not a domain") == nil)
    #expect(
        DomainNormalizer.normalizeAll(["Example.com", "https://example.com/path"])
            == ["example.com"]
    )
}

@Test
func newsCategoryMatchesAcrossLanguages() {
    let general = TargetPresetCatalog.match(prompt: "Block news for two hours")
    let english = TargetPresetCatalog.match(prompt: "Block major news sites for two hours")
    let german = TargetPresetCatalog.match(prompt: "Blockiere große Nachrichtenseiten")

    #expect(general?.domains == TargetPresetCatalog.newsDomains)
    #expect(english?.domains == TargetPresetCatalog.newsDomains)
    #expect(german?.domains == TargetPresetCatalog.newsDomains)
    #expect(TargetPresetCatalog.newsDomains.contains("nytimes.com"))
    #expect(TargetPresetCatalog.newsDomains.contains("bbc.com"))
    #expect(TargetPresetCatalog.newsDomains.contains("reuters.com"))
    #expect(TargetPresetCatalog.match(prompt: "Block German language-learning sites") == nil)
}

@Test
func emailCategoryUsesCommonProviders() {
    let match = TargetPresetCatalog.match(prompt: "Block email for two hours")

    #expect(match?.domains == TargetPresetCatalog.emailDomains)
    #expect(TargetPresetCatalog.emailDomains.contains("mail.google.com"))
    #expect(TargetPresetCatalog.emailDomains.contains("outlook.office.com"))
    #expect(TargetPresetCatalog.match(prompt: "Block the Mail app for an hour") == nil)
}

@Test
func categoryPresetsCanBeCombined() {
    let matches = TargetPresetCatalog.matches(
        prompt: "Block email and major news sites"
    )

    #expect(matches.map(\.name) == ["email", "news sites"])
    #expect(
        Set(matches.flatMap(\.domains))
            == Set(TargetPresetCatalog.emailDomains + TargetPresetCatalog.newsDomains)
    )
}

@Test
func explicitStrictnessParsingIsDeterministic() {
    #expect(StrictnessInterpreter.explicitStrictness(in: "Block Reddit for an hour, flexible") == .flexible)
    #expect(StrictnessInterpreter.explicitStrictness(in: "Use focus mode until 5") == .focused)
    #expect(StrictnessInterpreter.explicitStrictness(in: "Block news, strict") == .locked)
    #expect(StrictnessInterpreter.explicitStrictness(in: "Focus on writing for an hour") == nil)
    #expect(StrictnessInterpreter.explicitStrictness(in: "Start flexible, actually make it locked") == .locked)
}

@Test
func llmDraftDecodesInterpretationAndClarificationFields() throws {
    let data = Data(
        #"{"kind":"one_time","title":"news","domains":["nytimes.com"],"applications":[],"start_delay_minutes":0,"duration_minutes":60,"strictness":"focused","summary":"News will be blocked for an hour.","interpretation":"Expanded the requested news category.","needs_clarification":false,"clarification_question":"","recurrence_days":[],"recurrence_start_hour":0,"recurrence_start_minute":0}"#.utf8
    )
    let draft = try JSONDecoder().decode(LLMBlockDraft.self, from: data)

    #expect(draft.interpretation == "Expanded the requested news category.")
    #expect(!draft.needsClarification)
    #expect(draft.clarificationQuestion.isEmpty)
}

@Test
func hostsFileUpdateIsIdempotentAndPreservesExistingContent() {
    let original = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n"
    let first = HostsFileEditor.updating(original, blockedDomains: ["example.com"])
    let second = HostsFileEditor.updating(first, blockedDomains: ["example.com"])

    #expect(first == second)
    #expect(first.contains("127.0.0.1 localhost"))
    #expect(first.contains("127.0.0.1 example.com"))
    #expect(first.contains("127.0.0.1 www.example.com"))

    let cleaned = HostsFileEditor.updating(first, blockedDomains: [])
    #expect(cleaned == original)
}

@Test
func xDomainExpansionCoversFirstPartyServiceHosts() {
    let original = "127.0.0.1 localhost\n"
    let updated = HostsFileEditor.updating(original, blockedDomains: ["x.com"])

    #expect(updated.contains("127.0.0.1 x.com"))
    #expect(updated.contains("127.0.0.1 twitter.com"))
    #expect(updated.contains("127.0.0.1 pbs.twimg.com"))

    let now = Date(timeIntervalSince1970: 10_000)
    let plan = BlockPlan(
        title: "No X",
        domains: ["x.com"],
        applications: [],
        startsAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: "Stay with the task."
    )
    let document = BlockScheduleDocument(plans: [plan])

    #expect(document.activeWebsiteBlock(for: "pbs.twimg.com", at: now)?.title == "No X")
}

@Test
func subdomainsOfBlockedDomainsMatch() {
    #expect(DomainBlockExpansion.matches(host: "old.reddit.com", blockedDomain: "reddit.com"))
    #expect(DomainBlockExpansion.matches(host: "www.reddit.com", blockedDomain: "reddit.com"))
    #expect(DomainBlockExpansion.matches(host: "reddit.com", blockedDomain: "reddit.com"))
    #expect(!DomainBlockExpansion.matches(host: "notreddit.com", blockedDomain: "reddit.com"))
    #expect(!DomainBlockExpansion.matches(host: "reddit.com.evil.example", blockedDomain: "reddit.com"))

    let now = Date(timeIntervalSince1970: 10_000)
    let plan = BlockPlan(
        title: "No Reddit",
        domains: ["reddit.com"],
        applications: [],
        startsAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: ""
    )
    let document = BlockScheduleDocument(plans: [plan])

    #expect(document.activeWebsiteBlock(for: "old.reddit.com", at: now)?.title == "No Reddit")
    #expect(document.activeWebsiteBlock(for: "notreddit.com", at: now) == nil)
}

@Test
func hostsFileEditorRemovesDuplicateManagedSections() {
    let duplicated = """
    127.0.0.1 localhost
    \(HostsFileEditor.beginMarker)
    127.0.0.1 stale.example
    \(HostsFileEditor.endMarker)
    255.255.255.255 broadcasthost
    \(HostsFileEditor.beginMarker)
    127.0.0.1 stale2.example
    \(HostsFileEditor.endMarker)
    """

    let cleaned = HostsFileEditor.removingManagedSection(from: duplicated)
    #expect(!cleaned.contains("stale.example"))
    #expect(!cleaned.contains("stale2.example"))
    #expect(cleaned.contains("127.0.0.1 localhost"))
    #expect(cleaned.contains("255.255.255.255 broadcasthost"))

    let updated = HostsFileEditor.updating(duplicated, blockedDomains: ["example.com"])
    #expect(updated.components(separatedBy: HostsFileEditor.beginMarker).count == 2)
    #expect(!updated.contains("stale.example"))
}

@Test
func hostsFileEditorLeavesUnterminatedManagedSectionAlone() {
    let missingEndMarker = """
    127.0.0.1 localhost
    \(HostsFileEditor.beginMarker)
    127.0.0.1 orphan.example
    """

    #expect(HostsFileEditor.removingManagedSection(from: missingEndMarker) == missingEndMarker)
}

@Test
func hostsFileWriteReplacesFileAtomicallyWithExpectedPermissions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardHostsWriteTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let path = directory.appendingPathComponent("hosts").path
    try "original\n".write(toFile: path, atomically: true, encoding: .utf8)

    try HostsFileEditor.write("updated\n", toPath: path)

    #expect(try String(contentsOfFile: path, encoding: .utf8) == "updated\n")
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o644)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(leftovers == ["hosts"])
}

@Test
func blockStatisticsRoundTripThroughStoreWithReadablePermissions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardStatsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = BlockStatisticsStore(fileURL: directory.appendingPathComponent("stats.json"))

    #expect(try store.load() == nil)

    let statistics = BlockStatistics(
        websiteHits: ["reddit.com": 4, "x.com": 1],
        applicationTerminations: ["Slack": 2],
        since: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
    try store.save(statistics)

    #expect(try store.load() == statistics)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o644)
}

@Test
func activeWebsiteBlockReportsTheMatchedPlanDomain() {
    let now = Date(timeIntervalSince1970: 10_000)
    let plan = BlockPlan(
        title: "No Reddit",
        domains: ["reddit.com"],
        applications: [],
        startsAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: ""
    )
    let document = BlockScheduleDocument(plans: [plan])

    let block = document.activeWebsiteBlock(for: "old.reddit.com", at: now)
    #expect(block?.host == "old.reddit.com")
    #expect(block?.blockedDomain == "reddit.com")
}

@Test
func strictnessControlsEffectiveEnd() {
    let start = Date(timeIntervalSince1970: 1_000)
    let end = start.addingTimeInterval(3_600)
    let request = start.addingTimeInterval(100)

    let flexible = BlockPlan(
        title: "Flexible",
        domains: ["example.com"],
        applications: [],
        startsAt: start,
        endsAt: end,
        strictness: .flexible,
        summary: "",
        endRequestedAt: request
    )
    let focused = BlockPlan(
        title: "Focused",
        domains: ["example.com"],
        applications: [],
        startsAt: start,
        endsAt: end,
        strictness: .focused,
        summary: "",
        endRequestedAt: request
    )
    let locked = BlockPlan(
        title: "Locked",
        domains: ["example.com"],
        applications: [],
        startsAt: start,
        endsAt: end,
        strictness: .locked,
        summary: "",
        endRequestedAt: request
    )

    #expect(flexible.effectiveEnd == request)
    #expect(focused.effectiveEnd == request.addingTimeInterval(90))
    #expect(locked.effectiveEnd == request.addingTimeInterval(600))
}

@Test
func processScannerFindsCurrentExecutableForCurrentUser() {
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let pathLength = pathBuffer.withUnsafeMutableBufferPointer { buffer in
        proc_pidpath(getpid(), buffer.baseAddress, UInt32(buffer.count))
    }
    #expect(pathLength > 0)

    let executablePath = pathBuffer.withUnsafeBufferPointer { buffer in
        String(cString: buffer.baseAddress!)
    }
    let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
    let matches = ProcessScanner.matching(
        targets: [ProcessMatchTarget(executableName: executableName)],
        ownerUID: getuid()
    )

    #expect(matches.contains { $0.pid == getpid() })
}

@Test
func processTargetMatchingRequiresBundlePathWhenKnown() {
    let slack = ProcessMatchTarget(executableName: "Slack", bundleName: "Slack.app")
    let bareElectron = ProcessMatchTarget(executableName: "Electron")

    #expect(
        ProcessScanner.target(
            matching: "/Applications/Slack.app/Contents/MacOS/Slack",
            in: [slack]
        ) == slack
    )
    #expect(
        ProcessScanner.target(
            matching: "/Users/dev/SomeTool.app/Contents/MacOS/Slack",
            in: [slack]
        ) == nil
    )
    #expect(
        ProcessScanner.target(
            matching: "/Applications/Other.app/Contents/MacOS/Electron",
            in: [bareElectron]
        ) == bareElectron
    )
    #expect(
        ProcessScanner.target(
            matching: "/Applications/Slack.app/Contents/MacOS/Helper",
            in: [slack, bareElectron]
        ) == nil
    )
}

@Test
func blockedApplicationDecodesPolicyFilesWithoutBundleName() throws {
    let data = Data(
        #"{"displayName":"Slack","bundleIdentifier":"com.tinyspeck.slackmacgap","executableName":"Slack"}"#.utf8
    )
    let application = try JSONDecoder().decode(BlockedApplication.self, from: data)

    #expect(application.bundleName == nil)
    #expect(application.executableName == "Slack")
}

@Test
func activeWebsiteBlockMatchesRootWWWAndSubdomainHostsOnlyWhileActive() {
    let now = Date(timeIntervalSince1970: 10_000)
    let plan = BlockPlan(
        title: "Write the draft",
        domains: ["example.com"],
        applications: [],
        startsAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: "Stay with the page."
    )
    let document = BlockScheduleDocument(plans: [plan])

    #expect(document.activeWebsiteBlock(for: "example.com", at: now)?.title == "Write the draft")
    #expect(document.activeWebsiteBlock(for: "www.example.com", at: now)?.endsAt == plan.endsAt)
    #expect(document.activeWebsiteBlock(for: "other.example.com", at: now)?.title == "Write the draft")
    #expect(document.activeWebsiteBlock(for: "unrelated.example", at: now) == nil)
    #expect(document.activeWebsiteBlock(for: "example.com", at: plan.endsAt) == nil)
}

@Test
func recurringPlanCreatesActiveOccurrencesAndFindsNextStart() {
    let formatter = ISO8601DateFormatter()
    let mondayAtTen = formatter.date(from: "2026-07-13T10:00:00Z")!
    let mondayAtNoon = formatter.date(from: "2026-07-13T12:00:00Z")!
    let nextMondayAtNine = formatter.date(from: "2026-07-20T09:00:00Z")!

    let recurring = RecurringBlockPlan(
        title: "Monday writing",
        domains: ["example.com"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 120,
        timeZoneIdentifier: "UTC",
        strictness: .locked,
        summary: "Protect Monday writing time."
    )

    let occurrence = recurring.activeOccurrence(at: mondayAtTen)
    #expect(occurrence?.startsAt == formatter.date(from: "2026-07-13T09:00:00Z"))
    #expect(occurrence?.endsAt == formatter.date(from: "2026-07-13T11:00:00Z"))
    #expect(recurring.activeOccurrence(at: mondayAtNoon) == nil)
    #expect(recurring.nextStart(after: mondayAtNoon) == nextMondayAtNine)

    let document = BlockScheduleDocument(recurringPlans: [recurring])
    #expect(document.activePlans(at: mondayAtTen).count == 1)
}

@Test
func recurringPlanSupportsOvernightOccurrences() {
    let formatter = ISO8601DateFormatter()
    let tuesdayAtOne = formatter.date(from: "2026-07-14T01:00:00Z")!
    let recurring = RecurringBlockPlan(
        title: "Monday night",
        domains: ["example.com"],
        applications: [],
        weekdays: [.monday],
        startHour: 22,
        startMinute: 0,
        durationMinutes: 240,
        timeZoneIdentifier: "UTC",
        strictness: .focused,
        summary: "Protect the night."
    )

    #expect(recurring.activeOccurrence(at: tuesdayAtOne) != nil)
}

@Test
func overlappingRecurringOccurrencesCollapseToTheNewestOccurrence() {
    // Pins current behavior: when consecutive occurrences overlap (duration
    // longer than the gap between weekdays), the most recent start wins.
    let formatter = ISO8601DateFormatter()
    let tuesdayAtTen = formatter.date(from: "2026-07-14T10:00:00Z")!
    let recurring = RecurringBlockPlan(
        title: "Long block",
        domains: ["example.com"],
        applications: [],
        weekdays: [.monday, .tuesday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 2_880,
        timeZoneIdentifier: "UTC",
        strictness: .focused,
        summary: ""
    )

    let occurrence = recurring.activeOccurrence(at: tuesdayAtTen)
    #expect(occurrence?.startsAt == formatter.date(from: "2026-07-14T09:00:00Z"))
}

@Test
func recurringEmergencyUnlockEndsOnlyTheCurrentOccurrence() throws {
    let formatter = ISO8601DateFormatter()
    let mondayAtTen = formatter.date(from: "2026-07-13T10:00:00Z")!
    let mondayAtTenOhFive = formatter.date(from: "2026-07-13T10:05:00Z")!
    let mondayAtTenEleven = formatter.date(from: "2026-07-13T10:11:00Z")!
    let nextMondayAtTen = formatter.date(from: "2026-07-20T10:00:00Z")!
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardUnlockTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let recurring = RecurringBlockPlan(
        title: "Monday writing",
        domains: ["example.com"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 120,
        timeZoneIdentifier: "UTC",
        strictness: .locked,
        summary: "Protect Monday writing time."
    )
    try store.save(BlockScheduleDocument(recurringPlans: [recurring]))

    let requested = try store.requestEnd(recurringPlanID: recurring.id, at: mondayAtTen)
    let stored = requested.recurringPlans[0]

    #expect(stored.activeOccurrence(at: mondayAtTenOhFive)?.effectiveEnd == formatter.date(from: "2026-07-13T10:10:00Z"))
    #expect(stored.activeOccurrence(at: mondayAtTenEleven) == nil)
    #expect(stored.activeOccurrence(at: nextMondayAtTen) != nil)
}

@Test
func oldPolicyDocumentsDecodeWithoutRecurringPlans() throws {
    let data = Data(#"{"version":1,"plans":[]}"#.utf8)
    let document = try JSONDecoder().decode(BlockScheduleDocument.self, from: data)

    #expect(document.version == 1)
    #expect(document.plans.isEmpty)
    #expect(document.recurringPlans.isEmpty)
}

@Test
func policyStorePrunesOnlyOldOneTimePlans() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let now = Date()
    let old = BlockPlan(
        title: "Old",
        domains: ["old.example"],
        applications: [],
        startsAt: now.addingTimeInterval(-10_000),
        endsAt: now.addingTimeInterval(-9_000),
        strictness: .focused,
        summary: ""
    )
    let current = BlockPlan(
        title: "Current",
        domains: ["current.example"],
        applications: [],
        startsAt: now.addingTimeInterval(-60),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: ""
    )
    let recurring = RecurringBlockPlan(
        title: "Weekly",
        domains: ["weekly.example"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 60,
        strictness: .focused,
        summary: ""
    )
    try store.save(BlockScheduleDocument(plans: [old, current], recurringPlans: [recurring]))

    let pruned = try store.pruneOneTimePlans(endingBefore: now.addingTimeInterval(-3_600))

    #expect(pruned.plans.map(\.title) == ["Current"])
    #expect(pruned.recurringPlans.map(\.title) == ["Weekly"])
}

@Test
func policyStoreCanCancelJustActivatedPlans() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FocusGuardUndoActivationTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PolicyStore(fileURL: directory.appendingPathComponent("policy.json"))
    let now = Date()
    let oneTime = BlockPlan(
        title: "Started now",
        domains: ["example.com"],
        applications: [],
        startsAt: now.addingTimeInterval(-1),
        endsAt: now.addingTimeInterval(600),
        strictness: .locked,
        summary: ""
    )
    let recurring = RecurringBlockPlan(
        title: "Enabled now",
        domains: ["weekly.example"],
        applications: [],
        weekdays: [.monday],
        startHour: 9,
        startMinute: 0,
        durationMinutes: 60,
        strictness: .locked,
        summary: ""
    )
    try store.save(BlockScheduleDocument(plans: [oneTime], recurringPlans: [recurring]))

    let withoutOneTime = try store.cancelNewOneTimePlan(planID: oneTime.id)
    #expect(withoutOneTime.plans.isEmpty)
    #expect(withoutOneTime.recurringPlans.map(\.id) == [recurring.id])

    let empty = try store.cancelNewRecurringPlan(planID: recurring.id)
    #expect(empty.plans.isEmpty)
    #expect(empty.recurringPlans.isEmpty)
}
