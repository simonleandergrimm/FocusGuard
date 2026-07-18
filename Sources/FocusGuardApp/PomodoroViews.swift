import SwiftUI

struct PomodoroSidebarControl: View {
    @ObservedObject var timer: PomodoroTimerModel
    var compact = false
    @State private var showsPopover = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            HStack(spacing: 6) {
                Button {
                    if timer.isRunning {
                        timer.pause()
                    } else {
                        timer.start()
                    }
                } label: {
                    PomodoroProgressRing(
                        fraction: timer.remainingFraction(at: context.date),
                        isRunning: timer.isRunning
                    )
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(timer.isRunning ? "Pause Pomodoro" : "Start Pomodoro")

                Button {
                    showsPopover.toggle()
                } label: {
                    HStack(spacing: 10) {
                        if !compact {
                            Text("Pomodoro")
                                .lineLimit(1)
                            Spacer(minLength: 6)
                        }

                        Text(timer.timeDescription(at: context.date))
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(timer.isRunning ? ChatPalette.accent : .secondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Adjust Pomodoro timer")
                .popover(isPresented: $showsPopover, arrowEdge: .trailing) {
                    PomodoroPopover(timer: timer)
                }
            }
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, 6)
            .background(ChatPalette.surfaceRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct PomodoroProgressRing: View {
    let fraction: Double
    let isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(ChatPalette.border, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isRunning ? ChatPalette.accent : ChatPalette.secondaryText.opacity(0.7),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: isRunning ? "pause.fill" : "timer")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(isRunning ? ChatPalette.accent : ChatPalette.secondaryText)
        }
        .frame(width: 22, height: 22)
    }
}

private struct PomodoroPopover: View {
    @ObservedObject var timer: PomodoroTimerModel

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pomodoro")
                            .font(.headline)
                        Text(timer.phase.title)
                            .font(.caption)
                            .foregroundStyle(timer.isRunning ? ChatPalette.accent : .secondary)
                    }
                    Spacer()
                    PomodoroProgressRing(
                        fraction: timer.remainingFraction(at: context.date),
                        isRunning: timer.isRunning
                    )
                    .scaleEffect(1.35)
                }

                Text(timer.timeDescription(at: context.date))
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .monospacedDigit()

                HStack(spacing: 10) {
                    Button(timer.isRunning ? "Pause" : "Start") {
                        if timer.isRunning {
                            timer.pause()
                        } else {
                            timer.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)

                    Button("Reset") { timer.reset() }
                        .buttonStyle(.bordered)

                    Spacer()

                    Button(timer.phase == .focus ? "Take break" : "Focus") {
                        timer.switchPhase()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Divider()

                VStack(spacing: 12) {
                    Stepper(
                        "Focus · \(timer.focusMinutes) min",
                        value: Binding(
                            get: { timer.focusMinutes },
                            set: { timer.setFocusMinutes($0) }
                        ),
                        in: 5...120,
                        step: 5
                    )
                    Stepper(
                        "Break · \(timer.breakMinutes) min",
                        value: Binding(
                            get: { timer.breakMinutes },
                            set: { timer.setBreakMinutes($0) }
                        ),
                        in: 1...30
                    )
                }
                .disabled(!timer.canEditDurations)

                if !timer.canEditDurations {
                    Text("Reset the current interval before changing its durations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(width: 310)
        }
    }
}
