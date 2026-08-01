import AppKit

/// Tracks the currently visible "Coming Soon" panel so we don't create duplicates.
/// Strong ref: we manage the lifecycle ourselves since isReleasedWhenClosed is off.
private var currentPanel: NSPanel?

/// Shows a floating "Coming Soon" panel centered on screen.
/// Re-focuses the existing panel if one is already visible.
@MainActor
func showComingSoonPanel() {
    if let existing = currentPanel {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let panel = ComingSoonPanel(
        contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.hidesOnDeactivate = true
    panel.center()

    panel.contentViewController = ComingSoonViewController()
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    currentPanel = panel
}

// MARK: - Panel subclass for Esc key support

private final class ComingSoonPanel: NSPanel {
    override func close() {
        super.close()
        if currentPanel === self {
            currentPanel = nil
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private final class ComingSoonViewController: NSViewController {
    private lazy var okButton: NSButton = {
        let button = NSButton(title: "OK", target: self, action: #selector(dismissPanel))
        button.bezelColor = .controlAccentColor
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.contentTintColor = .white
        button.keyEquivalent = "\r"
        button.setAccessibilityHelp("Close the Coming Soon panel")
        return button
    }()

    override func loadView() {
        let background = NSVisualEffectView()
        background.blendingMode = .behindWindow
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(true)
        icon.setAccessibilityRole(.image)
        icon.setAccessibilityLabel("ArcBox application icon")
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),
        ])

        let title = NSTextField(labelWithString: "Coming Soon!")
        title.alignment = .center
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let stack = NSStackView(views: [icon, title, okButton])
        stack.alignment = .centerX
        stack.orientation = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            okButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = background
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(okButton)
    }

    @objc private func dismissPanel() {
        view.window?.close()
    }
}
