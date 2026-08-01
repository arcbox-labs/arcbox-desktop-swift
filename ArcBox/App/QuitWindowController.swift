import AppKit
import SwiftUI

@MainActor
final class QuitWindowController: NSWindowController {
    static let cardSize = NSSize(width: 320, height: 148)

    init(screen: NSScreen? = NSScreen.main) {
        let window = QuitWindow(
            contentRect: NSRect(origin: .zero, size: Self.cardSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.title = "Quitting ArcBox"
        window.contentViewController = NSHostingController(rootView: QuitCardView())
        window.setContentSize(Self.cardSize)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .modalPanel
        window.isMovable = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.animationBehavior = .none
        if let screen {
            let visibleFrame = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - Self.cardSize.width / 2,
                    y: visibleFrame.midY - Self.cardSize.height / 2
                ))
        } else {
            window.center()
        }

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.orderFrontRegardless()
    }
}

private final class QuitWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct QuitCardView: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("Quitting ArcBox")
                    .font(.system(size: 15, weight: .semibold))
                Text("Stopping services and finishing up safely…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(cornerRadius: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quitting ArcBox. Stopping services and finishing up safely.")
    }
}
