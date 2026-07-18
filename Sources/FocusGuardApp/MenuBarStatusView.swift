import AppKit
import SwiftUI

/// A compact Pomodoro readout that remains visible while working in other apps.
struct MenuBarStatusLabel: View {
    @ObservedObject var timer: PomodoroTimerModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: timer.phase == .focus ? "timer" : "cup.and.saucer.fill")
            Text(timer.timeDescription(at: timer.displayDate))
                .monospacedDigit()
        }
        .help("\(timer.phase.title) · \(timer.isRunning ? "running" : "paused")")
    }
}

/// Pomodoro progress and controls, plus shortcuts to the app and Settings.
struct MenuBarStatusView: View {
    @ObservedObject var timer: PomodoroTimerModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.phase.title)
                        .font(.headline)
                    Text(timer.isRunning ? "In progress" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PomodoroProgressRing(
                    fraction: timer.remainingFraction(at: timer.displayDate),
                    isRunning: timer.isRunning
                )
                .scaleEffect(1.2)
            }

            Text(timer.timeDescription(at: timer.displayDate))
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            ProgressView(value: 1 - timer.remainingFraction(at: timer.displayDate))
                .progressViewStyle(.linear)

            HStack(spacing: 10) {
                Button(timer.isRunning ? "Pause" : "Start") {
                    if timer.isRunning {
                        timer.pause()
                    } else {
                        timer.start()
                    }
                }
                .buttonStyle(.borderedProminent)

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
        .padding(16)
        .frame(width: 280)
    }
}
