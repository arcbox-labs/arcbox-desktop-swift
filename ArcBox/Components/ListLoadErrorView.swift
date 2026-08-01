import SwiftUI

/// Error state shown when an initial list fetch fails.
struct ListLoadErrorView: View {
    let title: String
    let message: String
    let onRetry: () -> Void

    var body: some View {
        EmptyStateView(icon: "exclamationmark.triangle", title: title) {
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
        }
    }
}
