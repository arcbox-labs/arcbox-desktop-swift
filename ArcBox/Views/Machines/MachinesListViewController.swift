import AppKit
import Observation

@MainActor
final class MachinesListViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    private enum Row: Equatable {
        case section(String)
        case machine(MachineViewModel)
    }

    private struct Snapshot: Equatable {
        let loadState: LoadPhase
        let hasMachines: Bool
        let rows: [Row]
        let searchText: String
        let selectedID: String?

        init(viewModel: MachinesViewModel) {
            loadState = viewModel.loadState
            hasMachines = !viewModel.machines.isEmpty
            searchText = viewModel.searchText
            selectedID = viewModel.selectedID

            let machines = viewModel.filteredMachines
            let running = machines.filter(\.isRunning)
            let stopped = machines.filter { !$0.isRunning }
            rows =
                running.map(Row.machine)
                + (stopped.isEmpty ? [] : [.section("Stopped")] + stopped.map(Row.machine))
        }
    }

    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier("MachineSectionCell")
    private static let machineCellIdentifier = NSUserInterfaceItemIdentifier("MachineCell")

    private let viewModel: MachinesViewModel
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let placeholderView = StatePlaceholderView(
        state: .loading(title: "Loading machines…")
    )
    private let emptyStateView = MachineEmptyStateView()
    private let errorStateView = MachineLoadErrorView()

    private var snapshot: Snapshot?
    private var onRetry: @MainActor () -> Void
    private var onToggle: @MainActor (String) -> Void
    private var onDelete: @MainActor (String) -> Void
    private var deleteAlert: NSAlert?
    private var isApplyingSelection = false

    init(
        viewModel: MachinesViewModel,
        onRetry: @escaping @MainActor () -> Void,
        onToggle: @escaping @MainActor (String) -> Void,
        onDelete: @escaping @MainActor (String) -> Void
    ) {
        self.viewModel = viewModel
        self.onRetry = onRetry
        self.onToggle = onToggle
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        setUpTableView()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        errorStateView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(placeholderView)
        container.addSubview(emptyStateView)
        container.addSubview(errorStateView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: container.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: container.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            errorStateView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            errorStateView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            errorStateView.topAnchor.constraint(equalTo: container.topAnchor),
            errorStateView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeAndRender()
    }

    func update(
        onRetry: @escaping @MainActor () -> Void,
        onToggle: @escaping @MainActor (String) -> Void,
        onDelete: @escaping @MainActor (String) -> Void
    ) {
        self.onRetry = onRetry
        self.onToggle = onToggle
        self.onDelete = onDelete
        guard let snapshot, isViewLoaded else { return }
        if case .failed(let message) = snapshot.loadState {
            errorStateView.update(message: message, onRetry: onRetry)
        }
    }

    func numberOfRows(in _: NSTableView) -> Int {
        snapshot?.rows.count ?? 0
    }

    func tableView(
        _: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let item = snapshot?.rows[row] else { return nil }
        switch item {
        case .section(let title):
            return sectionCell(title: title)
        case .machine(let machine):
            return machineCell(machine: machine)
        }
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = snapshot?.rows[row] else { return 0 }
        switch item {
        case .section: return 28
        case .machine: return AppMetrics.rowHeight
        }
    }

    func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let item = snapshot?.rows[row] else { return nil }
        if case .machine = item {
            return ResourceListRowView(horizontalInset: 8)
        }
        return nil
    }

    func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
        guard let item = snapshot?.rows[row] else { return false }
        if case .section = item {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard let item = snapshot?.rows[row] else { return false }
        if case .machine = item {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let selectedID = machine(at: tableView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        viewModel.selectedID = selectedID
    }

    private func observeAndRender() {
        let snapshot = withObservationTracking {
            Snapshot(viewModel: viewModel)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRender()
            }
        }
        render(snapshot)
    }

    private func render(_ snapshot: Snapshot) {
        let previous = self.snapshot
        let rowsChanged = previous?.rows != snapshot.rows
        let presentationChanged =
            previous == nil
            || previous?.loadState != snapshot.loadState
            || previous?.hasMachines != snapshot.hasMachines
            || (snapshot.rows.isEmpty && previous?.searchText != snapshot.searchText)

        self.snapshot = snapshot
        if rowsChanged {
            applyingSelection {
                tableView.reloadData()
            }
        }

        if rowsChanged || presentationChanged {
            switch snapshot.loadState {
            case .waiting, .loading:
                showPlaceholder(.loading(title: "Loading machines…"))
            case .failed(let message):
                showError(message)
            case .loaded where !snapshot.hasMachines:
                showEmptyState()
            case .loaded where snapshot.rows.isEmpty:
                showPlaceholder(
                    .empty(
                        systemImage: "magnifyingglass",
                        title: "No Results",
                        message: "No machines match “\(snapshot.searchText)”."
                    )
                )
            case .loaded:
                placeholderView.isHidden = true
                emptyStateView.isHidden = true
                errorStateView.isHidden = true
                scrollView.isHidden = false
            }
            NSAccessibility.post(element: view, notification: .layoutChanged)
        }

        if case .loaded = snapshot.loadState {
            applySelection(snapshot.selectedID)
        }
    }

    private func showPlaceholder(
        _ state: StatePlaceholderView.State,
        action: StatePlaceholderView.Action? = nil
    ) {
        placeholderView.update(state, action: action)
        placeholderView.isHidden = false
        emptyStateView.isHidden = true
        errorStateView.isHidden = true
        scrollView.isHidden = true
    }

    private func showEmptyState() {
        placeholderView.isHidden = true
        emptyStateView.isHidden = false
        errorStateView.isHidden = true
        scrollView.isHidden = true
    }

    private func showError(_ message: String) {
        errorStateView.update(message: message, onRetry: onRetry)
        errorStateView.isHidden = false
        placeholderView.isHidden = true
        emptyStateView.isHidden = true
        scrollView.isHidden = true
    }

    private func setUpTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MachineColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .fullWidth
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.floatsGroupRows = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Machines")

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func sectionCell(title: String) -> NSTableCellView {
        let cell =
            tableView.makeView(withIdentifier: Self.sectionCellIdentifier, owner: nil)
            as? NSTableCellView ?? makeSectionCell()
        cell.textField?.stringValue = title
        cell.setAccessibilityLabel(title)
        return cell
    }

    private func makeSectionCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.sectionCellIdentifier
        cell.setAccessibilityElement(true)
        cell.setAccessibilityRole(.group)

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
        ])
        return cell
    }

    private func machineCell(machine: MachineViewModel) -> MachineTableCellView {
        let cell =
            tableView.makeView(withIdentifier: Self.machineCellIdentifier, owner: nil)
            as? MachineTableCellView ?? MachineTableCellView()
        cell.identifier = Self.machineCellIdentifier
        cell.configure(
            machine: machine,
            onToggle: { [weak self] in
                self?.toggleMachine(machine.id)
            },
            onDelete: { [weak self] in
                self?.confirmDelete(machine.id)
            }
        )
        return cell
    }

    private func machine(at row: Int) -> MachineViewModel? {
        guard row >= 0, let rows = snapshot?.rows, row < rows.count else { return nil }
        guard case .machine(let machine) = rows[row] else { return nil }
        return machine
    }

    private func currentMachine(id: String) -> MachineViewModel? {
        viewModel.machines.first { $0.id == id }
    }

    private func toggleMachine(_ id: String) {
        guard let machine = currentMachine(id: id), !machine.isBusy else { return }
        onToggle(id)
    }

    private func confirmDelete(_ id: String) {
        guard
            let machine = currentMachine(id: id),
            !machine.isBusy,
            deleteAlert == nil,
            let window = view.window
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Machine “\(machine.name)”?"
        alert.informativeText = "This permanently deletes the machine and its data disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        deleteAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            deleteAlert = nil
            guard
                response == .alertFirstButtonReturn,
                let machine = currentMachine(id: id),
                !machine.isBusy
            else {
                return
            }
            onDelete(id)
        }
    }

    private func applySelection(_ selectedID: String?) {
        guard
            let selectedID,
            let rows = snapshot?.rows,
            let row = rows.firstIndex(where: {
                guard case .machine(let machine) = $0 else { return false }
                return machine.id == selectedID
            })
        else {
            if let selectedID,
                !viewModel.machines.contains(where: { $0.id == selectedID })
            {
                viewModel.selectedID = nil
            }
            guard tableView.selectedRow != -1 else { return }
            applyingSelection {
                tableView.deselectAll(nil)
            }
            return
        }
        guard tableView.selectedRow != row else { return }
        applyingSelection {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        tableView.scrollRowToVisible(row)
    }

    private func applyingSelection(_ action: () -> Void) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        action()
    }
}

@MainActor
private final class MachineTableCellView: NSTableCellView, ResourceListActionDisplaying {
    private static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemCyan,
        .systemBlue, .systemPurple, .systemPink, .systemIndigo, .systemTeal,
    ]

    private let iconBox = NSBox()
    private let machineImageView = NSImageView()
    private let statusDot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let busyIndicator = NSProgressIndicator()
    private let toggleButton = ResourceActionButton()
    private let deleteButton = ResourceActionButton()

    private var labelsToActionsConstraint: NSLayoutConstraint?
    private var labelsToBusyConstraint: NSLayoutConstraint?
    private var iconColor = NSColor.secondaryLabelColor
    private var statusColor = NSColor.secondaryLabelColor
    private var isBusy = false
    private var showsActions = false
    private var onToggle: (@MainActor () -> Void)?
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = AppColors.iconBackgroundNSColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        machineImageView.image = NSImage(
            systemSymbolName: "desktopcomputer",
            accessibilityDescription: nil
        )
        machineImageView.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        machineImageView.setAccessibilityElement(false)
        machineImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(machineImageView)

        statusDot.identifier = NSUserInterfaceItemIdentifier("MachineStatusDot")
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 6
        statusDot.layer?.borderWidth = 2
        statusDot.setAccessibilityElement(false)
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [nameLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        busyIndicator.identifier = NSUserInterfaceItemIdentifier("MachineBusyIndicator")
        busyIndicator.style = .spinning
        busyIndicator.controlSize = .small
        busyIndicator.isIndeterminate = true
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            toggleButton,
            identifier: "MachineToggleButton",
            action: #selector(togglePressed)
        )
        configureButton(
            deleteButton,
            identifier: "MachineDeleteButton",
            action: #selector(deletePressed)
        )
        deleteButton.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)

        let actions = NSStackView(views: [toggleButton, deleteButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBox)
        addSubview(statusDot)
        addSubview(labels)
        addSubview(busyIndicator)
        addSubview(actions)
        imageView = machineImageView
        textField = nameLabel

        let labelsToActionsConstraint = labels.trailingAnchor.constraint(
            lessThanOrEqualTo: actions.leadingAnchor,
            constant: -8
        )
        let labelsToBusyConstraint = labels.trailingAnchor.constraint(
            lessThanOrEqualTo: busyIndicator.leadingAnchor,
            constant: -8
        )
        self.labelsToActionsConstraint = labelsToActionsConstraint
        self.labelsToBusyConstraint = labelsToBusyConstraint

        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            machineImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            machineImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            machineImageView.widthAnchor.constraint(equalToConstant: 22),
            machineImageView.heightAnchor.constraint(equalToConstant: 22),
            statusDot.widthAnchor.constraint(equalToConstant: 12),
            statusDot.heightAnchor.constraint(equalToConstant: 12),
            statusDot.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 2),
            statusDot.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor, constant: 2),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 8),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
            busyIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            busyIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            busyIndicator.widthAnchor.constraint(equalToConstant: 16),
            busyIndicator.heightAnchor.constraint(equalToConstant: 16),
            toggleButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            toggleButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            deleteButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            deleteButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateColors()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        busyIndicator.stopAnimation(nil)
        onToggle = nil
        onDelete = nil
    }

    func configure(
        machine: MachineViewModel,
        onToggle: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor () -> Void
    ) {
        nameLabel.stringValue = machine.name
        detailLabel.stringValue = "\(machine.distro.version), \(machine.cpuCores) cores"
        iconColor =
            machine.isRunning
            ? Self.color(for: machine.distro.name)
            : .tertiaryLabelColor
        statusColor = Self.color(for: machine.state)

        toggleButton.image = NSImage(
            systemSymbolName: machine.isRunning ? "stop.fill" : "play.fill",
            accessibilityDescription: nil
        )
        toggleButton.toolTip = machine.isRunning ? "Stop machine" : "Start machine"
        toggleButton.setAccessibilityLabel(
            "\(machine.isRunning ? "Stop" : "Start") \(machine.name)"
        )
        deleteButton.toolTip = "Delete machine"
        deleteButton.setAccessibilityLabel("Delete \(machine.name)")

        isBusy = machine.isBusy
        busyIndicator.isHidden = !machine.isBusy
        toggleButton.isEnabled = !machine.isBusy
        deleteButton.isEnabled = !machine.isBusy
        if machine.isBusy {
            busyIndicator.setAccessibilityLabel("Updating \(machine.name)")
            busyIndicator.startAnimation(nil)
            self.onToggle = nil
            self.onDelete = nil
        } else {
            busyIndicator.stopAnimation(nil)
            self.onToggle = onToggle
            self.onDelete = onDelete
        }
        updateActionVisibility()

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(machine.name), \(machine.distro.displayName) \(machine.distro.version), "
                + "\(machine.cpuCores) cores, \(machine.state.label)"
        )
        updateColors()
    }

    func setShowsActions(_ showsActions: Bool) {
        self.showsActions = showsActions
        updateActionVisibility()
    }

    private func configureButton(
        _ button: ResourceActionButton,
        identifier: String,
        action: Selector
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.contentTintColor = .secondaryLabelColor
        button.isHidden = true
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private static func color(for distro: String) -> NSColor {
        let hash = distro.utf8.reduce(0) { value, byte in
            value &* 31 &+ Int(byte)
        }
        let index = Int(hash.magnitude % UInt(palette.count))
        return palette[index]
    }

    private static func color(for state: MachineState) -> NSColor {
        switch state {
        case .running: .systemGreen
        case .starting, .stopping: .systemOrange
        case .created, .stopped: .secondaryLabelColor
        }
    }

    private func updateColors() {
        let isSelected = backgroundStyle == .emphasized
        nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        detailLabel.textColor =
            isSelected
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
            : .secondaryLabelColor
        toggleButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        deleteButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        machineImageView.contentTintColor = iconColor
        statusDot.layer?.backgroundColor = statusColor.cgColor
        statusDot.layer?.borderColor =
            (isSelected ? NSColor.controlAccentColor : NSColor.textBackgroundColor).cgColor
    }

    private func updateActionVisibility() {
        let showsMachineActions = showsActions && !isBusy
        toggleButton.isHidden = !showsMachineActions
        deleteButton.isHidden = !showsMachineActions
        labelsToActionsConstraint?.isActive = showsMachineActions
        labelsToBusyConstraint?.isActive = isBusy
    }

    @objc private func togglePressed() {
        onToggle?()
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
