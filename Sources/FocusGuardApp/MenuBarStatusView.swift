import AppKit
import FocusGuardCore
import SwiftUI

/// The menu bar label: a shield that fills while any block is active.
struct MenuBarStatusLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Image(systemName: model.hasActiveSession(at: context.date) ? "shield.fill" : "shield")
        }
    }
}

/// The menu bar dropdown: active sessions with remaining time, plus
/// shortcuts to the main window and Settings.
struct MenuBarStatusView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                let sessions = model.activeSessionSummaries(at: context.date)

                if sessions.isEmpty {
                    Label("No active blocks", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sessions) { session in
                            HStack(alignment: .firstTextBaseline) {
                                Text(session.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 16)
                                Text(Self.remainingDescription(until: session.endsAt, from: context.date))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Button("Open FocusGuard") {
                        openWindow(id: FocusGuardApp.mainWindowID)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    Spacer()
                    Button("Settings…") {
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .controlSize(.small)
            }
            .padding(14)
            .frame(width: 280)
        }
    }

    static func remainingDescription(until end: Date, from date: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(date).rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))m"
        }
        return "\(minutes)m \(String(format: "%02d", seconds % 60))s"
    }
}

struct ActiveSessionSummary: Identifiable {
    let id: String
    let title: String
    let endsAt: Date
}

extension AppModel {
    func hasActiveSession(at date: Date) -> Bool {
        !activeSessionSummaries(at: date).isEmpty
    }

    func activeSessionSummaries(at date: Date) -> [ActiveSessionSummary] {
        let oneTime = plans
            .filter { $0.isActive(at: date) }
            .map { ActiveSessionSummary(id: "plan-\($0.id)", title: $0.title, endsAt: $0.effectiveEnd) }
        let recurring = recurringPlans.compactMap { schedule -> ActiveSessionSummary? in
            guard let occurrence = schedule.activeOccurrence(at: date) else { return nil }
            return ActiveSessionSummary(
                id: "recurring-\(schedule.id)",
                title: schedule.title,
                endsAt: occurrence.effectiveEnd
            )
        }
        return (oneTime + recurring).sorted { $0.endsAt < $1.endsAt }
    }
}
