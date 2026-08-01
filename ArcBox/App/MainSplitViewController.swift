import AppKit

@MainActor
final class MainSplitViewController: NSSplitViewController {
    private static let autosaveName = NSSplitView.AutosaveName("ArcBox.MainSplitView")
    private static let sidebarWidth: CGFloat = 180

    private let contentItem: NSSplitViewItem

    init(
        sidebarViewController: NSViewController,
        contentViewController: NSViewController
    ) {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        sidebarItem.canCollapse = false
        contentItem = NSSplitViewItem(viewController: contentViewController)

        super.init(nibName: nil, bundle: nil)

        splitView.autosaveName = Self.autosaveName
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func replaceContentViewController(_ viewController: NSViewController) {
        guard contentItem.viewController !== viewController else { return }
        removeSplitViewItem(contentItem)
        contentItem.viewController = viewController
        addSplitViewItem(contentItem)
    }
}
