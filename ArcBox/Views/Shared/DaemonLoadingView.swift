import ArcBoxClient
import SwiftUI

/// Loading indicator shown while the arcbox daemon is starting or stopping.
struct DaemonLoadingView: View {
    let state: DaemonState

    @Environment(\.startupOrchestrator) private var orchestrator

    @ViewBuilder
    var body: some View {
        switch state {
        case .error(let message):
            unavailable(
                title: "ArcBox Daemon Unavailable",
                message: message,
                actionTitle: "Retry"
            )
        case .stopped:
            unavailable(
                title: "ArcBox Daemon Is Stopped",
                message: "Start the daemon to use ArcBox resources.",
                actionTitle: "Start"
            )
        case .starting:
            progress("Starting ArcBox Daemon…")
        case .registered:
            progress("Connecting to ArcBox Daemon…")
        case .stopping:
            progress("Stopping ArcBox Daemon…")
        case .running:
            EmptyView()
        }
    }

    private func progress(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func unavailable(
        title: LocalizedStringKey,
        message: String,
        actionTitle: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let orchestrator {
                Button(actionTitle) {
                    Task { await orchestrator.retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
