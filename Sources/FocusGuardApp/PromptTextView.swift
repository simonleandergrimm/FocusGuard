import AppKit
import SwiftUI

struct PromptTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let onCommandEnter: () -> Void
    let onFocusChange: (Bool) -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat = 16,
        onCommandEnter: @escaping () -> Void = {},
        onFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        _text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.onCommandEnter = onCommandEnter
        self.onFocusChange = onFocusChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onCommandEnter: onCommandEnter,
            onFocusChange: onFocusChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PromptScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.onCommandEnter = context.coordinator.onCommandEnter
        textView.onFocusChange = context.coordinator.onFocusChange

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        context.coordinator.onCommandEnter = onCommandEnter
        context.coordinator.onFocusChange = onFocusChange
        textView.onCommandEnter = context.coordinator.onCommandEnter
        textView.onFocusChange = context.coordinator.onFocusChange
        textView.placeholder = placeholder
        if textView.font?.pointSize != fontSize {
            textView.font = .systemFont(ofSize: fontSize)
        }
        if textView.string != text {
            textView.string = text
        }
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        var onCommandEnter: () -> Void
        var onFocusChange: (Bool) -> Void

        init(
            text: Binding<String>,
            onCommandEnter: @escaping () -> Void,
            onFocusChange: @escaping (Bool) -> Void
        ) {
            _text = text
            self.onCommandEnter = onCommandEnter
            self.onFocusChange = onFocusChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PlaceholderTextView else { return }
            text = textView.string
            textView.needsDisplay = true
        }
    }
}

private final class PromptScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let previousOrigin = contentView.bounds.origin
        super.scrollWheel(with: event)

        let newOrigin = contentView.bounds.origin
        let movedVertically = abs(newOrigin.y - previousOrigin.y) > 0.5
        guard !movedVertically, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }

        var ancestor = superview
        while let view = ancestor {
            if let outerScrollView = view as? NSScrollView {
                outerScrollView.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
    }
}

private final class PlaceholderTextView: NSTextView {
    var onCommandEnter: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        let commandModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if commandModifiers == .command, event.keyCode == 36 || event.keyCode == 76 {
            onCommandEnter?()
            return
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFocusChange?(true)
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder {
            onFocusChange?(false)
        }
        return resignedFirstResponder
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.72),
        ]
        placeholder.draw(at: textContainerOrigin, withAttributes: attributes)
    }
}
