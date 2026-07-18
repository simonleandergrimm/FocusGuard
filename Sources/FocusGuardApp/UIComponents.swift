import AppKit
import FocusGuardCore
import SwiftUI

/// A deliberately small type scale shared by the main workspace and sidebar.
/// macOS body and headline styles are both 13 pt; weight and color provide the
/// hierarchy without making adjacent parts of the interface feel mismatched.
enum InterfaceTypography {
    static let body = Font.body
    static let emphasized = Font.body.weight(.semibold)
    static let itemTitle = Font.headline
    static let metadata = Font.body
    static let badge = Font.system(.caption2, design: .rounded).weight(.bold)
}

extension RecurringBlockPlan {
    var daysDescription: String {
        let daySet = Set(weekdays)
        if daySet == Set(Weekday.ordered) { return "Every day" }
        if daySet == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) { return "Weekdays" }
        if daySet == Set([.saturday, .sunday]) { return "Weekends" }
        return Weekday.ordered.filter(daySet.contains).map(\.shortName).joined(separator: ", ")
    }

    var startTimeDescription: String {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        calendar.timeZone = timeZone
        let date = calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: 2001,
                month: 1,
                day: 1,
                hour: startHour,
                minute: startMinute
            )
        ) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    var durationDescription: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(minutes)m"
    }
}


struct UndoActivationBar: View {
    let activation: UndoableActivation
    let secondsRemaining: (Date) -> Int
    let undoAction: () -> Void

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            HStack(spacing: 13) {
                Image(systemName: activation.kind == .oneTime ? "checkmark.shield.fill" : "repeat.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ChatPalette.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activation.kind == .oneTime ? "Block started" : "Schedule enabled")
                        .font(.callout.weight(.semibold))
                    Text("\(activation.title) · \(secondsRemaining(context.date))s to undo")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 18)

                Button("Undo block", action: undoAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(ChatPalette.primaryAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: 620)
            .foregroundStyle(.white)
            .background(ChatPalette.primaryAction, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
        }
    }
}

struct GlassCard<Content: View>: View {
    var accent: Color?
    let content: Content

    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(19)
            .background(ChatPalette.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent?.opacity(0.5) ?? ChatPalette.border, lineWidth: 1)
            }
    }
}

struct StrictnessBadge: View {
    let strictness: Strictness

    var body: some View {
        Text(strictness.displayName.uppercased())
            .font(InterfaceTypography.badge)
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch strictness {
        case .flexible: ChatPalette.secondaryText
        case .focused: ChatPalette.focusAccent
        case .locked: ChatPalette.accent
        }
    }
}

struct StrictnessMenu: View {
    @Binding var selection: Strictness

    var body: some View {
        Menu {
            ForEach(Strictness.allCases, id: \.rawValue) { strictness in
                Button {
                    selection = strictness
                } label: {
                    Label(
                        strictness.displayName,
                        systemImage: strictness == selection ? "checkmark" : strictness.systemImage
                    )
                }
            }
        } label: {
            Label("Mode: \(selection.displayName)", systemImage: selection.systemImage)
                .frame(minWidth: 105, minHeight: 24)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.large)
        .fixedSize()
        .help("Used when the request does not explicitly name a mode")
    }
}

extension Strictness {
    var systemImage: String {
        switch self {
        case .flexible: "lock.open"
        case .focused: "timer"
        case .locked: "lock.fill"
        }
    }
}

struct TargetTag: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(ChatPalette.surfaceRaised, in: Capsule())
    }
}

struct InterpretationNote: View {
    let text: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("HOW FOCUSGUARD READ YOUR REQUEST")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(ChatPalette.accent)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatPalette.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct ApplicationClosingNotice: View {
    var body: some View {
        Label(
            "Blocked apps are force-closed immediately. Save open work before activating.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(ChatPalette.warning)
    }
}

struct DetailLabel: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(ChatPalette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.callout.weight(.medium))
            }
        }
    }
}

enum ChatPalette {
    static let canvas = Color.white
    static let canvasTop = Color.white
    static let canvasBottom = Color.white
    static let sidebar = Color(red: 0.972, green: 0.972, blue: 0.972)
    static let surface = Color.white
    static let surfaceRaised = Color(red: 0.938, green: 0.938, blue: 0.938)
    static let composer = Color(red: 0.967, green: 0.967, blue: 0.967)
    static let primaryAction = Color(red: 0.105, green: 0.125, blue: 0.165)
    static let accent = Color(red: 0.105, green: 0.455, blue: 0.900)
    static let focusAccent = Color(red: 0.245, green: 0.425, blue: 0.760)
    static let warning = Color(red: 0.720, green: 0.455, blue: 0.090)
    static let secondaryText = Color(red: 0.365, green: 0.405, blue: 0.475)
    static let border = Color.black.opacity(0.09)
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
