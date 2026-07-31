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
    @Environment(\.arcboxClient) private var arcboxClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
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

    @ViewBuilder
    private var content: some View {
        if let stats = vm.current {
            ActivityContainerTable(containers: stats.containers)
                .overlay {
                    if stats.containers.isEmpty {
                        ContentUnavailableView(
                            "No Running Containers",
                            systemImage: "cube",
                            description: Text("Per-container usage appears here while containers are running.")
                        )
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    ActivityMetricStrip(
                        stats: stats,
                        cpuHistory: vm.cpuHistory,
                        memoryHistory: vm.memoryHistory,
                        networkHistory: vm.networkHistory
                    )
                }
                .softScrollEdge(for: .top)
        } else {
            waitingForData
        }
    }

    /// The machine's shape, once known — the toolbar's own line for the
    /// constants the tiles would otherwise have to repeat.
    private var subtitle: String {
        guard let stats = vm.current else { return "System VM" }
        return "System VM · \(stats.onlineCPUs) cores · \(StatsFormat.bytes(stats.memoryTotalBytes))"
    }

    /// Distinguishes a first connection from a stream that keeps failing before
    /// its first sample, so a persistent error stops looking like a spinner
    /// that will resolve on its own.
    @ViewBuilder
    private var waitingForData: some View {
        if case .reconnecting(let attempt) = vm.phase, attempt >= 3 {
            ContentUnavailableView {
                Label("Stats Unavailable", systemImage: "waveform.path.ecg")
            } description: {
                Text("The daemon's stats stream keeps dropping. Retrying — attempt \(attempt).")
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Waiting for the first sample…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
