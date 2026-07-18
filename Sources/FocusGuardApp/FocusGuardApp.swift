import Darwin
import SwiftUI

@main
struct FocusGuardApp: App {
    static let mainWindowID = "main"

    private static let defaultInterfaceZoom = 1.15
    private static let minimumInterfaceZoom = 0.8
    private static let maximumInterfaceZoom = 1.6

    @StateObject private var model: AppModel
    @StateObject private var pomodoro: PomodoroTimerModel
    @AppStorage("interfaceZoom") private var interfaceZoom = Self.defaultInterfaceZoom
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @AppStorage("showMenuBarStatus") private var showMenuBarStatus = true

    init() {
        guard AppInstanceCoordinator.shouldContinueLaunching() else {
            Darwin.exit(EXIT_SUCCESS)
        }
        _model = StateObject(wrappedValue: AppModel())
        _pomodoro = StateObject(wrappedValue: PomodoroTimerModel())
    }

    var body: some Scene {
        Window("FocusGuard", id: Self.mainWindowID) {
            ContentView(model: model, pomodoro: pomodoro, interfaceZoom: $interfaceZoom)
                .frame(minWidth: 820, minHeight: 650)
                .background(WindowAppearanceConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_120, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    sidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()
                Button("Zoom In") {
                    interfaceZoom = min(Self.maximumInterfaceZoom, interfaceZoom + 0.1)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(interfaceZoom >= Self.maximumInterfaceZoom)

                Button("Zoom Out") {
                    interfaceZoom = max(Self.minimumInterfaceZoom, interfaceZoom - 0.1)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(interfaceZoom <= Self.minimumInterfaceZoom)

                Button("Default Size") {
                    interfaceZoom = Self.defaultInterfaceZoom
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(abs(interfaceZoom - Self.defaultInterfaceZoom) < 0.001)
            }
        }

        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra(isInserted: $showMenuBarStatus) {
            MenuBarStatusView(timer: pomodoro)
        } label: {
            MenuBarStatusLabel(timer: pomodoro)
        }
        .menuBarExtraStyle(.window)
    }
}
