import SwiftTerm
import SwiftUI

/// Temporary SwiftUI adapter for the AppKit terminal controller.
struct SwiftTermView: NSViewControllerRepresentable {
    let delegate: any TerminalViewDelegate
    let onTerminalCreated: (TerminalView) -> Void
    var theme: String = "system"

    @Environment(\.colorScheme) private var colorScheme

    func makeNSViewController(context _: Context) -> TerminalViewController {
        let controller = TerminalViewController(delegate: delegate, theme: theme)
        onTerminalCreated(controller.terminalView)
        return controller
    }

    func updateNSViewController(
        _ nsViewController: TerminalViewController,
        context _: Context
    ) {
        _ = colorScheme
        nsViewController.update(theme: theme)
    }
}
