import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    static let frameAutosaveName = "main"
    static let defaultFrameSize = NSSize(width: 1_200, height: 800)

    init(
        contentViewController: NSViewController,
        frameAutosaveName: String = MainWindowController.frameAutosaveName
    ) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ArcBox"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false
        window.setFrame(
            NSRect(origin: .zero, size: Self.defaultFrameSize),
            display: false
        )

        super.init(window: window)

        if !window.setFrameUsingName(frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(frameAutosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func replaceContentViewController(_ viewController: NSViewController) {
        window?.contentViewController = viewController
    }
}
