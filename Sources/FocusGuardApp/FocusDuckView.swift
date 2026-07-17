import SwiftUI

struct FocusDuckView: View {
    private static let phrases = [
        "Time to work.",
        "Keep going.",
        "Nice work."
    ]

    private static let duck = """
       __
     <(° )___
      (  ._>
       `--'
    """

    @State private var phraseIndex = 0
    @State private var recentClicks: [Date] = []
    @State private var message: String?
    @State private var messageID = 0

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let message {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(ChatPalette.surface, in: Capsule())
                    .overlay {
                        Capsule().stroke(ChatPalette.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
            }

            Button(action: speak) {
                Text(Self.duck)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(-2)
                    .foregroundStyle(ChatPalette.primaryAction)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("A small word from the FocusGuard duck")
            .accessibilityLabel("FocusGuard duck")
            .accessibilityHint("Shows a short focus prompt")
        }
        .animation(.snappy(duration: 0.2), value: message)
        .task(id: messageID) {
            guard message != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation {
                message = nil
            }
        }
    }

    private func speak() {
        let now = Date()
        recentClicks = recentClicks.filter { now.timeIntervalSince($0) < 5 }
        recentClicks.append(now)

        if recentClicks.count >= 4 {
            message = "..."
        } else {
            message = Self.phrases[phraseIndex % Self.phrases.count]
            phraseIndex += 1
        }
        messageID += 1
    }
}
