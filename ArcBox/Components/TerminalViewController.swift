import AppKit
import SwiftTerm

@MainActor
final class TerminalViewController: NSViewController {
    let terminalView: TerminalView

    private let terminalDelegate: any TerminalViewDelegate
    private var didFocus = false

    init(delegate: any TerminalViewDelegate, theme: String = "system") {
        terminalDelegate = delegate
        terminalView = TerminalView(frame: .zero)
        super.init(nibName: nil, bundle: nil)

        terminalView.terminalDelegate = terminalDelegate
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.setAccessibilityElement(true)
        terminalView.setAccessibilityRole(.textArea)
        terminalView.setAccessibilityLabel("Terminal")
        update(theme: theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = terminalView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didFocus, let window = terminalView.window else { return }
        didFocus = window.makeFirstResponder(terminalView)
    }

    func update(theme: String) {
        TerminalAppearance.configure(terminalView, theme: theme)
    }
}
