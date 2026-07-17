import AppKit
import SwiftUI

/// Applies the small amount of AppKit window styling that SwiftUI's
/// `hiddenTitleBar` window style does not expose. In particular, AppKit can
/// otherwise leave a tinted titlebar strip and separator above full-size
/// SwiftUI content.
struct WindowAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowAppearanceView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowAppearanceView)?.configureWindow()
    }
}

private final class WindowAppearanceView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }

        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .white
        window.toolbar?.showsBaselineSeparator = false
    }
}
