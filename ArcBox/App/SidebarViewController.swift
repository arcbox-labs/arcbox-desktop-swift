import AppKit
import Foundation
import OSLog

@MainActor
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier("SidebarSectionCell")
    private static let itemCellIdentifier = NSUserInterfaceItemIdentifier("SidebarItemCell")

    private let sections = NavItem.Section.allCases
    private let outlineView = NSOutlineView()
    private let accountButton = SidebarAccountButton()
    private let onSelect: @MainActor (NavItem) -> Void
    private let onAccount: @MainActor () -> Void

    private var selection: NavItem?
    private var accountTitle = "Sign In"
    private var accountAvatarURL: URL?
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
        let background = NSView()

        let scrollView = makeOutlineScrollView()
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        setUpAccountButton(in: footer)

        background.addSubview(scrollView)
        background.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: background.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            accountButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            accountButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            accountButton.topAnchor.constraint(equalTo: footer.topAnchor, constant: 8),
            accountButton.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8),
            accountButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        view = background
        outlineView.reloadData()
        for section in sections {
            outlineView.expandItem(section)
        }
        applySelection()
        applyAccountState()
    }

    func select(_ item: NavItem?) {
        selection = item
        guard isViewLoaded else { return }
        applySelection()
    }

    func updateAccount(
        title: String,
        avatarURL: URL?,
        isBusy: Bool,
        isEnabled: Bool,
        help: String
    ) {
        accountTitle = title
        accountAvatarURL = avatarURL
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
        outlineView.rowSizeStyle = .medium
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
        accountButton.identifier = NSUserInterfaceItemIdentifier("SidebarAccountButton")
        accountButton.target = self
        accountButton.action = #selector(accountButtonPressed)
        accountButton.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(accountButton)
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
        accountButton.update(
            title: accountTitle,
            avatarURL: accountAvatarURL,
            isBusy: accountIsBusy,
            isEnabled: accountIsEnabled && !accountIsBusy,
            help: accountHelp
        )
    }

    private func sectionCell(for section: NavItem.Section) -> NSTableCellView {
        let cell =
            outlineView.makeView(withIdentifier: Self.sectionCellIdentifier, owner: nil)
            as? NSTableCellView ?? makeSectionCell()
        cell.textField?.stringValue = section.rawValue.capitalized
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
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func makeItemCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.itemCellIdentifier

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
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

@MainActor
private final class SidebarAccountButton: NSButton {
    private let contentContainer = NSView()
    private let avatarContainer = NSView()
    private let avatarView = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")

    private var avatarTask: Task<Void, Never>?
    private var representedAvatarURL: URL?
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        title = ""
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        avatarContainer.identifier = NSUserInterfaceItemIdentifier("SidebarAccountAvatar")
        avatarContainer.wantsLayer = true
        avatarContainer.layer?.cornerRadius = 12
        avatarContainer.layer?.masksToBounds = true
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false

        avatarView.frame = avatarContainer.bounds
        avatarView.autoresizingMask = [.width, .height]
        avatarView.imageScaling = .scaleProportionallyUpOrDown
        avatarView.setAccessibilityLabel("User avatar")
        avatarContainer.addSubview(avatarView)

        progressIndicator.controlSize = .small
        progressIndicator.style = .spinning
        progressIndicator.isIndeterminate = true
        progressIndicator.setAccessibilityElement(false)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentContainer)
        contentContainer.addSubview(avatarContainer)
        contentContainer.addSubview(progressIndicator)
        contentContainer.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarContainer.leadingAnchor.constraint(
                equalTo: contentContainer.leadingAnchor, constant: 8),
            avatarContainer.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            avatarContainer.widthAnchor.constraint(equalToConstant: 24),
            avatarContainer.heightAnchor.constraint(equalToConstant: 24),
            progressIndicator.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
        ])

        showFallbackAvatar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        avatarTask?.cancel()
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func highlight(_ flag: Bool) {
        isPressed = flag
        updateBackground()
        super.highlight(flag)
    }

    func update(
        title: String,
        avatarURL: URL?,
        isBusy: Bool,
        isEnabled: Bool,
        help: String
    ) {
        titleLabel.stringValue = title
        self.isEnabled = isEnabled
        alphaValue = isEnabled ? 1 : 0.5
        toolTip = help
        setAccessibilityLabel(title)
        setAccessibilityHelp(help)

        avatarContainer.isHidden = isBusy
        progressIndicator.isHidden = !isBusy
        if isBusy {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            loadAvatar(from: avatarURL)
        }
    }

    private func loadAvatar(from url: URL?) {
        guard representedAvatarURL != url else { return }
        avatarTask?.cancel()
        avatarTask = nil
        representedAvatarURL = url
        showFallbackAvatar()

        guard let url else { return }
        avatarTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard
                    let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode),
                    let image = NSImage(data: data),
                    let self,
                    representedAvatarURL == url
                else {
                    return
                }
                avatarView.image = image
            } catch is CancellationError {
                return
            } catch {
                Log.startup.debug("Sidebar avatar load failed")
            }
        }
    }

    private func showFallbackAvatar() {
        let palette = NSImage.SymbolConfiguration(paletteColors: [.white, .systemGray])
        avatarView.image = NSImage(
            systemSymbolName: "person.crop.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(palette)
    }

    private func updateBackground() {
        let color: NSColor =
            isHovered || isPressed
            ? .quaternarySystemFill
            : .clear
        layer?.backgroundColor = color.cgColor
    }
}
