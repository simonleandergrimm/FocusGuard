import Foundation
@preconcurrency import UserNotifications

enum PomodoroPhase: String, Codable, Sendable {
    case focus
    case breakTime

    var title: String {
        switch self {
        case .focus: "Focus"
        case .breakTime: "Break"
        }
    }

    var next: PomodoroPhase {
        switch self {
        case .focus: .breakTime
        case .breakTime: .focus
        }
    }
}

private struct StoredPomodoroState: Codable {
    let phase: PomodoroPhase
    let focusMinutes: Int
    let breakMinutes: Int
    let isRunning: Bool
    let endDate: Date?
    let remainingSeconds: Int
}

private final class PomodoroNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class PomodoroTimerModel: ObservableObject {
    private static let storageKey = "pomodoroTimerState.v2"
    private static let legacyNotificationIdentifier = "focusguard.pomodoro.complete"
    private static let notificationIdentifierPrefix = "focusguard.pomodoro.complete"

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var focusMinutes = 45
    @Published private(set) var breakMinutes = 5
    @Published private(set) var isRunning = false
    @Published private(set) var endDate: Date?
    @Published private(set) var storedRemainingSeconds = 45 * 60
    @Published private(set) var displayDate = Date()

    private let defaults: UserDefaults
    private let notificationPresenter: PomodoroNotificationPresenter
    private var tickTask: Task<Void, Never>?
    private var notificationGeneration = UUID()
    private var scheduledNotificationIdentifier: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let notificationPresenter = PomodoroNotificationPresenter()
        self.notificationPresenter = notificationPresenter
        UNUserNotificationCenter.current().delegate = notificationPresenter
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.legacyNotificationIdentifier]
        )
        restore()
        let now = Date()
        displayDate = now
        let advancedToCurrentInterval = reconcile(at: now)
        if isRunning && !advancedToCurrentInterval {
            scheduleCompletionNotification()
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                guard let self, self.isRunning else { continue }
                let now = Date()
                if Int(now.timeIntervalSince1970) != Int(self.displayDate.timeIntervalSince1970) {
                    self.displayDate = now
                }
                self.reconcile(at: now)
            }
        }
    }

    deinit {
        tickTask?.cancel()
    }

    var canEditDurations: Bool {
        !isRunning && storedRemainingSeconds == durationSeconds(for: phase)
    }

    func remainingSeconds(at date: Date = Date()) -> Int {
        if isRunning, let endDate {
            return max(0, Int(ceil(endDate.timeIntervalSince(date))))
        }
        return max(0, storedRemainingSeconds)
    }

    func remainingFraction(at date: Date = Date()) -> Double {
        let duration = max(1, durationSeconds(for: phase))
        return min(1, max(0, Double(remainingSeconds(at: date)) / Double(duration)))
    }

    func timeDescription(at date: Date = Date()) -> String {
        let seconds = remainingSeconds(at: date)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    func start() {
        let now = Date()
        displayDate = now
        reconcile(at: now)
        guard !isRunning else { return }
        if storedRemainingSeconds <= 0 {
            storedRemainingSeconds = durationSeconds(for: phase)
        }
        isRunning = true
        endDate = now.addingTimeInterval(TimeInterval(storedRemainingSeconds))
        persist()
        scheduleCompletionNotification()
    }

    func pause() {
        guard isRunning else { return }
        let now = Date()
        displayDate = now
        storedRemainingSeconds = remainingSeconds(at: now)
        isRunning = false
        endDate = nil
        cancelCompletionNotification()
        persist()
    }

    func reset() {
        displayDate = Date()
        isRunning = false
        endDate = nil
        storedRemainingSeconds = durationSeconds(for: phase)
        cancelCompletionNotification()
        persist()
    }

    func switchPhase() {
        displayDate = Date()
        isRunning = false
        endDate = nil
        phase = phase.next
        storedRemainingSeconds = durationSeconds(for: phase)
        cancelCompletionNotification()
        persist()
    }

    func setFocusMinutes(_ minutes: Int) {
        let previousDuration = focusMinutes * 60
        let shouldResetRemaining = phase == .focus
            && !isRunning
            && storedRemainingSeconds == previousDuration
        focusMinutes = min(120, max(5, minutes))
        if shouldResetRemaining {
            storedRemainingSeconds = focusMinutes * 60
        }
        persist()
    }

    func setBreakMinutes(_ minutes: Int) {
        let previousDuration = breakMinutes * 60
        let shouldResetRemaining = phase == .breakTime
            && !isRunning
            && storedRemainingSeconds == previousDuration
        breakMinutes = min(30, max(1, minutes))
        if shouldResetRemaining {
            storedRemainingSeconds = breakMinutes * 60
        }
        persist()
    }

    private func durationSeconds(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: focusMinutes * 60
        case .breakTime: breakMinutes * 60
        }
    }

    @discardableResult
    private func reconcile(at date: Date) -> Bool {
        guard isRunning, let currentEnd = endDate, date >= currentEnd else { return false }

        var nextPhase = phase
        var nextEnd = currentEnd
        repeat {
            nextPhase = nextPhase.next
            nextEnd = nextEnd.addingTimeInterval(TimeInterval(durationSeconds(for: nextPhase)))
        } while date >= nextEnd

        phase = nextPhase
        endDate = nextEnd
        storedRemainingSeconds = remainingSeconds(at: date)
        persist()
        scheduleCompletionNotification()
        return true
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(StoredPomodoroState.self, from: data)
        else { return }

        focusMinutes = min(120, max(5, stored.focusMinutes))
        breakMinutes = min(30, max(1, stored.breakMinutes))
        phase = stored.phase
        isRunning = stored.isRunning && stored.endDate != nil
        endDate = isRunning ? stored.endDate : nil
        storedRemainingSeconds = min(
            durationSeconds(for: phase),
            max(0, stored.remainingSeconds)
        )
    }

    private func persist() {
        let state = StoredPomodoroState(
            phase: phase,
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes,
            isRunning: isRunning,
            endDate: endDate,
            remainingSeconds: isRunning ? remainingSeconds(at: Date()) : storedRemainingSeconds
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func scheduleCompletionNotification() {
        guard let scheduledEnd = endDate else { return }
        let scheduledPhase = phase
        let identifier = Self.notificationIdentifier(for: scheduledPhase, endingAt: scheduledEnd)
        scheduledNotificationIdentifier = identifier
        let generation = UUID()
        notificationGeneration = generation

        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional,
                  let self,
                  self.notificationGeneration == generation,
                  self.isRunning,
                  self.endDate == scheduledEnd
            else { return }

            let content = UNMutableNotificationContent()
            switch scheduledPhase {
            case .focus:
                content.title = "Focus session complete"
                content.body = "Your \(self.breakMinutes)-minute break has started."
            case .breakTime:
                content.title = "Break complete"
                content.body = "Your next \(self.focusMinutes)-minute focus session has started."
            }
            content.sound = .default
            content.threadIdentifier = "focusguard-pomodoro"

            let delay = max(1, scheduledEnd.timeIntervalSinceNow)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            )
            try? await center.add(request)
        }
    }

    private func cancelCompletionNotification() {
        notificationGeneration = UUID()
        guard let scheduledNotificationIdentifier else { return }
        self.scheduledNotificationIdentifier = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [scheduledNotificationIdentifier]
        )
    }

    private static func notificationIdentifier(
        for phase: PomodoroPhase,
        endingAt endDate: Date
    ) -> String {
        let endMilliseconds = Int64((endDate.timeIntervalSince1970 * 1_000).rounded())
        return "\(notificationIdentifierPrefix).\(phase.rawValue).\(endMilliseconds)"
    }
}
