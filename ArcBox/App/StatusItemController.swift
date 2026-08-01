import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    init(contentViewController: NSViewController) {
        super.init()
        popover.behavior = .transient
        popover.contentViewController = contentViewController
    }

    func replaceContentViewController(_ viewController: NSViewController) {
        popover.contentViewController = viewController
    }

    func setVisible(_ visible: Bool) {
        if visible {
            installStatusItem()
        } else {
            closePopover()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
        }
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "ArcBox")
            button.image?.isTemplate = true
            button.toolTip = "ArcBox"
            button.target = self
            button.action = #selector(statusItemPressed)
        }
        self.statusItem = statusItem
    }

    @objc private func statusItemPressed() {
        togglePopover()
    }
}
