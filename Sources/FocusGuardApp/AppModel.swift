import Foundation
import FocusGuardCore

struct UndoableActivation: Identifiable, Equatable {
    enum Kind: Equatable {
        case oneTime
        case recurring
    }

    let planID: UUID
    let title: String
    let kind: Kind
    let expiresAt: Date

    var id: UUID { planID }
}

@MainActor
final class AppModel: ObservableObject {
    private static let recurringWarningsKey = "recurringWarningsEnabled"
    private static let activationUndoDuration: TimeInterval = 15

    @Published var prompt = ""
    @Published var recurringPrompt = ""
    @Published var selectedStrictness: Strictness = .locked
    @Published var recurringSelectedStrictness: Strictness = .locked
    @Published private(set) var plans: [BlockPlan] = []
    @Published private(set) var recurringPlans: [RecurringBlockPlan] = []
    @Published private(set) var previewPlan: BlockPlan?
    @Published private(set) var previewRecurringPlan: RecurringBlockPlan?
    @Published private(set) var previewWarnings: [String] = []
    @Published private(set) var recurringPreviewWarnings: [String] = []
    @Published private(set) var previewInterpretation = ""
    @Published private(set) var recurringPreviewInterpretation = ""
    @Published private(set) var isParsing = false
    @Published private(set) var isInstallingHelper = false
    @Published private(set) var helperInstalled = false
    @Published private(set) var helperState: HelperInstallationState = .missing
    @Published private(set) var helperHealth: HelperRuntimeHealth?
    @Published private(set) var helperHealthUnreachable = false
    @Published private(set) var launchAtLoginDesired = LoginItemManager.isDesired
    @Published private(set) var loginItemState = LoginItemManager.state()
    @Published private(set) var backgroundStatusMessage = ""
    @Published private(set) var recurringWarningsEnabled =
        UserDefaults.standard.object(forKey: recurringWarningsKey) as? Bool ?? true
    @Published private(set) var recurringWarningStatus = ""
    @Published private(set) var undoableActivation: UndoableActivation?
    @Published var errorMessage: String?

    private let store: PolicyStore
    private var applicationCatalog: ApplicationCatalog
    private var backgroundMonitorTask: Task<Void, Never>?
    private var undoExpirationTask: Task<Void, Never>?
    private var automaticHelperRepairAttempted = false
    private var consecutiveHealthFetchFailures = 0

    init() {
        let store = PolicyStore(fileURL: PolicyStore.defaultFileURL())
        self.store = store
        self.applicationCatalog = ApplicationCatalog.load()

        do {
            let retentionCutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            let document = try store.pruneOneTimePlans(endingBefore: retentionCutoff)
            self.plans = document.plans
            self.recurringPlans = document.recurringPlans
        } catch {
            self.errorMessage = error.localizedDescription
        }
        try? BrowserExtensionExporter.refreshIfPreviouslyExported()
        let helperState = HelperInstaller.status()
        self.helperState = helperState
        self.helperInstalled = helperState.isOperational
        synchronizeRecurringWarnings()
    }

    var relevantPlans: [BlockPlan] {
        plans.filter { Date() < $0.effectiveEnd }.sorted { $0.startsAt < $1.startsAt }
    }

    var helperStatusText: String {
        guard helperState == .healthy else { return helperState.description }
        if let helperHealth {
            if helperHealth.activePlans == 0 { return "Helper healthy" }
            return "Helper healthy · \(helperHealth.activePlans) active"
        }
        if helperHealthUnreachable {
            return "Helper is running, but its local status port (8765) is unreachable — another app may be using it."
        }
        return "Helper running"
    }

    var helperActionTitle: String {
        helperState.actionTitle
    }

    var helperHealthDetails: String? {
        guard let helperHealth else { return nil }
        return "\(helperHealth.blockedDomains) website targets · \(helperHealth.blockedApplications) application targets"
    }

    var loginItemStatusText: String {
        loginItemState.description
    }

    func startBackgroundManagement() {
        guard backgroundMonitorTask == nil else { return }

        do {
            loginItemState = try LoginItemManager.applyDesiredState()
        } catch {
            backgroundStatusMessage = "Launch-at-login setup needs attention: \(error.localizedDescription)"
        }

        refreshHelperStatus()
        attemptAutomaticHelperRepairIfNeeded()

        backgroundMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshHelperStatus()
                self.loginItemState = LoginItemManager.state()
                self.attemptAutomaticHelperRepairIfNeeded()
                let health = self.helperInstalled
                    ? await HelperHealthClient.fetch()
                    : nil
                self.helperHealth = health
                if self.helperInstalled, health == nil {
                    self.consecutiveHealthFetchFailures += 1
                } else {
                    self.consecutiveHealthFetchFailures = 0
                }
                self.helperHealthUnreachable = self.consecutiveHealthFetchFailures >= 3
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginDesired = enabled
        do {
            loginItemState = try LoginItemManager.setEnabled(enabled)
            backgroundStatusMessage = loginItemState.description
        } catch {
            loginItemState = LoginItemManager.state()
            errorMessage = "Launch-at-login could not be changed: \(error.localizedDescription)"
        }
    }

    func openLoginItemSettings() {
        LoginItemManager.openApprovalSettings()
    }

    func parsePrompt(
        mode: PlanDraftMode = .oneTime,
        activateImmediately: Bool = false
    ) {
        guard !isParsing else { return }
        let sourcePrompt = mode == .recurring ? recurringPrompt : prompt
        let trimmed = sourcePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = mode == .recurring
                ? "Describe what should repeat, on which days, and for how long."
                : "Describe what you want to block and for how long."
            return
        }

        if activateImmediately {
            refreshHelperStatus()
            guard helperInstalled else {
                errorMessage = "The blocking helper must be healthy before Command–Enter can start a block immediately."
                return
            }
        }

        let apiKey: String
        do {
            guard let storedKey = try APIKeyStore.read() else {
                errorMessage = "Add a fresh OpenAI API key in Settings first."
                return
            }
            apiKey = storedKey
        } catch {
            errorMessage = "FocusGuard could not read the API key: \(error.localizedDescription)"
            return
        }

        isParsing = true
        if mode == .recurring {
            previewRecurringPlan = nil
            recurringPreviewWarnings = []
            recurringPreviewInterpretation = ""
        } else {
            previewPlan = nil
            previewWarnings = []
            previewInterpretation = ""
        }
        let selectedModel = ModelSettings.current()
        let defaultStrictness = mode == .recurring
            ? recurringSelectedStrictness
            : selectedStrictness

        Task {
            defer { isParsing = false }
            do {
                let client = OpenAIClient(apiKey: apiKey, model: selectedModel)
                let draft: LLMBlockDraft
                do {
                    draft = try await client.draftPlan(
                        from: trimmed,
                        mode: mode,
                        defaultStrictness: defaultStrictness
                    )
                } catch OpenAIClientError.invalidResponse {
                    // A malformed response is safe to retry because plans are never
                    // activated until the person reviews and confirms the preview.
                    draft = try await client.draftPlan(
                        from: trimmed,
                        mode: mode,
                        defaultStrictness: defaultStrictness
                    )
                }
                try preparePreview(
                    from: draft,
                    mode: mode,
                    originalPrompt: trimmed,
                    defaultStrictness: defaultStrictness
                )
                if activateImmediately {
                    switch mode {
                    case .oneTime:
                        activatePreview(offerUndo: true)
                    case .recurring:
                        activateRecurringPreview(offerUndo: true)
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func activatePreview() {
        activatePreview(offerUndo: false)
    }

    func prepareManualPreview(_ plan: BlockPlan) {
        previewPlan = plan
        previewRecurringPlan = nil
        previewWarnings = []
        previewInterpretation = ""
        selectedStrictness = plan.strictness
    }

    func prepareManualPreview(_ plan: RecurringBlockPlan) {
        previewRecurringPlan = plan
        previewPlan = nil
        recurringPreviewWarnings = []
        recurringPreviewInterpretation = ""
        recurringSelectedStrictness = plan.strictness
    }

    private func activatePreview(offerUndo: Bool) {
        guard let previewPlan else { return }
        do {
            plans = try store.add(previewPlan).plans
            if offerUndo {
                beginUndoWindow(
                    planID: previewPlan.id,
                    title: previewPlan.title,
                    kind: .oneTime
                )
            }
            self.previewPlan = nil
            self.previewWarnings = []
            self.previewInterpretation = ""
            self.prompt = ""
            self.selectedStrictness = .locked
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activateRecurringPreview() {
        activateRecurringPreview(offerUndo: false)
    }

    private func activateRecurringPreview(offerUndo: Bool) {
        guard let previewRecurringPlan else { return }
        do {
            let document = try store.add(previewRecurringPlan)
            plans = document.plans
            recurringPlans = document.recurringPlans
            if offerUndo {
                beginUndoWindow(
                    planID: previewRecurringPlan.id,
                    title: previewRecurringPlan.title,
                    kind: .recurring
                )
            }
            synchronizeRecurringWarnings()
            self.previewRecurringPlan = nil
            self.recurringPreviewWarnings = []
            self.recurringPreviewInterpretation = ""
            self.recurringPrompt = ""
            self.recurringSelectedStrictness = .locked
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undoAutomaticActivation() {
        guard let activation = undoableActivation else { return }
        guard Date() <= activation.expiresAt else {
            clearUndoWindow(planID: activation.planID)
            return
        }

        do {
            let document: BlockScheduleDocument
            switch activation.kind {
            case .oneTime:
                document = try store.cancelNewOneTimePlan(planID: activation.planID)
            case .recurring:
                document = try store.cancelNewRecurringPlan(planID: activation.planID)
            }
            plans = document.plans
            recurringPlans = document.recurringPlans
            if activation.kind == .recurring {
                synchronizeRecurringWarnings()
            }
            clearUndoWindow(planID: activation.planID)
        } catch {
            clearUndoWindow(planID: activation.planID)
            errorMessage = "The new block could not be undone: \(error.localizedDescription)"
        }
    }

    func undoSecondsRemaining(at date: Date) -> Int {
        guard let activation = undoableActivation else { return 0 }
        return max(0, Int(ceil(activation.expiresAt.timeIntervalSince(date))))
    }

    func updatePlan(_ plan: BlockPlan) throws {
        let document = try store.update(plan)
        plans = document.plans
        recurringPlans = document.recurringPlans
    }

    func updateRecurringPlan(_ plan: RecurringBlockPlan) throws {
        let document = try store.update(plan)
        plans = document.plans
        recurringPlans = document.recurringPlans
        synchronizeRecurringWarnings()
    }

    func strengthenPlan(_ plan: BlockPlan) throws {
        let document = try store.strengthen(plan)
        plans = document.plans
        recurringPlans = document.recurringPlans
    }

    func strengthenRecurringPlan(_ plan: RecurringBlockPlan) throws {
        let document = try store.strengthen(plan)
        plans = document.plans
        recurringPlans = document.recurringPlans
        synchronizeRecurringWarnings()
    }

    func discardPreview() {
        previewPlan = nil
        previewWarnings = []
        previewInterpretation = ""
    }

    func discardRecurringPreview() {
        previewRecurringPlan = nil
        recurringPreviewWarnings = []
        recurringPreviewInterpretation = ""
    }

    func setRecurringPlan(_ plan: RecurringBlockPlan, enabled: Bool) {
        do {
            let document = try store.setRecurringPlanEnabled(planID: plan.id, enabled: enabled)
            plans = document.plans
            recurringPlans = document.recurringPlans
            synchronizeRecurringWarnings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecurringPlan(_ plan: RecurringBlockPlan) {
        do {
            let document = try store.deleteRecurringPlan(planID: plan.id)
            plans = document.plans
            recurringPlans = document.recurringPlans
            synchronizeRecurringWarnings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestEnd(_ plan: BlockPlan) {
        do {
            plans = try store.requestEnd(planID: plan.id).plans
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestEnd(_ plan: RecurringBlockPlan) {
        do {
            let document = try store.requestEnd(recurringPlanID: plan.id)
            plans = document.plans
            recurringPlans = document.recurringPlans
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRecurringWarningsEnabled(_ enabled: Bool) {
        recurringWarningsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.recurringWarningsKey)
        synchronizeRecurringWarnings()
    }

    func installHelper(automatically: Bool = false) {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        let installer = HelperInstaller(policyURL: store.fileURL)

        Task {
            defer { isInstallingHelper = false }
            do {
                try await Task.detached { try installer.install() }.value
                refreshHelperStatus()
                if !helperInstalled {
                    let message = "The helper was copied, but its background service did not start. Use Repair to try again."
                    if automatically {
                        backgroundStatusMessage = message
                    } else {
                        errorMessage = message
                    }
                } else {
                    backgroundStatusMessage = "Helper setup completed. It now runs independently in the background."
                    try? await Task.sleep(for: .milliseconds(500))
                    helperHealth = await HelperHealthClient.fetch()
                }
            } catch {
                if automatically {
                    backgroundStatusMessage = error.localizedDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func refreshHelperStatus() {
        helperState = HelperInstaller.status()
        helperInstalled = helperState.isOperational
    }

    private func attemptAutomaticHelperRepairIfNeeded() {
        guard helperState.needsRepair,
              !automaticHelperRepairAttempted,
              !isInstallingHelper
        else { return }
        automaticHelperRepairAttempted = true
        backgroundStatusMessage = "FocusGuard is asking macOS to finish the one-time helper setup."
        installHelper(automatically: true)
    }

    private func beginUndoWindow(
        planID: UUID,
        title: String,
        kind: UndoableActivation.Kind
    ) {
        undoExpirationTask?.cancel()
        let expiresAt = Date().addingTimeInterval(Self.activationUndoDuration)
        undoableActivation = UndoableActivation(
            planID: planID,
            title: title,
            kind: kind,
            expiresAt: expiresAt
        )
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.activationUndoDuration))
            guard !Task.isCancelled else { return }
            self?.clearUndoWindow(planID: planID)
        }
    }

    private func clearUndoWindow(planID: UUID) {
        guard undoableActivation?.planID == planID else { return }
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        undoableActivation = nil
    }

    private func synchronizeRecurringWarnings() {
        let schedules = recurringPlans
        let enabled = recurringWarningsEnabled
        Task { [weak self] in
            let status = await RecurringNotificationManager.synchronize(
                plans: schedules,
                enabled: enabled
            )
            self?.recurringWarningStatus = status
        }
    }

    private func preparePreview(
        from draft: LLMBlockDraft,
        mode: PlanDraftMode,
        originalPrompt: String,
        defaultStrictness: Strictness
    ) throws {
        if draft.needsClarification {
            let question = draft.clarificationQuestion
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw OpenAIClientError.api(
                question.isEmpty
                    ? "Please make the target or timing a little more specific."
                    : String(question.prefix(240))
            )
        }

        applicationCatalog = ApplicationCatalog.load()
        let presets = TargetPresetCatalog.matches(prompt: originalPrompt)
        let explicitStrictness = StrictnessInterpreter.explicitStrictness(in: originalPrompt)
        let strictness = explicitStrictness ?? defaultStrictness
        let presetDomains = presets.flatMap(\.domains)
        let domains = DomainNormalizer.normalizeAll(draft.domains + presetDomains)
        let resolution = applicationCatalog.resolve(names: draft.applications)

        guard !domains.isEmpty || !resolution.applications.isEmpty else {
            throw OpenAIClientError.api(
                "I couldn't resolve a concrete website or installed app. Try naming a category, domain, or installed application."
            )
        }

        let duration = max(1, min(draft.durationMinutes, 10_080))
        let warning = resolution.unresolvedNames.isEmpty
            ? []
            : ["Not activated because no unique installed app matched: \(resolution.unresolvedNames.joined(separator: ", "))."]
        var interpretationParts: [String] = []
        let modelInterpretation = draft.interpretation
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelInterpretation.isEmpty {
            interpretationParts.append(String(modelInterpretation.prefix(300)))
        }
        for preset in presets {
            interpretationParts.append("Expanded “\(preset.name)” using FocusGuard's curated category preset.")
        }
        if explicitStrictness != nil {
            interpretationParts.append("Used \(strictness.displayName) because the request explicitly selected that mode.")
        } else {
            interpretationParts.append("Used \(strictness.displayName) from the mode menu.")
        }
        let interpretation = interpretationParts.joined(separator: " ")

        switch mode {
        case .oneTime:
            guard draft.kind == .oneTime else {
                throw OpenAIClientError.api("The response was recurring. Draft it from the Recurring pane instead.")
            }
            let now = Date()
            let delay = max(0, min(draft.startDelayMinutes, 10_080))
            let startsAt = now.addingTimeInterval(TimeInterval(delay * 60))
            let endsAt = startsAt.addingTimeInterval(TimeInterval(duration * 60))

            previewPlan = BlockPlan(
                title: String(draft.title.prefix(80)),
                domains: domains,
                applications: resolution.applications,
                startsAt: startsAt,
                endsAt: endsAt,
                strictness: strictness,
                summary: String(draft.summary.prefix(240))
            )
            previewWarnings = warning
            previewInterpretation = interpretation
            selectedStrictness = strictness

        case .recurring:
            guard draft.kind == .recurring, !draft.recurrenceDays.isEmpty else {
                throw OpenAIClientError.api("The recurring response needs at least one day of the week.")
            }
            previewRecurringPlan = RecurringBlockPlan(
                title: String(draft.title.prefix(80)),
                domains: domains,
                applications: resolution.applications,
                weekdays: draft.recurrenceDays,
                startHour: draft.recurrenceStartHour,
                startMinute: draft.recurrenceStartMinute,
                durationMinutes: duration,
                strictness: strictness,
                summary: String(draft.summary.prefix(240))
            )
            recurringPreviewWarnings = warning
            recurringPreviewInterpretation = interpretation
            recurringSelectedStrictness = strictness
        }
    }
}
