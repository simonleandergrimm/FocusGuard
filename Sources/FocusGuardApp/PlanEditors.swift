import AppKit
import FocusGuardCore
import SwiftUI

struct OneTimePlanEditor: View {
    let originalPlan: BlockPlan
    let isCreating: Bool
    let onSave: (BlockPlan) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var domains: [String]
    @State private var applications: [BlockedApplication]
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var strictness: Strictness
    @State private var startsImmediately: Bool
    @State private var validationMessage: String?
    @State private var installedApplications: [InstalledApplication]

    init(
        plan: BlockPlan,
        isCreating: Bool = false,
        onSave: @escaping (BlockPlan) throws -> Void
    ) {
        originalPlan = plan
        self.isCreating = isCreating
        self.onSave = onSave
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _domains = State(initialValue: plan.domains)
        _applications = State(initialValue: plan.applications)
        _startsAt = State(initialValue: plan.startsAt)
        _endsAt = State(initialValue: plan.endsAt)
        _strictness = State(initialValue: plan.strictness)
        _startsImmediately = State(initialValue: isCreating)
        _installedApplications = State(initialValue: ApplicationCatalog.load().applications)
    }

    var body: some View {
        editorShell(
            title: isCreating ? "Set up a block" : "Edit commitment",
            subtitle: isCreating
                ? "Choose the timing, mode, websites, and applications yourself."
                : "Changes are saved only after validation."
        ) {
            GroupBox("Commitment") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...4)

                    if isCreating {
                        Toggle("Start immediately", isOn: $startsImmediately)
                    }

                    HStack(spacing: 18) {
                        if !isCreating || !startsImmediately {
                            DatePicker("Starts", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                        }
                        DatePicker("Ends", selection: $endsAt, displayedComponents: [.date, .hourAndMinute])
                    }

                    Picker("Mode", selection: $strictness) {
                        ForEach(Strictness.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(8)
            }

            ManualTargetsEditor(
                domains: $domains,
                applications: $applications,
                installedApplications: installedApplications
            )
        }
    }

    private func editorShell<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider().overlay(ChatPalette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .padding(24)
            }

            Divider().overlay(ChatPalette.border)

            HStack {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ChatPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isCreating ? "Review block" : "Save changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 650, minHeight: 680)
        .background(ChatPalette.canvasTop)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDomains = DomainNormalizer.normalizeAll(domains)
        let now = Date()
        let effectiveStartsAt = isCreating && startsImmediately ? now : startsAt

        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a title."
            return
        }
        guard effectiveStartsAt >= now else {
            validationMessage = isCreating
                ? "Choose a future start or select Start immediately."
                : "An editable one-time commitment must start in the future."
            return
        }
        guard endsAt > effectiveStartsAt else {
            validationMessage = "The end time must be after the start time."
            return
        }
        guard endsAt.timeIntervalSince(effectiveStartsAt) <= 7 * 24 * 60 * 60 else {
            validationMessage = "A commitment can last at most seven days."
            return
        }
        guard !normalizedDomains.isEmpty || !applications.isEmpty else {
            validationMessage = "Add at least one website or application."
            return
        }

        let updatedPlan = BlockPlan(
            id: originalPlan.id,
            title: String(cleanTitle.prefix(80)),
            domains: normalizedDomains,
            applications: applications,
            startsAt: effectiveStartsAt,
            endsAt: endsAt,
            strictness: strictness,
            summary: String(cleanSummary.prefix(240))
        )

        do {
            try onSave(updatedPlan)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct RecurringPlanEditor: View {
    let originalPlan: RecurringBlockPlan
    let isCreating: Bool
    let onSave: (RecurringBlockPlan) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var domains: [String]
    @State private var applications: [BlockedApplication]
    @State private var weekdays: Set<Weekday>
    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var strictness: Strictness
    @State private var validationMessage: String?
    @State private var installedApplications: [InstalledApplication]

    init(
        plan: RecurringBlockPlan,
        isCreating: Bool = false,
        onSave: @escaping (RecurringBlockPlan) throws -> Void
    ) {
        originalPlan = plan
        self.isCreating = isCreating
        self.onSave = onSave
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _domains = State(initialValue: plan.domains)
        _applications = State(initialValue: plan.applications)
        _weekdays = State(initialValue: Set(plan.weekdays))
        _startTime = State(initialValue: Self.dateForTime(in: plan))
        _durationMinutes = State(initialValue: plan.durationMinutes)
        _strictness = State(initialValue: plan.strictness)
        _installedApplications = State(initialValue: ApplicationCatalog.load().applications)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCreating ? "Set up a recurring schedule" : "Edit recurring schedule")
                        .font(.title2.weight(.semibold))
                    Text(
                        isCreating
                            ? "Choose the days, time, mode, websites, and applications yourself."
                            : "An active occurrence must finish before this schedule can be changed."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider().overlay(ChatPalette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Schedule") {
                        VStack(alignment: .leading, spacing: 13) {
                            TextField("Title", text: $title)
                            TextField("Summary", text: $summary, axis: .vertical)
                                .lineLimit(2...4)

                            Text("Days")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 7) {
                                ForEach(Weekday.ordered, id: \.rawValue) { day in
                                    Button(day.shortName) {
                                        if weekdays.contains(day) {
                                            weekdays.remove(day)
                                        } else {
                                            weekdays.insert(day)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        weekdays.contains(day) ? ChatPalette.accent : ChatPalette.surfaceRaised,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(weekdays.contains(day) ? Color.white : Color.primary)
                                }
                            }

                            HStack(spacing: 24) {
                                DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                                Stepper(value: $durationMinutes, in: 1...10_080, step: 15) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Duration").font(.caption).foregroundStyle(.secondary)
                                        Text(durationDescription).font(.callout.weight(.medium))
                                    }
                                }
                            }

                            Picker("Mode", selection: $strictness) {
                                ForEach(Strictness.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(8)
                    }

                    ManualTargetsEditor(
                        domains: $domains,
                        applications: $applications,
                        installedApplications: installedApplications
                    )
                }
                .padding(24)
            }

            Divider().overlay(ChatPalette.border)

            HStack {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ChatPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isCreating ? "Review schedule" : "Save changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 650, minHeight: 700)
        .background(ChatPalette.canvasTop)
    }

    private var durationDescription: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDomains = DomainNormalizer.normalizeAll(domains)

        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a title."
            return
        }
        guard !weekdays.isEmpty else {
            validationMessage = "Select at least one day."
            return
        }
        guard !normalizedDomains.isEmpty || !applications.isEmpty else {
            validationMessage = "Add at least one website or application."
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: originalPlan.timeZoneIdentifier) ?? .current
        let startHour = calendar.component(.hour, from: startTime)
        let startMinute = calendar.component(.minute, from: startTime)
        let updatedPlan = RecurringBlockPlan(
            id: originalPlan.id,
            title: String(cleanTitle.prefix(80)),
            domains: normalizedDomains,
            applications: applications,
            weekdays: Weekday.ordered.filter(weekdays.contains),
            startHour: startHour,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            timeZoneIdentifier: originalPlan.timeZoneIdentifier,
            strictness: strictness,
            summary: String(cleanSummary.prefix(240)),
            createdAt: originalPlan.createdAt,
            isEnabled: originalPlan.isEnabled
        )

        guard updatedPlan.activeOccurrence(at: Date()) == nil else {
            validationMessage = "Those settings would create an occurrence already in progress. Choose another time."
            return
        }

        do {
            try onSave(updatedPlan)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private static func dateForTime(in plan: RecurringBlockPlan) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
        return calendar.date(
            bySettingHour: plan.startHour,
            minute: plan.startMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}

struct ManualTargetsEditor: View {
    @Binding var domains: [String]
    @Binding var applications: [BlockedApplication]
    let installedApplications: [InstalledApplication]
    let protectedDomains: Set<String>
    let protectedApplicationIDs: Set<String>

    @State private var domainEntry = ""
    @State private var applicationQuery = ""
    @State private var entryMessage: String?

    init(
        domains: Binding<[String]>,
        applications: Binding<[BlockedApplication]>,
        installedApplications: [InstalledApplication],
        protectedDomains: Set<String> = [],
        protectedApplicationIDs: Set<String> = []
    ) {
        _domains = domains
        _applications = applications
        self.installedApplications = installedApplications
        self.protectedDomains = protectedDomains
        self.protectedApplicationIDs = protectedApplicationIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Websites") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Add a website, e.g. example.com", text: $domainEntry)
                            .onSubmit(addDomain)
                        Button("Add", action: addDomain)
                            .disabled(domainEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if domains.isEmpty {
                        Text("No websites in this block.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(domains, id: \.self) { domain in
                            HStack {
                                Label(domain, systemImage: "globe")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                if protectedDomains.contains(domain) {
                                    Label("Current", systemImage: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button {
                                        domains.removeAll { $0 == domain }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .help("Remove \(domain)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Applications") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search installed applications", text: $applicationQuery)

                    if !applicationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if applicationMatches.isEmpty {
                            Text("No unselected installed app matches that search.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(applicationMatches, id: \.bundleIdentifier) { application in
                                    Button {
                                        addApplication(application)
                                    } label: {
                                        HStack {
                                            Label(application.displayName, systemImage: "app")
                                            Spacer()
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(ChatPalette.accent)
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.vertical, 7)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .background(ChatPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(ChatPalette.border, lineWidth: 1)
                            }
                        }
                    }

                    if applications.isEmpty {
                        Text("No applications in this block.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(applications) { application in
                            HStack {
                                Label(application.displayName, systemImage: "app")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                if protectedApplicationIDs.contains(application.bundleIdentifier) {
                                    Label("Current", systemImage: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button {
                                        applications.removeAll { $0.id == application.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .help("Remove \(application.displayName)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(8)
            }

            if let entryMessage {
                Label(entryMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(ChatPalette.warning)
            }
        }
    }

    private var applicationMatches: [InstalledApplication] {
        let query = applicationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let selectedIDs = Set(applications.map(\.bundleIdentifier))
        return Array(
            installedApplications
                .filter {
                    !selectedIDs.contains($0.bundleIdentifier)
                        && $0.displayName.localizedCaseInsensitiveContains(query)
                }
                .prefix(8)
        )
    }

    private func addDomain() {
        guard let domain = DomainNormalizer.normalize(domainEntry) else {
            entryMessage = "Enter a valid website domain, such as example.com."
            return
        }
        if !domains.contains(domain) {
            domains.append(domain)
            domains.sort()
        }
        domainEntry = ""
        entryMessage = nil
    }

    private func addApplication(_ application: InstalledApplication) {
        guard !applications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            applicationQuery = ""
            return
        }
        applications.append(
            BlockedApplication(
                displayName: application.displayName,
                bundleIdentifier: application.bundleIdentifier,
                executableName: application.executableName,
                bundleName: application.bundleName
            )
        )
        applications.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        applicationQuery = ""
        entryMessage = nil
    }
}

