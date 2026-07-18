import FocusGuardCore
import SwiftUI

/// Shows the enforcement counters the helper accumulates in stats.json:
/// how often blocked sites were visited and how often blocked applications
/// were force-closed.
struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var statistics: BlockStatistics?
    @State private var loadFailed = false

    private static let maximumRows = 10

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocking statistics")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider().overlay(ChatPalette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let statistics, !statistics.websiteHits.isEmpty || !statistics.applicationTerminations.isEmpty {
                        if !statistics.websiteHits.isEmpty {
                            countSection(
                                title: "Blocked site visits",
                                icon: "globe",
                                counts: statistics.websiteHits
                            )
                        }
                        if !statistics.applicationTerminations.isEmpty {
                            countSection(
                                title: "Applications closed",
                                icon: "xmark.app",
                                counts: statistics.applicationTerminations
                            )
                        }
                    } else {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(ChatPalette.border)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
        }
        .frame(width: 480, height: 520)
        .background(ChatPalette.canvasTop)
        .task {
            do {
                statistics = try BlockStatisticsStore(
                    fileURL: BlockStatisticsStore.defaultFileURL()
                ).load()
            } catch {
                loadFailed = true
            }
        }
    }

    private var subtitle: String {
        guard let statistics else {
            return "Counted by the background helper while blocks are enforced."
        }
        return "Counted since \(statistics.since.formatted(date: .abbreviated, time: .omitted))."
    }

    private var emptyMessage: String {
        if loadFailed {
            return "The statistics file could not be read."
        }
        return "Nothing counted yet. Visits to blocked sites and force-closed applications appear here once a block is active."
    }

    private func countSection(title: String, icon: String, counts: [String: Int]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(topEntries(from: counts), id: \.key) { entry in
                    HStack {
                        Text(entry.key)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(entry.value)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if counts.count > Self.maximumRows {
                    Text("Top \(Self.maximumRows) of \(counts.count) shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func topEntries(from counts: [String: Int]) -> [(key: String, value: Int)] {
        Array(
            counts.sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(Self.maximumRows)
        )
    }
}
