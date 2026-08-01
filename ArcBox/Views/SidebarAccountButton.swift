import ArcBoxAuth
import SwiftUI

/// Account chip pinned to the bottom of the main-window sidebar.
struct SidebarAccountButton: View {
    @Environment(AuthSession.self) private var authSession
    @State private var isHovered = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if authSession.status == .signingIn {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                    Text("Signing In…")
                        .foregroundStyle(.secondary)
                } else {
                    AvatarView(url: authSession.identity?.avatarURL, size: 24)
                    Text(title)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 6)
        )
        .onHover { isHovered = $0 }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(isDisabled)
        .help(helpText)
        .accessibilityLabel(title)
        .accessibilityHint(helpText)
    }

    private var title: String {
        authSession.status == .signedIn
            ? authSession.identity?.displayName ?? "Account"
            : "Sign In"
    }

    private var isDisabled: Bool {
        authSession.status == .signingIn
            || (authSession.status != .signedIn && authSession.configuration.isPlaceholder)
    }

    private var helpText: String {
        switch authSession.status {
        case .signedIn:
            "Open account settings"
        case .signingIn:
            "Signing in to ArcBox"
        case .error(let message):
            "Sign-in failed: \(message)"
        case .signedOut:
            authSession.configuration.isPlaceholder
                ? "No OIDC provider is configured"
                : "Sign in to ArcBox"
        }
    }
}
