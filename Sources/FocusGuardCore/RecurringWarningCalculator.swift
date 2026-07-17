public struct WeeklyClockTime: Equatable, Sendable {
    public let weekday: Weekday
    public let hour: Int
    public let minute: Int

    public init(weekday: Weekday, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

public enum RecurringWarningCalculator {
    public static func warningTime(
        weekday: Weekday,
        startHour: Int,
        startMinute: Int,
        leadMinutes: Int
    ) -> WeeklyClockTime {
        let dayIndex = Weekday.ordered.firstIndex(of: weekday) ?? 0
        let start = dayIndex * 1_440 + startHour * 60 + startMinute
        let minutesPerWeek = 7 * 1_440
        let warning = (start - max(0, leadMinutes) + minutesPerWeek) % minutesPerWeek
        return WeeklyClockTime(
            weekday: Weekday.ordered[warning / 1_440],
            hour: (warning % 1_440) / 60,
            minute: warning % 60
        )
    }
}
