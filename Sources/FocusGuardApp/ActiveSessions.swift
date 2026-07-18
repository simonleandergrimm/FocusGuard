import AppKit
import FocusGuardCore
import SwiftUI

struct ActiveSessionSnapshot: Identifiable {
    let id: String
    let title: String
    let source: String
    let scheduleDescription: String?
    let plan: BlockPlan
    let recurringPlan: RecurringBlockPlan?

    var targetCount: Int {
        plan.domains.count + plan.applications.count
    }
}

struct ActiveSessionsRail: View {
    @ObservedObject var model: AppModel
    @State private var selectedSession: ActiveSessionSnapshot?

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let sessions = activeSessions(at: context.date)

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(sessions.isEmpty ? ChatPalette.secondaryText : ChatPalette.accent)
                        .frame(width: 8, height: 8)
                    Text("ACTIVE NOW")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.1)
                    Spacer()
                    Text("\(sessions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Divider().overlay(ChatPalette.border)

                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .font(.title2)
                            .foregroundStyle(ChatPalette.secondaryText)
                        Text("No active sessions")
                            .font(.callout.weight(.semibold))
                        Text("Current one-time and recurring blocks will appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(sessions) { session in
                                Button {
                                    selectedSession = session
                                } label: {
                                    ActiveSessionCard(session: session, now: context.date)
                                }
                                .buttonStyle(.plain)
                                .help("Show exactly what this session is blocking")
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ChatPalette.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ChatPalette.border, lineWidth: 1)
            }
        }
        .sheet(item: $selectedSession) { session in
            ActiveSessionDetailsView(session: session) { strengthened in
                switch strengthened {
                case .oneTime(let plan):
                    try model.strengthenPlan(plan)
                case .recurring(let plan):
                    try model.strengthenRecurringPlan(plan)
                }
            }
        }
    }

    private func activeSessions(at date: Date) -> [ActiveSessionSnapshot] {
        let oneTime = model.plans
            .filter { $0.isActive(at: date) }
            .map {
                ActiveSessionSnapshot(
                    id: "one-time-\($0.id.uuidString)",
                    title: $0.title,
                    source: "One-time",
                    scheduleDescription: nil,
                    plan: $0,
                    recurringPlan: nil
                )
            }
        let recurring = model.recurringPlans.compactMap { schedule -> ActiveSessionSnapshot? in
            guard let occurrence = schedule.activeOccurrence(at: date) else { return nil }
            return ActiveSessionSnapshot(
                id: "recurring-\(schedule.id.uuidString)-\(Int(occurrence.startsAt.timeIntervalSince1970))",
                title: schedule.title,
                source: "Recurring",
                scheduleDescription: "\(schedule.daysDescription) at \(schedule.startTimeDescription)",
                plan: occurrence,
                recurringPlan: schedule
            )
        }
        return (oneTime + recurring).sorted { $0.plan.effectiveEnd < $1.plan.effectiveEnd }
    }
}

struct ActiveSessionCard: View {
    let session: ActiveSessionSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(session.source.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(ChatPalette.accent)
                Spacer()
                StrictnessBadge(strictness: session.plan.strictness)
            }

            Text(session.title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)

            Label(
                session.plan.endRequestedAt == nil
                    ? "\(remainingDescription) remaining"
                    : "Unlocking in \(remainingDescription)",
                systemImage: session.plan.endRequestedAt == nil ? "clock" : "hourglass"
            )
            .font(.caption)
            .foregroundStyle(session.plan.endRequestedAt == nil ? .secondary : ChatPalette.warning)

            HStack {
                Text("\(session.targetCount) \(session.targetCount == 1 ? "target" : "targets")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatPalette.composer.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ChatPalette.border, lineWidth: 1)
        }
    }

    private var remainingDescription: String {
        let totalSeconds = max(0, Int(ceil(session.plan.effectiveEnd.timeIntervalSince(now))))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

struct ActiveSessionDetailsView: View {
    let session: ActiveSessionSnapshot
    let onStrengthen: (StrengthenedSession) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsStrengthenEditor = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(session.plan.isActive(at: context.date) ? ChatPalette.accent : ChatPalette.secondaryText)
                                .frame(width: 8, height: 8)
                            Text(session.plan.isActive(at: context.date) ? "ACTIVE NOW" : "SESSION FINISHED")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(session.plan.isActive(at: context.date) ? ChatPalette.accent : .secondary)
                        }
                        Text(session.title)
                            .font(.title2.weight(.semibold))
                        Text(session.scheduleDescription ?? "One-time commitment")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    StrictnessBadge(strictness: session.plan.strictness)

                    if session.plan.isActive(at: context.date) {
                        Button {
                            showsStrengthenEditor = true
                        } label: {
                            Label("Strengthen", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChatPalette.primaryAction)
                    }

                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                }
                .padding(24)

                Divider().overlay(ChatPalette.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !session.plan.summary.isEmpty {
                            Text(session.plan.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 32) {
                            DetailLabel(
                                title: "Started",
                                value: session.plan.startsAt.formatted(date: .abbreviated, time: .shortened),
                                icon: "play.fill"
                            )
                            DetailLabel(
                                title: session.plan.endRequestedAt == nil ? "Ends" : "Releases",
                                value: session.plan.effectiveEnd.formatted(date: .abbreviated, time: .shortened),
                                icon: session.plan.endRequestedAt == nil ? "stop.fill" : "hourglass"
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("MODE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(.secondary)
                            Text(session.plan.strictness.explanation)
                                .font(.callout)
                        }

                        if !session.plan.domains.isEmpty {
                            targetSection(
                                title: "Websites",
                                subtitle: "These websites are redirected to the FocusGuard block page.",
                                icon: "globe",
                                values: session.plan.domains
                            )
                        }

                        if !session.plan.applications.isEmpty {
                            targetSection(
                                title: "Applications",
                                subtitle: "These applications are kept closed while the session is active.",
                                icon: "app",
                                values: session.plan.applications.map(\.displayName)
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 560, minHeight: 540)
            .background(ChatPalette.canvasTop)
        }
        .sheet(isPresented: $showsStrengthenEditor) {
            StrengthenSessionEditor(session: session) { strengthened in
                try onStrengthen(strengthened)
                dismiss()
            }
        }
    }

    private func targetSection(
        title: String,
        subtitle: String,
        icon: String,
        values: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Text("\(values.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .frame(width: 18)
                            .foregroundStyle(ChatPalette.accent)
                        Text(value)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(.vertical, 9)

                    if index < values.count - 1 {
                        Divider().overlay(ChatPalette.border)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(ChatPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ChatPalette.border, lineWidth: 1)
            }
        }
    }
}

enum StrengthenedSession {
    case oneTime(BlockPlan)
    case recurring(RecurringBlockPlan)
}

struct StrengthenSessionEditor: View {
    let session: ActiveSessionSnapshot
    let onSave: (StrengthenedSession) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var domains: [String]
    @State private var applications: [BlockedApplication]
    @State private var endsAt: Date
    @State private var strictness: Strictness
    @State private var validationMessage: String?
    @State private var installedApplications: [InstalledApplication]

    init(
        session: ActiveSessionSnapshot,
        onSave: @escaping (StrengthenedSession) throws -> Void
    ) {
        self.session = session
        self.onSave = onSave
        _domains = State(initialValue: session.plan.domains)
        _applications = State(initialValue: session.plan.applications)
        _endsAt = State(initialValue: session.plan.endsAt)
        _strictness = State(initialValue: session.plan.strictness)
        _installedApplications = State(initialValue: ApplicationCatalog.load().applications)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strengthen active block")
                        .font(.title2.weight(.semibold))
                    Text("You can add coverage, extend the end, or choose a stricter mode. Existing protection cannot be removed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(24)

            Divider().overlay(ChatPalette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if session.recurringPlan != nil {
                        Label(
                            "Changes strengthen the current occurrence and future occurrences of this recurring schedule.",
                            systemImage: "repeat"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    GroupBox("Stronger settings") {
                        VStack(alignment: .leading, spacing: 14) {
                            DatePicker(
                                "Block through",
                                selection: $endsAt,
                                in: session.plan.endsAt...maximumEnd,
                                displayedComponents: [.date, .hourAndMinute]
                            )

                            Picker("Mode", selection: $strictness) {
                                ForEach(allowedStrictness, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(strictness.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }

                    ManualTargetsEditor(
                        domains: $domains,
                        applications: $applications,
                        installedApplications: installedApplications,
                        protectedDomains: Set(session.plan.domains),
                        protectedApplicationIDs: Set(session.plan.applications.map(\.bundleIdentifier))
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
                Button("Apply stronger block", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 650, minHeight: 700)
        .background(ChatPalette.canvasTop)
    }

    private var allowedStrictness: [Strictness] {
        Strictness.allCases.filter { $0.strengthRank >= session.plan.strictness.strengthRank }
    }

    private var maximumEnd: Date {
        max(
            session.plan.endsAt,
            session.plan.startsAt.addingTimeInterval(7 * 24 * 60 * 60)
        )
    }

    private func save() {
        let normalizedDomains = DomainNormalizer.normalizeAll(domains)
        let originalDomains = Set(session.plan.domains)
        let originalApplicationIDs = Set(session.plan.applications.map(\.bundleIdentifier))
        let updatedApplicationIDs = Set(applications.map(\.bundleIdentifier))

        guard Set(normalizedDomains).isSuperset(of: originalDomains),
              updatedApplicationIDs.isSuperset(of: originalApplicationIDs),
              endsAt >= session.plan.endsAt,
              strictness.strengthRank >= session.plan.strictness.strengthRank
        else {
            validationMessage = "Existing duration, targets, and strictness cannot be reduced while this block is active."
            return
        }

        let changed = Set(normalizedDomains) != originalDomains
            || updatedApplicationIDs != originalApplicationIDs
            || endsAt > session.plan.endsAt
            || strictness != session.plan.strictness
        guard changed else {
            validationMessage = "Add a target, extend the end time, or choose a stricter mode."
            return
        }

        do {
            if let recurring = session.recurringPlan {
                let duration = max(
                    recurring.durationMinutes,
                    Int(ceil(endsAt.timeIntervalSince(session.plan.startsAt) / 60))
                )
                let updated = RecurringBlockPlan(
                    id: recurring.id,
                    title: recurring.title,
                    domains: normalizedDomains,
                    applications: applications,
                    weekdays: recurring.weekdays,
                    startHour: recurring.startHour,
                    startMinute: recurring.startMinute,
                    durationMinutes: duration,
                    timeZoneIdentifier: recurring.timeZoneIdentifier,
                    strictness: strictness,
                    summary: recurring.summary,
                    createdAt: recurring.createdAt,
                    isEnabled: recurring.isEnabled,
                    endRequestedAt: recurring.endRequestedAt,
                    endRequestedOccurrenceStartsAt: recurring.endRequestedOccurrenceStartsAt
                )
                try onSave(.recurring(updated))
            } else {
                let updated = BlockPlan(
                    id: session.plan.id,
                    title: session.plan.title,
                    domains: normalizedDomains,
                    applications: applications,
                    startsAt: session.plan.startsAt,
                    endsAt: endsAt,
                    strictness: strictness,
                    summary: session.plan.summary,
                    endRequestedAt: session.plan.endRequestedAt
                )
                try onSave(.oneTime(updated))
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

