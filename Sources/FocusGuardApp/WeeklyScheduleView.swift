import FocusGuardCore
import SwiftUI

struct WeeklyScheduleView: View {
    let plans: [RecurringBlockPlan]

    private var segments: [WeeklyScheduleSegment] {
        Self.makeSegments(from: plans.filter(\.isEnabled))
    }

    private var visibleStart: Int {
        guard let earliest = segments.map(\.startMinute).min() else { return 8 * 60 }
        return max(0, ((earliest - 60) / 60) * 60)
    }

    private var visibleEnd: Int {
        guard let latest = segments.map(\.endMinute).max() else { return 18 * 60 }
        return min(1_440, Int(ceil(Double(latest + 60) / 60.0)) * 60)
    }

    private var calendarHeight: CGFloat {
        let span = max(60, visibleEnd - visibleStart)
        return min(max(CGFloat(span) * 0.34, 260), 480)
    }

    private var overlapCount: Int {
        var overlaps = Set<String>()
        for day in 0..<7 {
            let daySegments = segments.filter { $0.dayIndex == day }
            for firstIndex in daySegments.indices {
                for secondIndex in daySegments.indices where secondIndex > firstIndex {
                    let first = daySegments[firstIndex]
                    let second = daySegments[secondIndex]
                    guard first.planID != second.planID,
                          first.startMinute < second.endMinute,
                          second.startMinute < first.endMinute
                    else { continue }
                    let pair = [first.planID.uuidString, second.planID.uuidString].sorted().joined(separator: ":")
                    overlaps.insert("\(day):\(pair)")
                }
            }
        }
        return overlaps.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly calendar")
                        .font(.title3.weight(.semibold))
                    Text("Enabled recurring schedules · shown in their saved local times")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if overlapCount > 0 {
                    Label(
                        "\(overlapCount) \(overlapCount == 1 ? "overlap" : "overlaps")",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ChatPalette.warning)
                }
            }

            if segments.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Enable a recurring schedule to see it on the week.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            } else {
                dayHeaders
                calendarGrid
            }
        }
        .padding(19)
        .background(ChatPalette.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ChatPalette.border, lineWidth: 1)
        }
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 48)
            ForEach(Weekday.ordered, id: \.rawValue) { day in
                Text(day.shortName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        GeometryReader { geometry in
            let gutter: CGFloat = 48
            let usableWidth = max(1, geometry.size.width - gutter)
            let dayWidth = usableWidth / 7
            let minuteScale = calendarHeight / CGFloat(max(1, visibleEnd - visibleStart))
            let tickInterval = visibleEnd - visibleStart > 12 * 60 ? 120 : 60
            let firstTick = Int(ceil(Double(visibleStart) / Double(tickInterval))) * tickInterval
            let ticks = Array(stride(from: firstTick, to: visibleEnd, by: tickInterval))

            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { minute in
                    let y = CGFloat(minute - visibleStart) * minuteScale
                    Text(Self.timeLabel(minute))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .trailing)
                        .offset(x: 0, y: y - 6)
                    Rectangle()
                        .fill(ChatPalette.border)
                        .frame(width: usableWidth, height: 1)
                        .offset(x: gutter, y: y)
                }

                ForEach(0...7, id: \.self) { column in
                    Rectangle()
                        .fill(ChatPalette.border)
                        .frame(width: 1, height: calendarHeight)
                        .offset(x: gutter + CGFloat(column) * dayWidth)
                }

                ForEach(segments) { segment in
                    let layout = overlapLayout(for: segment)
                    let laneCount = CGFloat(max(1, layout.count))
                    let lane = CGFloat(layout.index)
                    let laneWidth = max(4, (dayWidth - 6) / laneCount)
                    let x = gutter + CGFloat(segment.dayIndex) * dayWidth + 3 + lane * laneWidth
                    let y = CGFloat(segment.startMinute - visibleStart) * minuteScale
                    let height = max(18, CGFloat(segment.endMinute - segment.startMinute) * minuteScale)

                    WeeklyScheduleBlockView(
                        segment: segment,
                        isOverlapping: layout.count > 1,
                        availableHeight: height
                    )
                    .frame(width: max(3, laneWidth - 3), height: height)
                    .offset(x: x, y: y)
                }
            }
        }
        .frame(height: calendarHeight)
        .clipped()
        .allowsHitTesting(false)
        .background(ChatPalette.composer.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private func overlapLayout(for segment: WeeklyScheduleSegment) -> (index: Int, count: Int) {
        let concurrent = segments
            .filter {
                $0.dayIndex == segment.dayIndex
                    && $0.startMinute < segment.endMinute
                    && segment.startMinute < $0.endMinute
            }
            .sorted {
                if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
                return $0.id < $1.id
            }
        return (
            concurrent.firstIndex(where: { $0.id == segment.id }) ?? 0,
            concurrent.count
        )
    }

    private static func makeSegments(from plans: [RecurringBlockPlan]) -> [WeeklyScheduleSegment] {
        var result: [WeeklyScheduleSegment] = []
        for plan in plans {
            for weekday in plan.weekdays {
                guard let originalDay = Weekday.ordered.firstIndex(of: weekday) else { continue }
                var remaining = plan.durationMinutes
                var dayIndex = originalDay
                var startMinute = plan.startHour * 60 + plan.startMinute
                var part = 0

                while remaining > 0, part < 8 {
                    let length = min(remaining, 1_440 - startMinute)
                    result.append(
                        WeeklyScheduleSegment(
                            id: "\(plan.id.uuidString)-\(weekday.rawValue)-\(part)",
                            planID: plan.id,
                            title: plan.title,
                            strictness: plan.strictness,
                            dayIndex: dayIndex,
                            startMinute: startMinute,
                            endMinute: startMinute + length
                        )
                    )
                    remaining -= length
                    dayIndex = (dayIndex + 1) % 7
                    startMinute = 0
                    part += 1
                }
            }
        }
        return result
    }

    private static func timeLabel(_ minute: Int) -> String {
        let normalized = min(max(minute, 0), 1_440)
        if normalized == 1_440 { return "24:00" }
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }
}

private struct WeeklyScheduleSegment: Identifiable {
    let id: String
    let planID: UUID
    let title: String
    let strictness: Strictness
    let dayIndex: Int
    let startMinute: Int
    let endMinute: Int
}

private struct WeeklyScheduleBlockView: View {
    let segment: WeeklyScheduleSegment
    let isOverlapping: Bool
    let availableHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(segment.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .lineLimit(availableHeight >= 34 ? 2 : 1)
            if availableHeight >= 44 {
                Text("\(Self.time(segment.startMinute))–\(Self.time(segment.endMinute))")
                    .font(.system(size: 8, design: .rounded))
                    .opacity(0.75)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.19), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isOverlapping ? ChatPalette.warning : color.opacity(0.65), lineWidth: isOverlapping ? 1.5 : 1)
        }
        .foregroundStyle(Color.primary)
        .help(isOverlapping ? "This schedule overlaps another enabled schedule" : segment.title)
    }

    private var color: Color {
        switch segment.strictness {
        case .flexible: ChatPalette.secondaryText
        case .focused: ChatPalette.focusAccent
        case .locked: ChatPalette.accent
        }
    }

    private static func time(_ minute: Int) -> String {
        let normalized = min(max(minute, 0), 1_440)
        if normalized == 1_440 { return "24:00" }
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }
}
