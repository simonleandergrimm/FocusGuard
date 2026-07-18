import AppKit
import FocusGuardCore
import SwiftUI

struct ContentView: View {
    private static let claudeFMURL = URL(string: "https://www.youtube.com/watch?v=tRsQsTMvPNg")!

    @ObservedObject var model: AppModel
    @ObservedObject var pomodoro: PomodoroTimerModel
    @Binding var interfaceZoom: Double
    @Environment(\.openSettings) private var openSettings
    @State private var selectedPane: PlanPane = .oneTime
    @State private var editingPlan: BlockPlan?
    @State private var editingRecurringPlan: RecurringBlockPlan?
    @State private var creatingPlan: BlockPlan?
    @State private var creatingRecurringPlan: RecurringBlockPlan?
    @State private var showingStatistics = false
    @AppStorage("sidebarVisible") private var sidebarVisible = true

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
        InterfaceTypography.body
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
        .font(InterfaceTypography.body)
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
        .sheet(isPresented: $showingStatistics) {
            StatisticsView()
        }
    }

    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ZStack(alignment: .topLeading) {
                VStack(alignment: .center, spacing: 24) {
                    reflectionHeader(fontSize: 30, centered: true)
                        .padding(.top, 14 * zoomScale)
                    contentScrollView
                }
                .padding(.horizontal, 36 * zoomScale)
                .padding(.top, 30 * zoomScale)
                .padding(.bottom, 22 * zoomScale)
                .frame(maxWidth: 1_020, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)

                sidebarToggleButton
                    .padding(.leading, 18 * zoomScale)
                    .padding(.top, 18 * zoomScale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.snappy, value: sidebarVisible)
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(alignment: .top, spacing: 18) {
                if sidebarVisible {
                    ActiveSessionsRail(model: model)
                        .frame(width: 238 * zoomScale)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                contentScrollView
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(30 * zoomScale)
        .frame(maxWidth: 1_200, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: sidebarVisible)
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
                showingStatistics = true
            } label: {
                Label("Statistics", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(ChatPalette.surfaceRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))

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
        .font(InterfaceTypography.body)
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
            sidebarToggleButton

            reflectionHeader(fontSize: 28)

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

    private func reflectionHeader(fontSize: CGFloat, centered: Bool = false) -> some View {
        Text("What do you want to do,\non reflection?")
            .font(.system(size: fontSize * zoomScale, weight: .semibold, design: .rounded))
            .tracking(-0.8)
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.snappy) {
                sidebarVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(InterfaceTypography.emphasized)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ChatPalette.surfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .help(sidebarVisible ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)")
        .accessibilityLabel(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
    }

    @ViewBuilder
    private var helperBadge: some View {
        if model.helperState.needsRepair || model.isInstallingHelper || model.helperHealthUnreachable {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(InterfaceTypography.metadata)
                    .foregroundStyle(ChatPalette.warning)
                Text(helperBadgeText)
                    .font(InterfaceTypography.emphasized)

                Image(systemName: "info.circle")
                    .font(InterfaceTypography.metadata)
                    .foregroundStyle(.secondary)
                    .help(helperRecoveryHelp)

                if model.helperState.needsRepair || model.isInstallingHelper {
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
        if model.helperHealthUnreachable {
            return "The helper is running, but FocusGuard cannot reach its local status service on port 8765. Quit any app using that port; FocusGuard will check again automatically."
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

    private var helperBadgeText: String {
        if model.isInstallingHelper { return "Helper setup in progress" }
        if model.helperHealthUnreachable { return "Helper connection needs attention" }
        return model.helperState.description
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
                    Button("Edit") { creatingPlan = plan }
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
                    Button("Edit") { creatingRecurringPlan = plan }
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
