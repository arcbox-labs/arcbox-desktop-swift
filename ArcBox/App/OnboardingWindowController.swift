import AppKit

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let windowSize = NSSize(width: 760, height: 600)

    private let onClose: () -> Void

    init(contentViewController: NSViewController, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ArcBox"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setFrame(NSRect(origin: .zero, size: Self.windowSize), display: false)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose()
        return false
    }
}
