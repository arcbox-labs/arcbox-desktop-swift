import AppKit
import OSLog
import Observation

@MainActor
final class NetworkDetailViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    struct ContainerEntry: Equatable {
        let id: String
        let name: String
        let ipv4: String
        let mac: String
    }

    typealias LoadContainers = @MainActor (String) async throws -> [ContainerEntry]

    private struct Snapshot: Equatable {
        let network: NetworkViewModel?

        init(viewModel: NetworksViewModel) {
            network = viewModel.selectedNetwork
        }
    }

    private static let infoTitles = [
        "Name", "ID", "Driver", "Scope", "Created", "Internal", "Attachable", "Containers",
    ]
    private static let nameColumnIdentifier = NSUserInterfaceItemIdentifier("NetworkContainerName")
    private static let statusColumnIdentifier = NSUserInterfaceItemIdentifier(
        "NetworkContainerStatus"
    )
    private static let ipv4ColumnIdentifier = NSUserInterfaceItemIdentifier("NetworkContainerIPv4")
    private static let macColumnIdentifier = NSUserInterfaceItemIdentifier("NetworkContainerMAC")

    private let viewModel: NetworksViewModel
    private let detailView = NSView()
    private let selectionPlaceholder = StatePlaceholderView(
        state: .empty(
            systemImage: "point.3.filled.connected.trianglepath.dotted",
            title: "No Selection",
            message: nil
        )
    )
    private let containersView = NSView()
    private let containersPlaceholder = StatePlaceholderView(
        state: .loading(title: "Loading connected containers…")
    )
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private var infoValueLabels: [NSTextField] = []
    private var snapshot: Snapshot?
    private var entries: [ContainerEntry] = []
    private var inspectState: LoadPhase = .waiting
    private var loadContainers: LoadContainers?
    private var runningContainerIDs: Set<String>
    private var loadTask: Task<Void, Never>?

    init(
        viewModel: NetworksViewModel,
        loadContainers: LoadContainers?,
        runningContainerIDs: Set<String>
    ) {
        self.viewModel = viewModel
        self.loadContainers = loadContainers
        self.runningContainerIDs = runningContainerIDs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func loadView() {
        let container = NSView()
        let infoCard = makeInfoCard()
        let sectionTitle = NSTextField(labelWithString: "Connected Containers")
        sectionTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        sectionTitle.textColor = .secondaryLabelColor

        setUpTableView()

        detailView.translatesAutoresizingMaskIntoConstraints = false
        selectionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        infoCard.translatesAutoresizingMaskIntoConstraints = false
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        containersView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containersPlaceholder.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(detailView)
        container.addSubview(selectionPlaceholder)
        detailView.addSubview(infoCard)
        detailView.addSubview(sectionTitle)
        detailView.addSubview(containersView)
        containersView.addSubview(scrollView)
        containersView.addSubview(containersPlaceholder)

        NSLayoutConstraint.activate([
            detailView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            detailView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            detailView.topAnchor.constraint(equalTo: container.topAnchor),
            detailView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            selectionPlaceholder.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionPlaceholder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            selectionPlaceholder.topAnchor.constraint(equalTo: container.topAnchor),
            selectionPlaceholder.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            infoCard.leadingAnchor.constraint(equalTo: detailView.leadingAnchor, constant: 16),
            infoCard.trailingAnchor.constraint(equalTo: detailView.trailingAnchor, constant: -16),
            infoCard.topAnchor.constraint(equalTo: detailView.topAnchor, constant: 16),
            sectionTitle.leadingAnchor.constraint(equalTo: detailView.leadingAnchor, constant: 16),
            sectionTitle.trailingAnchor.constraint(equalTo: detailView.trailingAnchor, constant: -16),
            sectionTitle.topAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: 16),
            containersView.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
            containersView.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
            containersView.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 6),
            containersView.bottomAnchor.constraint(equalTo: detailView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containersView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containersView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containersView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containersView.bottomAnchor),
            containersPlaceholder.leadingAnchor.constraint(equalTo: containersView.leadingAnchor),
            containersPlaceholder.trailingAnchor.constraint(equalTo: containersView.trailingAnchor),
            containersPlaceholder.topAnchor.constraint(equalTo: containersView.topAnchor),
            containersPlaceholder.bottomAnchor.constraint(equalTo: containersView.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeAndRender()
    }

    func update(
        loadContainers: LoadContainers?,
        runningContainerIDs: Set<String>
    ) {
        let availabilityChanged = (self.loadContainers == nil) != (loadContainers == nil)
        let runningStateChanged = self.runningContainerIDs != runningContainerIDs
        self.loadContainers = loadContainers
        self.runningContainerIDs = runningContainerIDs

        if runningStateChanged, !entries.isEmpty {
            tableView.reloadData()
        }

        guard availabilityChanged, snapshot?.network != nil else { return }
        if loadContainers != nil {
            reloadContainers()
        } else {
            loadTask?.cancel()
            loadTask = nil
            entries = []
            inspectState = .failed("Docker client unavailable.")
            tableView.reloadData()
            renderContainers()
        }
    }

    func numberOfRows(in _: NSTableView) -> Int {
        entries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard entries.indices.contains(row), let identifier = tableColumn?.identifier else {
            return nil
        }
        let entry = entries[row]

        switch identifier {
        case Self.nameColumnIdentifier:
            let cell = nameCell(in: tableView)
            cell.textField?.stringValue = entry.name
            cell.setAccessibilityLabel(entry.name)
            return cell
        case Self.statusColumnIdentifier:
            let isRunning = runningContainerIDs.contains(entry.id)
            let status = isRunning ? "Running" : "Stopped"
            let cell = textCell(
                in: tableView,
                identifier: identifier,
                alignment: .center,
                monospaced: false
            )
            cell.textField?.attributedStringValue = statusValue(
                status,
                color: isRunning ? .systemGreen : .systemGray
            )
            cell.setAccessibilityLabel(status)
            return cell
        case Self.ipv4ColumnIdentifier:
            let cell = textCell(
                in: tableView,
                identifier: identifier,
                alignment: .left,
                monospaced: true
            )
            cell.textField?.stringValue = entry.ipv4
            cell.setAccessibilityLabel(entry.ipv4)
            return cell
        case Self.macColumnIdentifier:
            let cell = textCell(
                in: tableView,
                identifier: identifier,
                alignment: .left,
                monospaced: true
            )
            cell.textField?.stringValue = entry.mac
            cell.setAccessibilityLabel(entry.mac)
            return cell
        default:
            return nil
        }
    }

    func tableView(_: NSTableView, shouldSelectRow _: Int) -> Bool {
        false
    }

    private func observeAndRender() {
        let modelChanged = snapshot != nil
        let snapshot = withObservationTracking {
            Snapshot(viewModel: viewModel)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRender()
            }
        }
        render(snapshot, modelChanged: modelChanged)
    }

    private func render(_ snapshot: Snapshot, modelChanged: Bool) {
        let previous = self.snapshot
        self.snapshot = snapshot
        guard modelChanged || previous != snapshot else { return }

        guard let network = snapshot.network else {
            loadTask?.cancel()
            loadTask = nil
            entries = []
            inspectState = .waiting
            tableView.reloadData()
            detailView.isHidden = true
            selectionPlaceholder.isHidden = false
            NSAccessibility.post(element: view, notification: .layoutChanged)
            return
        }

        configureInfo(network)
        detailView.isHidden = false
        selectionPlaceholder.isHidden = true

        if modelChanged || previous?.network?.id != network.id {
            reloadContainers()
        }
        NSAccessibility.post(element: view, notification: .layoutChanged)
    }

    private func reloadContainers() {
        guard let network = snapshot?.network else { return }

        loadTask?.cancel()
        entries = []
        inspectState = .loading
        tableView.reloadData()
        renderContainers()

        guard let loadContainers else {
            inspectState = .failed("Docker client unavailable.")
            renderContainers()
            return
        }

        let networkID = network.id
        loadTask = Task { [weak self] in
            do {
                let entries = try await loadContainers(networkID)
                guard
                    !Task.isCancelled,
                    let self,
                    self.viewModel.selectedID == networkID
                else { return }
                self.entries = entries
                self.inspectState = .loaded
                self.tableView.reloadData()
                self.renderContainers()
            } catch {
                guard
                    !Task.isCancelled,
                    !(error is CancellationError),
                    let self,
                    self.viewModel.selectedID == networkID
                else { return }
                Log.network.error(
                    "Error inspecting network \(networkID, privacy: .private): \(error.localizedDescription, privacy: .private)"
                )
                self.entries = []
                self.inspectState = .failed(error.localizedDescription)
                self.tableView.reloadData()
                self.renderContainers()
            }
        }
    }

    private func renderContainers() {
        switch inspectState {
        case .waiting, .loading:
            showContainersPlaceholder(.loading(title: "Loading connected containers…"))
        case .failed(let message):
            showContainersPlaceholder(
                .error(title: "Failed to inspect network", message: message),
                action: .init(title: "Retry") { [weak self] in
                    self?.reloadContainers()
                }
            )
        case .loaded where entries.isEmpty:
            showContainersPlaceholder(
                .empty(
                    systemImage: "shippingbox",
                    title: "No containers connected",
                    message: nil
                )
            )
        case .loaded:
            containersPlaceholder.isHidden = true
            scrollView.isHidden = false
        }
        NSAccessibility.post(element: containersView, notification: .layoutChanged)
    }

    private func showContainersPlaceholder(
        _ state: StatePlaceholderView.State,
        action: StatePlaceholderView.Action? = nil
    ) {
        containersPlaceholder.update(state, action: action)
        containersPlaceholder.isHidden = false
        scrollView.isHidden = true
    }

    private func configureInfo(_ network: NetworkViewModel) {
        let values = [
            network.name,
            network.shortID,
            network.driver,
            network.scope,
            network.createdAgo,
            network.`internal` ? "Yes" : "No",
            network.attachable ? "Yes" : "No",
            network.usageDisplay,
        ]

        for (label, value) in zip(infoValueLabels, values) {
            label.stringValue = value
        }
    }

    private func makeInfoCard() -> NSBox {
        var rows: [[NSView]] = []
        for title in Self.infoTitles {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)

            let valueLabel = NSTextField(labelWithString: "")
            valueLabel.alignment = .right
            valueLabel.font = .systemFont(ofSize: 13)
            valueLabel.textColor = .secondaryLabelColor
            valueLabel.lineBreakMode = .byTruncatingMiddle
            valueLabel.isSelectable = true
            valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            rows.append([titleLabel, valueLabel])
            infoValueLabels.append(valueLabel)
        }

        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])

        let box = NSBox()
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = 8
        box.fillColor = .controlBackgroundColor
        box.titlePosition = .noTitle
        box.contentViewMargins = .zero
        box.contentView = content
        return box
    }

    private func setUpTableView() {
        let nameColumn = NSTableColumn(identifier: Self.nameColumnIdentifier)
        nameColumn.title = "Name"
        nameColumn.minWidth = 140
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]

        let statusColumn = NSTableColumn(identifier: Self.statusColumnIdentifier)
        statusColumn.title = "Status"
        statusColumn.width = 90
        statusColumn.minWidth = 80
        statusColumn.maxWidth = 120
        statusColumn.resizingMask = .userResizingMask

        let ipv4Column = NSTableColumn(identifier: Self.ipv4ColumnIdentifier)
        ipv4Column.title = "IPv4 Address"
        ipv4Column.width = 140
        ipv4Column.minWidth = 100
        ipv4Column.resizingMask = .userResizingMask

        let macColumn = NSTableColumn(identifier: Self.macColumnIdentifier)
        macColumn.title = "MAC Address"
        macColumn.width = 160
        macColumn.minWidth = 120
        macColumn.resizingMask = .userResizingMask

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(ipv4Column)
        tableView.addTableColumn(macColumn)
        tableView.style = .fullWidth
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = .zero
        tableView.rowHeight = AppMetrics.rowHeight
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Connected Containers")

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func nameCell(in tableView: NSTableView) -> NSTableCellView {
        if let cell = tableView.makeView(withIdentifier: Self.nameColumnIdentifier, owner: nil)
            as? NSTableCellView
        {
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = Self.nameColumnIdentifier

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(label)
        cell.imageView = imageView
        cell.textField = label
        cell.setAccessibilityElement(true)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func textCell(
        in tableView: NSTableView,
        identifier: NSUserInterfaceItemIdentifier,
        alignment: NSTextAlignment,
        monospaced: Bool
    ) -> NSTableCellView {
        if let cell = tableView.makeView(withIdentifier: identifier, owner: nil)
            as? NSTableCellView
        {
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = identifier
        cell.setAccessibilityElement(true)

        let label = NSTextField(labelWithString: "")
        label.alignment = alignment
        label.font =
            monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func statusValue(_ status: String, color: NSColor) -> NSAttributedString {
        let value = NSMutableAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: AppMetrics.statusDot),
                .foregroundColor: color,
            ]
        )
        value.append(
            NSAttributedString(
                string: status,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
        )
        return value
    }
}
