import AppKit
import FocusGuardCore
import SwiftUI

struct RecurringPlanRow: View {
    let plan: RecurringBlockPlan
    let now: Date
    let enabledAction: (Bool) -> Void
    let deleteAction: () -> Void
    let editAction: () -> Void
    let endAction: () -> Void

    private var activeOccurrence: BlockPlan? {
        plan.activeOccurrence(at: now)
    }

    var body: some View {
        HStack(spacing: 14) {
            PlanStatusIcon()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(plan.title).font(InterfaceTypography.itemTitle)
                    StrictnessBadge(strictness: plan.strictness)
                }
                Text(statusText)
                    .font(InterfaceTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(plan.daysDescription)
                    .font(InterfaceTypography.emphasized)
                Text("\(plan.startTimeDescription) · \(plan.durationDescription)")
                    .font(InterfaceTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            if let activeOccurrence {
                UnlockControl(plan: activeOccurrence, now: now, action: endAction)
            }

            Button(action: editAction) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .disabled(activeOccurrence != nil)
            .help(activeOccurrence == nil ? "Edit schedule and targets" : "An active occurrence must finish first")

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { plan.isEnabled },
                    set: { enabledAction($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(activeOccurrence != nil)
            .help(activeOccurrence == nil ? "Enable or pause this schedule" : "An active occurrence must finish first")

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(activeOccurrence != nil)
            .help(activeOccurrence == nil ? "Delete schedule" : "An active occurrence must finish first")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
        .opacity(plan.isEnabled ? 1 : 0.62)
    }

    private var statusText: String {
        if let activeOccurrence {
            if activeOccurrence.endRequestedAt != nil {
                return "Unlock requested · releases at \(activeOccurrence.effectiveEnd.formatted(date: .omitted, time: .shortened))"
            }
            return "Active until \(activeOccurrence.effectiveEnd.formatted(date: .omitted, time: .shortened))"
        }
        guard plan.isEnabled else { return "Paused" }
        if let nextStart = plan.nextStart(after: now) {
            return "Next \(nextStart.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Waiting for the next scheduled day"
    }
}
struct PlanRow: View {
    let plan: BlockPlan
    let now: Date
    let editAction: (() -> Void)?
    let endAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlanStatusIcon()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(plan.title).font(InterfaceTypography.itemTitle)
                    StrictnessBadge(strictness: plan.strictness)
                }
                Text(statusText)
                    .font(InterfaceTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(plan.domains.count + plan.applications.count) targets")
                .font(InterfaceTypography.metadata)
                .foregroundStyle(.secondary)

            if let editAction {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit commitment and targets")
            }

            UnlockControl(plan: plan, now: now, action: endAction)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 2)
    }

    private var statusText: String {
        if plan.isUpcoming(at: now) {
            return "Starts \(plan.startsAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if plan.endRequestedAt != nil, plan.isActive(at: now) {
            return "Unlock requested · releases at \(plan.effectiveEnd.formatted(date: .omitted, time: .shortened))"
        }
        return "Active until \(plan.effectiveEnd.formatted(date: .omitted, time: .shortened))"
    }
}

struct PlanStatusIcon: View {
    var body: some View {
        Image(systemName: "shield.lefthalf.filled")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ChatPalette.accent)
            .frame(width: 22, height: 28)
    }
}

struct UnlockControl: View {
    let plan: BlockPlan
    let now: Date
    let action: () -> Void
    @State private var confirmsEmergencyUnlock = false

    var body: some View {
        if plan.isActive(at: now) {
            if plan.endRequestedAt != nil {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Label("Unlocking in \(remainingDescription(at: context.date))", systemImage: "hourglass")
                        .font(InterfaceTypography.emphasized)
                        .foregroundStyle(plan.strictness == .locked ? ChatPalette.warning : ChatPalette.accent)
                }
            } else {
                Button(buttonTitle) {
                    if plan.strictness == .locked {
                        confirmsEmergencyUnlock = true
                    } else {
                        action()
                    }
                }
                .buttonStyle(.bordered)
                .tint(plan.strictness == .locked ? ChatPalette.warning : nil)
                .confirmationDialog(
                    "Emergency unlock this commitment?",
                    isPresented: $confirmsEmergencyUnlock,
                    titleVisibility: .visible
                ) {
                    Button("Start 10-minute cooling-off", role: .destructive, action: action)
                    Button("Keep commitment", role: .cancel) {}
                } message: {
                    Text("The block stays active for another 10 minutes. The request persists if FocusGuard is closed, and cannot be accelerated from the app.")
                }
            }
        }
    }

    private var buttonTitle: String {
        switch plan.strictness {
        case .flexible: "End now"
        case .focused: "Request end"
        case .locked: "Emergency unlock"
        }
    }

    private func remainingDescription(at date: Date) -> String {
        let totalSeconds = max(0, Int(ceil(plan.effectiveEnd.timeIntervalSince(date))))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "\(seconds)s" }
        return "\(minutes)m \(seconds)s"
    }
}
