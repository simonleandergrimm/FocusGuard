import FocusGuardCore
import Foundation
import UserNotifications

enum RecurringNotificationManager {
    static let leadMinutes = 5
    private static let identifierPrefix = "focusguard.recurring-warning."

    static func synchronize(
        plans: [RecurringBlockPlan],
        enabled: Bool
    ) async -> String {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existingIDs)

        let enabledPlans = plans.filter(\.isEnabled)
        guard enabled, !enabledPlans.isEmpty else {
            return enabled ? "No enabled recurring schedules need warnings." : "Recurring warnings are off."
        }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            } catch {
                return "FocusGuard could not request notification permission: \(error.localizedDescription)"
            }
        }

        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else {
            return "Recurring warnings are enabled, but notifications are disabled in macOS Settings."
        }

        var scheduledCount = 0
        for plan in enabledPlans {
            for day in plan.weekdays {
                let warning = RecurringWarningCalculator.warningTime(
                    weekday: day,
                    startHour: plan.startHour,
                    startMinute: plan.startMinute,
                    leadMinutes: leadMinutes
                )
                var components = DateComponents()
                components.calendar = Calendar(identifier: .gregorian)
                components.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
                components.weekday = calendarWeekday(warning.weekday)
                components.hour = warning.hour
                components.minute = warning.minute

                let content = UNMutableNotificationContent()
                content.title = "FocusGuard starts in \(leadMinutes) minutes"
                let targetCount = plan.domains.count + plan.applications.count
                content.body = "\(plan.title) will block \(targetCount) \(targetCount == 1 ? "target" : "targets")."
                content.sound = .default
                content.threadIdentifier = "focusguard-recurring"

                let request = UNNotificationRequest(
                    identifier: "\(identifierPrefix)\(plan.id.uuidString).\(day.rawValue)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )
                do {
                    try await center.add(request)
                    scheduledCount += 1
                } catch {
                    return "FocusGuard could not schedule every recurring warning: \(error.localizedDescription)"
                }
            }
        }

        return "\(scheduledCount) weekly \(scheduledCount == 1 ? "warning" : "warnings") scheduled \(leadMinutes) minutes early."
    }

    private static func calendarWeekday(_ weekday: Weekday) -> Int {
        // Calendar uses Sunday = 1, while FocusGuard's visual week starts Monday.
        guard let dayIndex = Weekday.ordered.firstIndex(of: weekday) else { return 2 }
        return dayIndex == 6 ? 1 : dayIndex + 2
    }
}
