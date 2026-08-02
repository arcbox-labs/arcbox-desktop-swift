import AppKit
import ArcBoxClient
import SwiftUI

enum OnboardingStep: Hashable {
    case welcome
    case permission
    case setup
}

struct OnboardingView: View {
    let orchestrator: StartupOrchestrator
    let isReplay: Bool
    let onStart: () -> Void
    let onComplete: () -> Void
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var step: OnboardingStep
    @State private var movingForward = true

    init(
        orchestrator: StartupOrchestrator,
        initialStep: OnboardingStep,
        isReplay: Bool = false,
        onStart: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.orchestrator = orchestrator
        self.isReplay = isReplay
        self.onStart = onStart
        self.onComplete = onComplete
        self.onQuit = onQuit
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 72)
            .padding(.top, 44)
            .padding(.bottom, 24)

            Divider()

            footer
                .frame(height: 64)
                .padding(.horizontal, 24)
        }
        .frame(
            width: OnboardingWindowController.windowSize.width,
            height: OnboardingWindowController.windowSize.height
        )
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            welcomePage
        case .permission:
            permissionPage
        case .setup:
            setupPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to ArcBox")
                    .font(.system(size: 28, weight: .semibold))

                Text("Disposable Linux environments, ready in seconds.")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
            }

            sandboxCard
                .padding(.top, 4)
        }
        .frame(maxWidth: 536)
        .accessibilityElement(children: .contain)
    }

    private var sandboxCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.iconBackground)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sandboxes")
                        .font(.system(size: 18, weight: .semibold))
                    Text(
                        "Create isolated environments, then inspect and control them without leaving ArcBox."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 18) {
                featureLabel("Terminal", symbol: "terminal")
                featureLabel("Files", symbol: "folder")
                featureLabel("Ports", symbol: "network")
                featureLabel("Snapshots", symbol: "clock.arrow.circlepath")
                featureLabel("Events", symbol: "list.bullet.rectangle")
            }
        }
        .padding(20)
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var permissionPage: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 50, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(
                    isReplay
                        ? "Why ArcBox may ask for administrator access"
                        : "Allow ArcBox to finish system setup"
                )
                .font(.system(size: 24, weight: .semibold))

                Text(
                    "ArcBox and its runtime normally run as your user. "
                        + "When system integration needs installing or updating, macOS may ask "
                        + "you to approve a small privileged helper."
                )
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                PermissionRow(
                    symbol: "network",
                    title: "Container networking and local names",
                    detail: "Adds routes and resolves *.arcbox.local addresses."
                )
                PermissionRow(
                    symbol: "terminal",
                    title: "Docker and command-line integration",
                    detail: "Provides the standard Docker socket and ArcBox CLI tools."
                )

                Divider()

                Label {
                    Text("Your password stays with macOS. ArcBox never sees, stores, or sends it.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                } icon: {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(AppColors.running)
                }
            }
            .padding(20)
            .background(cardBackground)
            .overlay(cardBorder)

            Text(
                "You may be asked again when the helper receives a security or compatibility update."
            )
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textMuted)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 536)
    }

    @ViewBuilder
    private var setupPage: some View {
        if orchestrator.isReady {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.running)
                    .accessibilityHidden(true)

                Text("ArcBox is ready")
                    .font(.system(size: 24, weight: .semibold))

                Text("Your Sandboxes and system integrations are ready to use.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Setting up ArcBox")
                        .font(.system(size: 24, weight: .semibold))
                    Text("This usually takes less than a minute.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                }

                StartupProgressView(
                    orchestrator: orchestrator,
                    allowingAdministratorPrompt: true
                )
                .frame(width: 420, height: 190)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch step {
            case .welcome:
                Spacer()
                primaryButton("Continue") {
                    move(to: .permission, forward: true)
                }
            case .permission:
                Button("Back") {
                    move(to: .welcome, forward: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isReplay {
                    primaryButton("Done", action: onComplete)
                } else {
                    primaryButton("Continue to macOS") {
                        move(to: .setup, forward: true)
                        onStart()
                    }
                }
            case .setup:
                if orchestrator.isReady {
                    Spacer()
                    primaryButton("Open ArcBox", action: onComplete)
                } else {
                    Button("Quit ArcBox", action: onQuit)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Spacer()
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppColors.surfaceCard)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(AppColors.borderSubtle, lineWidth: 1)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: movingForward ? 12 : -12).combined(with: .opacity),
            removal: .offset(x: movingForward ? -12 : 12).combined(with: .opacity)
        )
    }

    private func featureLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12))
            .foregroundStyle(AppColors.textSecondary)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minWidth: 132)
            .keyboardShortcut(.defaultAction)
    }

    private func move(to destination: OnboardingStep, forward: Bool) {
        movingForward = forward
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.2)) {
            step = destination
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
