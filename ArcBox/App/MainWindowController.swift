import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    private static let frameAutosaveName = "ArcBox.MainWindow"

    init(contentViewController: NSViewController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ArcBox"
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false

        super.init(window: window)

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func replaceContentViewController(_ viewController: NSViewController) {
        window?.contentViewController = viewController
    }
}
