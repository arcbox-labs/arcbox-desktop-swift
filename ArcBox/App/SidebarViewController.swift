import AppKit

@MainActor
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier("SidebarSectionCell")
    private static let itemCellIdentifier = NSUserInterfaceItemIdentifier("SidebarItemCell")

    private let sections = NavItem.Section.allCases
    private let outlineView = NSOutlineView()
    private let accountButton = NSButton()
    private let accountProgressIndicator = NSProgressIndicator()
    private let onSelect: @MainActor (NavItem) -> Void
    private let onAccount: @MainActor () -> Void

    private var selection: NavItem?
    private var accountTitle = "Sign In"
    private var accountIsBusy = false
    private var accountIsEnabled = true
    private var accountHelp = "Sign in to ArcBox"

    init(
        selection: NavItem?,
        onSelect: @escaping @MainActor (NavItem) -> Void,
        onAccount: @escaping @MainActor () -> Void
    ) {
        self.selection = selection
        self.onSelect = onSelect
        self.onAccount = onAccount
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let background = NSVisualEffectView()
        background.blendingMode = .behindWindow
        background.material = .sidebar
        background.state = .followsWindowActiveState

        let scrollView = makeOutlineScrollView()
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        setUpAccountButton(in: footer)

        background.addSubview(scrollView)
        background.addSubview(separator)
        background.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: background.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.topAnchor.constraint(equalTo: separator.bottomAnchor),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            accountButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            accountButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            accountButton.topAnchor.constraint(equalTo: footer.topAnchor, constant: 8),
            accountButton.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8),
            accountButton.heightAnchor.constraint(equalToConstant: 32),
        ])

        view = background
        outlineView.reloadData()
        for section in sections {
            outlineView.expandItem(section)
        }
        applySelection()
        applyAccountState()
    }

    func select(_ item: NavItem) {
        selection = item
        guard isViewLoaded else { return }
        applySelection()
    }

    func updateAccount(
        title: String,
        isBusy: Bool,
        isEnabled: Bool,
        help: String
    ) {
        accountTitle = title
        accountIsBusy = isBusy
        accountIsEnabled = isEnabled
        accountHelp = help
        guard isViewLoaded else { return }
        applyAccountState()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return sections.count
        }
        return (item as? NavItem.Section)?.items.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return sections[index]
        }
        guard let section = item as? NavItem.Section else {
            preconditionFailure("Sidebar children must belong to a navigation section")
        }
        return section.items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is NavItem.Section
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is NavItem.Section
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is NavItem
    }

    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        if let section = item as? NavItem.Section {
            return sectionCell(for: section)
        }
        guard let item = item as? NavItem else { return nil }
        return itemCell(for: item)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? NavItem else { return }
        guard item != selection else { return }
        selection = item
        onSelect(item)
    }

    private func makeOutlineScrollView() -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.resizingMask = .autoresizingMask

        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowHeight = 28
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = false
        outlineView.backgroundColor = .clear
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityLabel("Main navigation")

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }

    private func setUpAccountButton(in footer: NSView) {
        accountButton.alignment = .left
        accountButton.bezelStyle = .recessed
        accountButton.font = .systemFont(ofSize: 13)
        accountButton.imageHugsTitle = true
        accountButton.imagePosition = .imageLeading
        accountButton.imageScaling = .scaleProportionallyDown
        accountButton.showsBorderOnlyWhileMouseInside = true
        accountButton.target = self
        accountButton.action = #selector(accountButtonPressed)
        accountButton.translatesAutoresizingMaskIntoConstraints = false

        accountProgressIndicator.controlSize = .small
        accountProgressIndicator.style = .spinning
        accountProgressIndicator.isIndeterminate = true
        accountProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        accountButton.addSubview(accountProgressIndicator)

        footer.addSubview(accountButton)
        NSLayoutConstraint.activate([
            accountProgressIndicator.leadingAnchor.constraint(
                equalTo: accountButton.leadingAnchor, constant: 6),
            accountProgressIndicator.centerYAnchor.constraint(equalTo: accountButton.centerYAnchor),
            accountProgressIndicator.widthAnchor.constraint(equalToConstant: 16),
            accountProgressIndicator.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func applySelection() {
        guard let selection else {
            outlineView.deselectAll(nil)
            return
        }

        for row in 0..<outlineView.numberOfRows
        where outlineView.item(atRow: row) as? NavItem == selection {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
            return
        }
    }

    private func applyAccountState() {
        accountButton.title = accountTitle
        accountButton.isEnabled = accountIsEnabled && !accountIsBusy
        accountButton.toolTip = accountHelp
        accountButton.setAccessibilityLabel(accountTitle)
        accountButton.setAccessibilityHelp(accountHelp)

        if accountIsBusy {
            accountButton.image = NSImage(size: NSSize(width: 16, height: 16))
            accountProgressIndicator.setAccessibilityLabel(accountTitle)
            accountProgressIndicator.isHidden = false
            accountProgressIndicator.startAnimation(nil)
        } else {
            accountProgressIndicator.stopAnimation(nil)
            accountProgressIndicator.isHidden = true
            let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            accountButton.image = NSImage(
                systemSymbolName: "person.crop.circle",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(configuration)
        }
    }

    private func sectionCell(for section: NavItem.Section) -> NSTableCellView {
        let cell =
            outlineView.makeView(withIdentifier: Self.sectionCellIdentifier, owner: nil)
            as? NSTableCellView ?? makeSectionCell()
        cell.textField?.stringValue = section.rawValue
        return cell
    }

    private func itemCell(for item: NavItem) -> NSTableCellView {
        let cell =
            outlineView.makeView(withIdentifier: Self.itemCellIdentifier, owner: nil)
            as? NSTableCellView ?? makeItemCell()
        cell.textField?.stringValue = item.label
        cell.imageView?.image = NSImage(
            systemSymbolName: item.sfSymbol,
            accessibilityDescription: nil
        )
        cell.setAccessibilityLabel(item.label)
        return cell
    }

    private func makeSectionCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.sectionCellIdentifier

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeItemCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.itemCellIdentifier

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.imageView = imageView
        cell.textField = label
        cell.addSubview(imageView)
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func accountButtonPressed() {
        onAccount()
    }
}
