import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    static let frameAutosaveName = "settings"

    init(
        contentViewController: NSViewController,
        screen: NSScreen? = nil,
        frameAutosaveName: String = SettingsWindowController.frameAutosaveName
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false

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
