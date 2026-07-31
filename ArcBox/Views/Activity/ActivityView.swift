import ArcBoxClient
import SwiftUI

/// Live resource monitor for the System VM, backed by the daemon's
/// `StatsService` stream via `ActivityViewModel`.
///
/// The machine-wide metrics float in the Liquid Glass layer while the
/// per-container table scrolls beneath them, so the numbers you are comparing
/// against stay on screen while you scan containers.
struct ActivityView: View {
    @Environment(ActivityViewModel.self) private var vm
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(\.arcboxClient) private var arcboxClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText = ""

    var body: some View {
        content
            .searchable(text: $searchText, placement: .toolbar, prompt: "Filter Containers")
            // Keyed on the arrival of data, not on the data: the screen
            // materialises once, and the 1 Hz samples inside it do not drag the
            // whole hierarchy through a transition every second.
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: vm.current == nil)
            .navigationTitle("Activity")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .status) {
                    StreamStatusPill(phase: vm.phase)
                }
            }
            // Re-key on the client's identity so the stream (re)starts when the
            // client first becomes available or is swapped.
            .task(id: arcboxClient.map(ObjectIdentifier.init)) {
                guard let client = arcboxClient else { return }
                await vm.run(client: client)
            }
    }

    /// Rates come from deltas, so the first usable frame is two samples in — a
    /// second or two at the daemon's 1 Hz cadence. Rather than hold the screen
    /// back behind a spinner for that, the real layout goes up immediately and
    /// carries redacted values until the numbers are real. Nothing false is
    /// shown, nothing moves when the data lands, and there is no separate
    /// loading screen to perceive.
    @ViewBuilder
    private var content: some View {
        if streamHasGivenUp {
            unavailable
        } else {
            ActivityContainerTable(
                containers: vm.current?.containers ?? [],
                docker: dockerContainers,
                searchText: searchText,
                // "No containers" is a finding; before the first frame it would
                // be a guess.
                hasLoaded: vm.current != nil
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                ActivityMetricStrip(
                    stats: vm.current,
                    cpuHistory: vm.cpuHistory,
                    memoryHistory: vm.memoryHistory,
                    networkHistory: vm.networkHistory
                )
                // Only the strip redacts. The table's column headers are known
                // labels, not pending data, and `TableColumn` gives no handle
                // to exempt them — an empty table under live headers already
                // reads as rows on the way.
                .redacted(reason: vm.current == nil ? .placeholder : [])
            }
            .softScrollEdge(for: .top)
        }
    }

    /// A stream that keeps failing before its first sample is not loading, and
    /// must stop looking like it.
    private var streamHasGivenUp: Bool {
        guard vm.current == nil, case .reconnecting(let attempt) = vm.phase else { return false }
        return attempt >= 3
    }

    /// Docker's view of the containers the stats stream reports, keyed by ID.
    /// The two sources are independent, so this is a join, not a lookup: an ID
    /// the Engine has not reported simply contributes nothing.
    private var dockerContainers: [String: ActivityContainerFacts] {
        Dictionary(
            containersVM.containers.map {
                ($0.id, ActivityContainerFacts(project: $0.composeProject, image: $0.image))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The machine's shape, once known — the toolbar's own line for the
    /// constants the tiles would otherwise have to repeat.
    private var subtitle: String {
        guard let stats = vm.current else { return "System VM" }
        return
            "System VM · \(stats.onlineCPUs) cores · \(StatsFormat.bytes(stats.memoryTotalBytes)) · up \(StatsFormat.uptime(stats.uptime))"
    }

    @ViewBuilder
    private var unavailable: some View {
        ContentUnavailableView {
            Label("Stats Unavailable", systemImage: "waveform.path.ecg")
        } description: {
            if case .reconnecting(let attempt) = vm.phase {
                Text("The daemon's stats stream keeps dropping. Retrying — attempt \(attempt).")
            }
        }
    }
}

// MARK: - Status

/// Stream health, in the toolbar's status slot: absent while connecting, quiet
/// once live, and loud only when the data on screen has gone stale.
private struct StreamStatusPill: View {
    let phase: ActivityViewModel.StreamPhase

    var body: some View {
        if let (color, label) = descriptor {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var descriptor: (Color, LocalizedStringKey)? {
        switch phase {
        case .live: (AppColors.running, "Live")
        // Charts keep showing the last data; the pill tells the user it is
        // stale while the stream reconnects.
        case .reconnecting: (AppColors.warning, "Reconnecting")
        case .connecting: nil
        }
    }
}
