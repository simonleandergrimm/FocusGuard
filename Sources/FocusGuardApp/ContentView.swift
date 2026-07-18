import AppKit
import FocusGuardCore
import SwiftUI

struct ContentView: View {
    private static let claudeFMURL = URL(string: "https://www.youtube.com/watch?v=tRsQsTMvPNg")!

    @ObservedObject var model: AppModel
    @Binding var interfaceZoom: Double
    @StateObject private var pomodoro = PomodoroTimerModel()
    @Environment(\.openSettings) private var openSettings
    @State private var selectedPane: PlanPane = .oneTime
    @State private var editingPlan: BlockPlan?
    @State private var editingRecurringPlan: RecurringBlockPlan?
    @State private var creatingPlan: BlockPlan?
    @State private var creatingRecurringPlan: RecurringBlockPlan?

    private var zoomScale: CGFloat {
        CGFloat(min(max(interfaceZoom, 0.8), 1.6))
    }

    private var interfaceTypeSize: DynamicTypeSize {
        switch interfaceZoom {
        case ..<0.85: .small
        case ..<0.95: .medium
        case ..<1.05: .large
        case ..<1.15: .xLarge
        case ..<1.35: .xxLarge
        case ..<1.55: .xxxLarge
        default: .accessibility1
        }
    }

    private var supportingFont: Font {
        .system(size: 14 * zoomScale)
    }

    var body: some View {
        ZStack {
            ChatPalette.canvas
                .ignoresSafeArea()

            GeometryReader { geometry in
                Group {
                    if geometry.size.width >= 940 {
                        sidebarLayout
                    } else {
                        compactLayout
                    }
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
            }
        }
        .dynamicTypeSize(interfaceTypeSize)
        .preferredColorScheme(.light)
        .overlay(alignment: .bottom) {
            if let activation = model.undoableActivation {
                UndoActivationBar(
                    activation: activation,
                    secondsRemaining: { model.undoSecondsRemaining(at: $0) },
                    undoAction: model.undoAutomaticActivation
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FocusDuckView()
                .padding(.trailing, 22)
                .padding(.bottom, model.undoableActivation == nil ? 18 : 84)
        }
        .task {
            model.startBackgroundManagement()
        }
        .animation(.snappy, value: model.previewPlan)
        .animation(.snappy, value: model.previewRecurringPlan)
        .animation(.snappy, value: model.undoableActivation?.id)
        .alert(
            "FocusGuard",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $editingPlan) { plan in
            OneTimePlanEditor(plan: plan) { updatedPlan in
                try model.updatePlan(updatedPlan)
            }
        }
        .sheet(item: $editingRecurringPlan) { plan in
            RecurringPlanEditor(plan: plan) { updatedPlan in
                try model.updateRecurringPlan(updatedPlan)
            }
        }
        .sheet(item: $creatingPlan) { plan in
            OneTimePlanEditor(plan: plan, isCreating: true) { newPlan in
                model.prepareManualPreview(newPlan)
            }
        }
        .sheet(item: $creatingRecurringPlan) { plan in
            RecurringPlanEditor(plan: plan, isCreating: true) { newPlan in
                model.prepareManualPreview(newPlan)
            }
        }
    }

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            sidebar

            VStack(alignment: .center, spacing: 24) {
                brand(fontSize: 30, centered: true)
                    .padding(.top, 14 * zoomScale)
                contentScrollView
            }
            .padding(.horizontal, 36 * zoomScale)
            .padding(.top, 30 * zoomScale)
            .padding(.bottom, 22 * zoomScale)
            .frame(maxWidth: 1_020, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(alignment: .top, spacing: 18) {
                ActiveSessionsRail(model: model)
                    .frame(width: 238 * zoomScale)
                    .frame(maxHeight: .infinity, alignment: .top)

                contentScrollView
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(30 * zoomScale)
        .frame(maxWidth: 1_200, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentScrollView: some View {
        ScrollView(.vertical) {
            VStack(alignment: .center, spacing: 22) {
                paneContent
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .id(selectedPane)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            ActiveSessionsRail(model: model)
                .frame(maxHeight: .infinity, alignment: .top)

            Divider().overlay(ChatPalette.border)

            helperBadge

            claudeFMButton

            PomodoroSidebarControl(timer: pomodoro)

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(ChatPalette.surfaceRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(20 * zoomScale)
        .frame(width: 252 * zoomScale)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ChatPalette.sidebar.opacity(0.78))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ChatPalette.border)
                .frame(width: 1)
        }
    }

    private var composerPanePicker: some View {
        Picker("Plan type", selection: $selectedPane) {
            Text("One-time").tag(PlanPane.oneTime)
            Text("Recurring").tag(PlanPane.recurring)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .font(supportingFont)
        .frame(width: 200 * min(zoomScale, 1.12))
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .oneTime:
            commandComposer
                .frame(maxWidth: 880)
            if let preview = model.previewPlan {
                previewCard(preview)
                    .frame(maxWidth: 880)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            schedules
                .frame(maxWidth: 880)

        case .recurring:
            recurringCommandComposer
                .frame(maxWidth: 880)
            if let preview = model.previewRecurringPlan {
                recurringPreviewCard(preview)
                    .frame(maxWidth: 880)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            WeeklyScheduleView(plans: model.recurringPlans)
                .frame(maxWidth: 960)
            recurringSchedules
                .frame(maxWidth: 880)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            brand(fontSize: 28)

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    Link(destination: Self.claudeFMURL) {
                        Label("Claude FM", systemImage: "music.note")
                    }
                    .buttonStyle(.bordered)
                    .help("Open Claude FM in your browser")

                    PomodoroSidebarControl(timer: pomodoro, compact: true)

                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                }

                helperBadge
            }
        }
    }

    private func brand(fontSize: CGFloat, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 7 * zoomScale) {
            Label("FOCUSGUARD", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 12 * zoomScale, weight: .bold, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(ChatPalette.accent)
            Text("What do you want to do,\non reflection?")
                .font(.system(size: fontSize * zoomScale, weight: .semibold, design: .rounded))
                .tracking(-0.8)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var helperBadge: some View {
        if model.helperState.needsRepair || model.isInstallingHelper {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ChatPalette.warning)
                Text(model.isInstallingHelper ? "Helper setup in progress" : model.helperState.description)
                    .font(.caption.weight(.semibold))

                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(helperRecoveryHelp)

                Button(
                    model.isInstallingHelper
                        ? "Working…"
                        : model.helperActionTitle
                ) {
                    model.installHelper()
                }
                .buttonStyle(.link)
                .disabled(model.isInstallingHelper)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ChatPalette.warning.opacity(0.10), in: Capsule())
            .overlay {
                Capsule().stroke(ChatPalette.warning.opacity(0.28), lineWidth: 1)
            }
            .onTapGesture { model.refreshHelperStatus() }
        }
    }

    private var helperRecoveryHelp: String {
        if model.isInstallingHelper {
            return "Approve the macOS administrator dialog if it is waiting. FocusGuard will check the helper again automatically."
        }
        switch model.helperState {
        case .missing:
            return "Click Set up, then approve the macOS administrator dialog to install the background helper."
        case .outdated:
            return "Click Update, then approve the macOS administrator dialog to replace the older helper."
        case .stopped:
            return "Click Repair to reinstall and restart the helper. Your saved commitments will be kept."
        case .healthy:
            return "The helper is healthy."
        }
    }

    private var claudeFMButton: some View {
        Link(destination: Self.claudeFMURL) {
            Label("Claude FM", systemImage: "music.note")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(ChatPalette.surfaceRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
        .help("Open Claude FM in your browser")
    }

    private var commandComposer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8 * zoomScale) {
                PromptTextView(
                    text: $model.prompt,
                    placeholder: "Describe what you want to block…",
                    fontSize: 17 * zoomScale,
                    onCommandEnter: {
                        model.parsePrompt(activateImmediately: true)
                    }
                )
                .frame(minHeight: 108 * zoomScale)

                Text("⌘↩ starts immediately")
                    .font(supportingFont)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24 * zoomScale)
            .padding(.top, 22 * zoomScale)
            .padding(.bottom, 16 * zoomScale)

            Divider().overlay(ChatPalette.border)

            composerFooter(
                strictness: $model.selectedStrictness,
                draftTitle: "Draft plan",
                action: { model.parsePrompt() }
            )
            .padding(.horizontal, 14 * zoomScale)
            .padding(.vertical, 12 * zoomScale)
        }
        .background(ChatPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ChatPalette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 18, y: 7)
    }

    private var recurringCommandComposer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8 * zoomScale) {
                PromptTextView(
                    text: $model.recurringPrompt,
                    placeholder: "Describe a schedule you want to repeat…",
                    fontSize: 17 * zoomScale,
                    onCommandEnter: {
                        model.parsePrompt(mode: .recurring, activateImmediately: true)
                    }
                )
                .frame(minHeight: 108 * zoomScale)

                Text("⌘↩ enables immediately")
                    .font(supportingFont)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24 * zoomScale)
            .padding(.top, 22 * zoomScale)
            .padding(.bottom, 16 * zoomScale)

            Divider().overlay(ChatPalette.border)

            composerFooter(
                strictness: $model.recurringSelectedStrictness,
                draftTitle: "Draft schedule",
                action: { model.parsePrompt(mode: .recurring) }
            )
            .padding(.horizontal, 14 * zoomScale)
            .padding(.vertical, 12 * zoomScale)
        }
        .background(ChatPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(ChatPalette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 18, y: 7)
    }

    @ViewBuilder
    private func composerFooter(
        strictness: Binding<Strictness>,
        draftTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                manualSetupButton
                composerPanePicker

                Spacer(minLength: 12)

                StrictnessMenu(selection: strictness)
                    .font(supportingFont)
                    .disabled(model.isParsing)

                draftButton(title: draftTitle, action: action)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    manualSetupButton
                    composerPanePicker
                    Spacer()
                }
                HStack {
                    Spacer()
                    StrictnessMenu(selection: strictness)
                        .font(supportingFont)
                        .disabled(model.isParsing)
                    draftButton(title: draftTitle, action: action)
                }
            }
        }
    }

    private func draftButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if model.isParsing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(ChatPalette.primaryAction, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: .black.opacity(0.09), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(model.isParsing)
        .opacity(model.isParsing ? 0.72 : 1)
        .accessibilityLabel(model.isParsing ? "Drafting" : title)
        .help(title)
    }

    private var manualSetupButton: some View {
        Button(action: beginManualSetup) {
            Label("Manual", systemImage: "plus")
                .font(supportingFont.weight(.medium))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(selectedPane == .oneTime ? "Set up a block manually" : "Set up a recurring schedule manually")
    }

    private func beginManualSetup() {
        let now = Date()
        switch selectedPane {
        case .oneTime:
            creatingPlan = BlockPlan(
                title: "Manual block",
                domains: [],
                applications: [],
                startsAt: now,
                endsAt: now.addingTimeInterval(60 * 60),
                strictness: model.selectedStrictness,
                summary: "Selected manually."
            )
        case .recurring:
            let calendar = Calendar.current
            let proposedStart = calendar.date(byAdding: .minute, value: 30, to: now) ?? now
            creatingRecurringPlan = RecurringBlockPlan(
                title: "Manual schedule",
                domains: [],
                applications: [],
                weekdays: [weekday(for: calendar.component(.weekday, from: proposedStart))],
                startHour: calendar.component(.hour, from: proposedStart),
                startMinute: calendar.component(.minute, from: proposedStart),
                durationMinutes: 60,
                strictness: model.recurringSelectedStrictness,
                summary: "Selected manually."
            )
        }
    }

    private func weekday(for calendarWeekday: Int) -> Weekday {
        switch calendarWeekday {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        default: .saturday
        }
    }

    private func previewCard(_ plan: BlockPlan) -> some View {
        GlassCard(accent: ChatPalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REVIEW BEFORE ACTIVATING")
                            .font(.caption2.bold())
                            .tracking(1.3)
                            .foregroundStyle(ChatPalette.accent)
                        Text(plan.title)
                            .font(.title2.weight(.semibold))
                    }
                    Spacer()
                    StrictnessBadge(strictness: plan.strictness)
                }

                Text(plan.summary)
                    .foregroundStyle(.secondary)

                if !model.previewInterpretation.isEmpty {
                    InterpretationNote(text: model.previewInterpretation)
                }

                HStack(spacing: 22) {
                    DetailLabel(title: "Starts", value: plan.startsAt.formatted(date: .abbreviated, time: .shortened), icon: "play.fill")
                    DetailLabel(title: "Ends", value: plan.endsAt.formatted(date: .abbreviated, time: .shortened), icon: "stop.fill")
                }

                targetTags(for: plan)

                if !plan.applications.isEmpty {
                    ApplicationClosingNotice()
                }

                ForEach(model.previewWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ChatPalette.warning)
                }

                Divider().overlay(ChatPalette.border)

                HStack {
                    Text(plan.strictness.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Discard") { model.discardPreview() }
                        .buttonStyle(.bordered)
                    if model.helperInstalled {
                        Button("Activate block") { model.activatePreview() }
                            .buttonStyle(.borderedProminent)
                            .tint(ChatPalette.primaryAction)
                    } else {
                        Button(model.isInstallingHelper ? "Installing helper…" : "Install helper first") {
                            model.installHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChatPalette.primaryAction)
                        .disabled(model.isInstallingHelper)
                    }
                }
            }
        }
    }

    private func recurringPreviewCard(_ plan: RecurringBlockPlan) -> some View {
        GlassCard(accent: ChatPalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("REVIEW RECURRING SCHEDULE")
                            .font(.caption2.bold())
                            .tracking(1.3)
                            .foregroundStyle(ChatPalette.accent)
                        Text(plan.title)
                            .font(.title2.weight(.semibold))
                    }
                    Spacer()
                    StrictnessBadge(strictness: plan.strictness)
                }

                Text(plan.summary)
                    .foregroundStyle(.secondary)

                if !model.recurringPreviewInterpretation.isEmpty {
                    InterpretationNote(text: model.recurringPreviewInterpretation)
                }

                HStack(spacing: 24) {
                    DetailLabel(title: "Repeats", value: plan.daysDescription, icon: "calendar")
                    DetailLabel(title: "Starts", value: plan.startTimeDescription, icon: "clock.fill")
                    DetailLabel(title: "Duration", value: plan.durationDescription, icon: "hourglass")
                }

                targetTags(domains: plan.domains, applications: plan.applications)

                if !plan.applications.isEmpty {
                    ApplicationClosingNotice()
                }

                ForEach(model.recurringPreviewWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ChatPalette.warning)
                }

                Divider().overlay(ChatPalette.border)

                HStack {
                    Text("The helper calculates each occurrence in \(plan.timeZoneIdentifier), even when FocusGuard is closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Discard") { model.discardRecurringPreview() }
                        .buttonStyle(.bordered)
                    if model.helperInstalled {
                        Button("Activate schedule") { model.activateRecurringPreview() }
                            .buttonStyle(.borderedProminent)
                            .tint(ChatPalette.primaryAction)
                    } else {
                        Button(model.isInstallingHelper ? "Installing helper…" : "Install helper first") {
                            model.installHelper()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChatPalette.primaryAction)
                        .disabled(model.isInstallingHelper)
                    }
                }
            }
        }
    }

    private var schedules: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { context in
            let relevant = model.plans
                .filter { context.date < $0.effectiveEnd }
                .sorted { $0.startsAt < $1.startsAt }

            if !relevant.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Upcoming")
                        .font(.headline)

                    ForEach(Array(relevant.enumerated()), id: \.element.id) { index, plan in
                        PlanRow(
                            plan: plan,
                            now: context.date,
                            editAction: plan.isActive(at: context.date)
                                ? nil
                                : { editingPlan = plan },
                            endAction: { model.requestEnd(plan) }
                        )
                        if index < relevant.count - 1 {
                            Divider().overlay(ChatPalette.border)
                        }
                    }
                }
            }
        }
    }

    private var recurringSchedules: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Text("Schedules")
                    .font(.headline)

                if model.recurringPlans.isEmpty {
                    Text("No recurring schedules")
                        .font(supportingFont)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(model.recurringPlans.enumerated()), id: \.element.id) { index, plan in
                        RecurringPlanRow(
                            plan: plan,
                            now: context.date,
                            enabledAction: { model.setRecurringPlan(plan, enabled: $0) },
                            deleteAction: { model.deleteRecurringPlan(plan) },
                            editAction: { editingRecurringPlan = plan },
                            endAction: { model.requestEnd(plan) }
                        )
                        if index < model.recurringPlans.count - 1 {
                            Divider().overlay(ChatPalette.border)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func targetTags(for plan: BlockPlan) -> some View {
        targetTags(domains: plan.domains, applications: plan.applications)
    }

    @ViewBuilder
    private func targetTags(domains: [String], applications: [BlockedApplication]) -> some View {
        FlowLayout(spacing: 7) {
            ForEach(domains, id: \.self) { domain in
                TargetTag(text: domain, icon: "globe")
            }
            ForEach(applications) { app in
                TargetTag(text: app.displayName, icon: "app")
            }
        }
    }
}

private enum PlanPane: Hashable {
    case oneTime
    case recurring
}

private struct ActiveSessionSnapshot: Identifiable {
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

private struct ActiveSessionsRail: View {
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

private struct ActiveSessionCard: View {
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

private struct ActiveSessionDetailsView: View {
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

private enum StrengthenedSession {
    case oneTime(BlockPlan)
    case recurring(RecurringBlockPlan)
}

private struct StrengthenSessionEditor: View {
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

private struct OneTimePlanEditor: View {
    let originalPlan: BlockPlan
    let isCreating: Bool
    let onSave: (BlockPlan) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var domains: [String]
    @State private var applications: [BlockedApplication]
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var strictness: Strictness
    @State private var startsImmediately: Bool
    @State private var validationMessage: String?
    @State private var installedApplications: [InstalledApplication]

    init(
        plan: BlockPlan,
        isCreating: Bool = false,
        onSave: @escaping (BlockPlan) throws -> Void
    ) {
        originalPlan = plan
        self.isCreating = isCreating
        self.onSave = onSave
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _domains = State(initialValue: plan.domains)
        _applications = State(initialValue: plan.applications)
        _startsAt = State(initialValue: plan.startsAt)
        _endsAt = State(initialValue: plan.endsAt)
        _strictness = State(initialValue: plan.strictness)
        _startsImmediately = State(initialValue: isCreating)
        _installedApplications = State(initialValue: ApplicationCatalog.load().applications)
    }

    var body: some View {
        editorShell(
            title: isCreating ? "Set up a block" : "Edit commitment",
            subtitle: isCreating
                ? "Choose the timing, mode, websites, and applications yourself."
                : "Changes are saved only after validation."
        ) {
            GroupBox("Commitment") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...4)

                    if isCreating {
                        Toggle("Start immediately", isOn: $startsImmediately)
                    }

                    HStack(spacing: 18) {
                        if !isCreating || !startsImmediately {
                            DatePicker("Starts", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                        }
                        DatePicker("Ends", selection: $endsAt, displayedComponents: [.date, .hourAndMinute])
                    }

                    Picker("Mode", selection: $strictness) {
                        ForEach(Strictness.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(8)
            }

            ManualTargetsEditor(
                domains: $domains,
                applications: $applications,
                installedApplications: installedApplications
            )
        }
    }

    private func editorShell<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider().overlay(ChatPalette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
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
                Button(isCreating ? "Review block" : "Save changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 650, minHeight: 680)
        .background(ChatPalette.canvasTop)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDomains = DomainNormalizer.normalizeAll(domains)
        let now = Date()
        let effectiveStartsAt = isCreating && startsImmediately ? now : startsAt

        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a title."
            return
        }
        guard effectiveStartsAt >= now else {
            validationMessage = isCreating
                ? "Choose a future start or select Start immediately."
                : "An editable one-time commitment must start in the future."
            return
        }
        guard endsAt > effectiveStartsAt else {
            validationMessage = "The end time must be after the start time."
            return
        }
        guard endsAt.timeIntervalSince(effectiveStartsAt) <= 7 * 24 * 60 * 60 else {
            validationMessage = "A commitment can last at most seven days."
            return
        }
        guard !normalizedDomains.isEmpty || !applications.isEmpty else {
            validationMessage = "Add at least one website or application."
            return
        }

        let updatedPlan = BlockPlan(
            id: originalPlan.id,
            title: String(cleanTitle.prefix(80)),
            domains: normalizedDomains,
            applications: applications,
            startsAt: effectiveStartsAt,
            endsAt: endsAt,
            strictness: strictness,
            summary: String(cleanSummary.prefix(240))
        )

        do {
            try onSave(updatedPlan)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct RecurringPlanEditor: View {
    let originalPlan: RecurringBlockPlan
    let isCreating: Bool
    let onSave: (RecurringBlockPlan) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var domains: [String]
    @State private var applications: [BlockedApplication]
    @State private var weekdays: Set<Weekday>
    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var strictness: Strictness
    @State private var validationMessage: String?
    @State private var installedApplications: [InstalledApplication]

    init(
        plan: RecurringBlockPlan,
        isCreating: Bool = false,
        onSave: @escaping (RecurringBlockPlan) throws -> Void
    ) {
        originalPlan = plan
        self.isCreating = isCreating
        self.onSave = onSave
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _domains = State(initialValue: plan.domains)
        _applications = State(initialValue: plan.applications)
        _weekdays = State(initialValue: Set(plan.weekdays))
        _startTime = State(initialValue: Self.dateForTime(in: plan))
        _durationMinutes = State(initialValue: plan.durationMinutes)
        _strictness = State(initialValue: plan.strictness)
        _installedApplications = State(initialValue: ApplicationCatalog.load().applications)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCreating ? "Set up a recurring schedule" : "Edit recurring schedule")
                        .font(.title2.weight(.semibold))
                    Text(
                        isCreating
                            ? "Choose the days, time, mode, websites, and applications yourself."
                            : "An active occurrence must finish before this schedule can be changed."
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider().overlay(ChatPalette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Schedule") {
                        VStack(alignment: .leading, spacing: 13) {
                            TextField("Title", text: $title)
                            TextField("Summary", text: $summary, axis: .vertical)
                                .lineLimit(2...4)

                            Text("Days")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 7) {
                                ForEach(Weekday.ordered, id: \.rawValue) { day in
                                    Button(day.shortName) {
                                        if weekdays.contains(day) {
                                            weekdays.remove(day)
                                        } else {
                                            weekdays.insert(day)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        weekdays.contains(day) ? ChatPalette.accent : ChatPalette.surfaceRaised,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(weekdays.contains(day) ? Color.white : Color.primary)
                                }
                            }

                            HStack(spacing: 24) {
                                DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                                Stepper(value: $durationMinutes, in: 1...10_080, step: 15) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Duration").font(.caption).foregroundStyle(.secondary)
                                        Text(durationDescription).font(.callout.weight(.medium))
                                    }
                                }
                            }

                            Picker("Mode", selection: $strictness) {
                                ForEach(Strictness.allCases, id: \.self) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(8)
                    }

                    ManualTargetsEditor(
                        domains: $domains,
                        applications: $applications,
                        installedApplications: installedApplications
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
                Button(isCreating ? "Review schedule" : "Save changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(minWidth: 650, minHeight: 700)
        .background(ChatPalette.canvasTop)
    }

    private var durationDescription: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDomains = DomainNormalizer.normalizeAll(domains)

        guard !cleanTitle.isEmpty else {
            validationMessage = "Add a title."
            return
        }
        guard !weekdays.isEmpty else {
            validationMessage = "Select at least one day."
            return
        }
        guard !normalizedDomains.isEmpty || !applications.isEmpty else {
            validationMessage = "Add at least one website or application."
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: originalPlan.timeZoneIdentifier) ?? .current
        let startHour = calendar.component(.hour, from: startTime)
        let startMinute = calendar.component(.minute, from: startTime)
        let updatedPlan = RecurringBlockPlan(
            id: originalPlan.id,
            title: String(cleanTitle.prefix(80)),
            domains: normalizedDomains,
            applications: applications,
            weekdays: Weekday.ordered.filter(weekdays.contains),
            startHour: startHour,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            timeZoneIdentifier: originalPlan.timeZoneIdentifier,
            strictness: strictness,
            summary: String(cleanSummary.prefix(240)),
            createdAt: originalPlan.createdAt,
            isEnabled: originalPlan.isEnabled
        )

        guard updatedPlan.activeOccurrence(at: Date()) == nil else {
            validationMessage = "Those settings would create an occurrence already in progress. Choose another time."
            return
        }

        do {
            try onSave(updatedPlan)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private static func dateForTime(in plan: RecurringBlockPlan) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: plan.timeZoneIdentifier) ?? .current
        return calendar.date(
            bySettingHour: plan.startHour,
            minute: plan.startMinute,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}

private struct ManualTargetsEditor: View {
    @Binding var domains: [String]
    @Binding var applications: [BlockedApplication]
    let installedApplications: [InstalledApplication]
    let protectedDomains: Set<String>
    let protectedApplicationIDs: Set<String>

    @State private var domainEntry = ""
    @State private var applicationQuery = ""
    @State private var entryMessage: String?

    init(
        domains: Binding<[String]>,
        applications: Binding<[BlockedApplication]>,
        installedApplications: [InstalledApplication],
        protectedDomains: Set<String> = [],
        protectedApplicationIDs: Set<String> = []
    ) {
        _domains = domains
        _applications = applications
        self.installedApplications = installedApplications
        self.protectedDomains = protectedDomains
        self.protectedApplicationIDs = protectedApplicationIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Websites") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Add a website, e.g. example.com", text: $domainEntry)
                            .onSubmit(addDomain)
                        Button("Add", action: addDomain)
                            .disabled(domainEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if domains.isEmpty {
                        Text("No websites in this block.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(domains, id: \.self) { domain in
                            HStack {
                                Label(domain, systemImage: "globe")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                if protectedDomains.contains(domain) {
                                    Label("Current", systemImage: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button {
                                        domains.removeAll { $0 == domain }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .help("Remove \(domain)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Applications") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search installed applications", text: $applicationQuery)

                    if !applicationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if applicationMatches.isEmpty {
                            Text("No unselected installed app matches that search.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(applicationMatches, id: \.bundleIdentifier) { application in
                                    Button {
                                        addApplication(application)
                                    } label: {
                                        HStack {
                                            Label(application.displayName, systemImage: "app")
                                            Spacer()
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(ChatPalette.accent)
                                        }
                                        .contentShape(Rectangle())
                                        .padding(.vertical, 7)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .background(ChatPalette.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(ChatPalette.border, lineWidth: 1)
                            }
                        }
                    }

                    if applications.isEmpty {
                        Text("No applications in this block.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(applications) { application in
                            HStack {
                                Label(application.displayName, systemImage: "app")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                if protectedApplicationIDs.contains(application.bundleIdentifier) {
                                    Label("Current", systemImage: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button {
                                        applications.removeAll { $0.id == application.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .help("Remove \(application.displayName)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(8)
            }

            if let entryMessage {
                Label(entryMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(ChatPalette.warning)
            }
        }
    }

    private var applicationMatches: [InstalledApplication] {
        let query = applicationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let selectedIDs = Set(applications.map(\.bundleIdentifier))
        return Array(
            installedApplications
                .filter {
                    !selectedIDs.contains($0.bundleIdentifier)
                        && $0.displayName.localizedCaseInsensitiveContains(query)
                }
                .prefix(8)
        )
    }

    private func addDomain() {
        guard let domain = DomainNormalizer.normalize(domainEntry) else {
            entryMessage = "Enter a valid website domain, such as example.com."
            return
        }
        if !domains.contains(domain) {
            domains.append(domain)
            domains.sort()
        }
        domainEntry = ""
        entryMessage = nil
    }

    private func addApplication(_ application: InstalledApplication) {
        guard !applications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            applicationQuery = ""
            return
        }
        applications.append(
            BlockedApplication(
                displayName: application.displayName,
                bundleIdentifier: application.bundleIdentifier,
                executableName: application.executableName,
                bundleName: application.bundleName
            )
        )
        applications.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        applicationQuery = ""
        entryMessage = nil
    }
}

private struct RecurringPlanRow: View {
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
                    Text(plan.title).font(.headline)
                    StrictnessBadge(strictness: plan.strictness)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(plan.daysDescription)
                    .font(.caption.weight(.semibold))
                Text("\(plan.startTimeDescription) · \(plan.durationDescription)")
                    .font(.caption)
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

private struct PlanRow: View {
    let plan: BlockPlan
    let now: Date
    let editAction: (() -> Void)?
    let endAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlanStatusIcon()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(plan.title).font(.headline)
                    StrictnessBadge(strictness: plan.strictness)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(plan.domains.count + plan.applications.count) targets")
                .font(.caption)
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

private struct PlanStatusIcon: View {
    var body: some View {
        Image(systemName: "shield.lefthalf.filled")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ChatPalette.accent)
            .frame(width: 22, height: 28)
    }
}

private struct UnlockControl: View {
    let plan: BlockPlan
    let now: Date
    let action: () -> Void
    @State private var confirmsEmergencyUnlock = false

    var body: some View {
        if plan.isActive(at: now) {
            if plan.endRequestedAt != nil {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Label("Unlocking in \(remainingDescription(at: context.date))", systemImage: "hourglass")
                        .font(.caption.weight(.semibold))
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

private extension RecurringBlockPlan {
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

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apiKey = ""
    @State private var modelName = ModelSettings.current()
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API key", text: $apiKey)
                TextField("Model", text: $modelName)
                Text("FocusGuard defaults to gpt-5.6-terra with medium reasoning. You can enter another Responses API model here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The key is stored in this Mac user's Keychain and is sent only to api.openai.com. Use a newly created project key—not one previously pasted into a chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Background reliability") {
                Toggle(
                    "Launch FocusGuard at login",
                    isOn: Binding(
                        get: { model.launchAtLoginDesired },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                Text(model.loginItemStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.loginItemState == .requiresApproval || model.loginItemState == .unavailable {
                    Button("Open Login Items settings") {
                        model.openLoginItemSettings()
                    }
                }

                LabeledContent("Privileged helper", value: model.helperStatusText)
                if let helperHealthDetails = model.helperHealthDetails {
                    Text(helperHealthDetails)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.helperState.needsRepair {
                    Button(model.isInstallingHelper ? "Setting up helper…" : model.helperActionTitle) {
                        model.installHelper()
                    }
                    .disabled(model.isInstallingHelper)
                }
                if !model.backgroundStatusMessage.isEmpty {
                    Text(model.backgroundStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recurring warnings") {
                Toggle(
                    "Warn 5 minutes before recurring blocks",
                    isOn: Binding(
                        get: { model.recurringWarningsEnabled },
                        set: { model.setRecurringWarningsEnabled($0) }
                    )
                )
                Text(model.recurringWarningStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser landing pages") {
                Text("Click Export and show extension first. Then, in Chrome, Brave, or Edge, enable Developer mode on the Extensions page, choose Load unpacked, and select the Finder folder that opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("~/Library/Application Support/FocusGuard/BrowserExtension")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)

                HStack {
                    Label("Local only · no browsing data leaves this Mac", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Export and show extension") { revealBrowserExtension() }
                }
            }

            HStack {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(ChatPalette.primaryAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 620)
        .preferredColorScheme(.light)
        .onAppear {
            do {
                apiKey = try APIKeyStore.read() ?? ""
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            try APIKeyStore.save(apiKey)
            ModelSettings.save(modelName)
            modelName = ModelSettings.current()
            statusMessage = "Saved to this Mac"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func revealBrowserExtension() {
        do {
            let extensionURL = try BrowserExtensionExporter.export()
            guard NSWorkspace.shared.open(extensionURL) else {
                statusMessage = "The extension was exported, but Finder did not open."
                return
            }
            statusMessage = "Extension exported to Application Support and opened in Finder"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct UndoActivationBar: View {
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

private struct GlassCard<Content: View>: View {
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

private struct StrictnessBadge: View {
    let strictness: Strictness

    var body: some View {
        Text(strictness.displayName.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
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

private struct StrictnessMenu: View {
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

private extension Strictness {
    var systemImage: String {
        switch self {
        case .flexible: "lock.open"
        case .focused: "timer"
        case .locked: "lock.fill"
        }
    }
}

private struct TargetTag: View {
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

private struct InterpretationNote: View {
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

private struct ApplicationClosingNotice: View {
    var body: some View {
        Label(
            "Blocked apps are force-closed immediately. Save open work before activating.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(ChatPalette.warning)
    }
}

private struct DetailLabel: View {
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

private struct FlowLayout: Layout {
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
