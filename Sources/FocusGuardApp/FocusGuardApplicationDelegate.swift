import AppKit

@MainActor
final class FocusGuardApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let mainWindow = sender.windows.first(where: Self.isMainWindow) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.title == "FocusGuard"
            || window.identifier?.rawValue.localizedCaseInsensitiveContains("main") == true
    }
}
