import AppKit

extension AboutViewController {
    func linkButton(icon: String, title: String, url: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.alignment = .left
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 12)
        button.identifier = NSUserInterfaceItemIdentifier(url)
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.toolTip = "Open \(title) in your browser"
        button.setAccessibilityHelp(button.toolTip)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    @objc func openLink(_ sender: NSButton) {
        guard
            let address = sender.identifier?.rawValue,
            let destination = URL(string: address)
        else {
            preconditionFailure("About link button is missing a valid URL")
        }
        NSWorkspace.shared.open(destination)
    }
}
