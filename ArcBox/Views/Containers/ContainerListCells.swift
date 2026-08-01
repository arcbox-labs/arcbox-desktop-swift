import AppKit
import Foundation

@MainActor
final class ContainerGroupTableCellView: NSTableCellView {
    private let iconBox = NSBox()
    private let groupImageView = NSImageView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let busyIndicator = NSProgressIndicator()
    private let toggleButton = NSButton()
    private let deleteButton = NSButton()

    private var onToggle: (@MainActor () -> Void)?
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = .quaternarySystemFill
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        groupImageView.image = NSImage(
            systemSymbolName: "square.3.layers.3d",
            accessibilityDescription: nil
        )
        groupImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        groupImageView.setAccessibilityElement(false)
        groupImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(groupImageView)

        projectLabel.font = .systemFont(ofSize: 13, weight: .medium)
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [projectLabel, countLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 0
        labels.translatesAutoresizingMaskIntoConstraints = false

        busyIndicator.identifier = NSUserInterfaceItemIdentifier("ContainerGroupBusyIndicator")
        busyIndicator.style = .spinning
        busyIndicator.controlSize = .small
        busyIndicator.isIndeterminate = true
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            toggleButton,
            identifier: "ContainerGroupToggleButton",
            action: #selector(togglePressed)
        )
        configureButton(
            deleteButton,
            identifier: "ContainerGroupDeleteButton",
            action: #selector(deletePressed)
        )
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)

        let actions = NSStackView(
            views: [busyIndicator, toggleButton, deleteButton]
        )
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBox)
        addSubview(labels)
        addSubview(actions)
        imageView = groupImageView
        textField = projectLabel

        let softWidthConstraints = [
            iconBox.widthAnchor.constraint(equalToConstant: 28),
            toggleButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
        ]
        softWidthConstraints.forEach { $0.priority = .defaultHigh }

        NSLayoutConstraint.activate(
            [
                iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconBox.heightAnchor.constraint(equalToConstant: 28),
                groupImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                groupImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                groupImageView.widthAnchor.constraint(equalToConstant: 20),
                groupImageView.heightAnchor.constraint(equalToConstant: 20),
                labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 8),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),
                actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                actions.centerYAnchor.constraint(equalTo: centerYAnchor),
                busyIndicator.widthAnchor.constraint(equalToConstant: 16),
                busyIndicator.heightAnchor.constraint(equalToConstant: 16),
                toggleButton.heightAnchor.constraint(equalToConstant: 24),
                deleteButton.heightAnchor.constraint(equalToConstant: 24),
            ] + softWidthConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        busyIndicator.stopAnimation(nil)
        onToggle = nil
        onDelete = nil
    }

    func configure(
        project: String,
        containers: [ContainerViewModel],
        onToggle: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor () -> Void
    ) {
        prepareForReuse()

        let runningCount = containers.filter(\.isRunning).count
        let isBusy = containers.contains(where: \.isTransitioning)
        let hasRunning = runningCount > 0

        projectLabel.stringValue = project
        countLabel.stringValue = "\(runningCount)/\(containers.count)"
        groupImageView.contentTintColor = hasRunning ? .controlAccentColor : .tertiaryLabelColor
        toggleButton.image = NSImage(
            systemSymbolName: hasRunning ? "stop.fill" : "play.fill",
            accessibilityDescription: nil
        )
        toggleButton.toolTip = hasRunning ? "Stop project containers" : "Start project containers"
        toggleButton.setAccessibilityLabel(
            "\(hasRunning ? "Stop" : "Start") containers in \(project)"
        )
        deleteButton.toolTip = "Delete project containers"
        deleteButton.setAccessibilityLabel(
            "Delete \(containers.count) containers in \(project)"
        )

        busyIndicator.isHidden = !isBusy
        toggleButton.isHidden = isBusy
        deleteButton.isHidden = isBusy
        toggleButton.isEnabled = !isBusy
        deleteButton.isEnabled = !isBusy
        if isBusy {
            busyIndicator.setAccessibilityLabel("Updating \(project)")
            busyIndicator.startAnimation(nil)
        } else {
            self.onToggle = onToggle
            self.onDelete = onDelete
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(project), \(runningCount) of \(containers.count) running"
        )
    }

    private func configureButton(
        _ button: NSButton,
        identifier: String,
        action: Selector
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func togglePressed() {
        onToggle?()
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}

@MainActor
final class ContainerTableCellView: NSTableCellView {
    private static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemCyan,
        .systemBlue, .systemPurple, .systemPink, .systemIndigo, .systemTeal,
    ]

    private let iconBox = NSBox()
    private let containerImageView = NSImageView()
    private let statusDot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let imageLabel = NSTextField(labelWithString: "")
    private let linkButton = NSButton()
    private let busyIndicator = NSProgressIndicator()
    private let toggleButton = NSButton()
    private let deleteButton = NSButton()

    private var iconTask: Task<Void, Never>?
    private var representedID: String?
    private var representedIconURL: URL?
    private var fallbackColor = NSColor.secondaryLabelColor
    private var showsRemoteIcon = false
    private var ports: [PortMapping] = []
    private var hostDomain = ""
    private var useDNS = false
    private var onOpenPort: (@MainActor (PortMapping) -> Void)?
    private var onToggle: (@MainActor () -> Void)?
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = .quaternarySystemFill
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        containerImageView.imageScaling = .scaleProportionallyDown
        containerImageView.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        containerImageView.setAccessibilityElement(false)
        containerImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(containerImageView)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 6
        statusDot.setAccessibilityElement(false)
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        imageLabel.font = .systemFont(ofSize: 11)
        imageLabel.textColor = .secondaryLabelColor
        imageLabel.lineBreakMode = .byTruncatingTail
        imageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [nameLabel, imageLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            linkButton,
            identifier: "ContainerLinkButton",
            action: #selector(linkPressed)
        )
        linkButton.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)

        busyIndicator.identifier = NSUserInterfaceItemIdentifier("ContainerBusyIndicator")
        busyIndicator.style = .spinning
        busyIndicator.controlSize = .small
        busyIndicator.isIndeterminate = true
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            toggleButton,
            identifier: "ContainerToggleButton",
            action: #selector(togglePressed)
        )
        configureButton(
            deleteButton,
            identifier: "ContainerDeleteButton",
            action: #selector(deletePressed)
        )
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)

        let actions = NSStackView(
            views: [linkButton, busyIndicator, toggleButton, deleteButton]
        )
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBox)
        addSubview(statusDot)
        addSubview(labels)
        addSubview(actions)
        imageView = containerImageView
        textField = nameLabel

        let softWidthConstraints = [
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            linkButton.widthAnchor.constraint(equalToConstant: 24),
            toggleButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
        ]
        softWidthConstraints.forEach { $0.priority = .defaultHigh }

        NSLayoutConstraint.activate(
            [
                iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
                containerImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                containerImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                containerImageView.widthAnchor.constraint(equalToConstant: 28),
                containerImageView.heightAnchor.constraint(equalToConstant: 28),
                statusDot.widthAnchor.constraint(equalToConstant: 12),
                statusDot.heightAnchor.constraint(equalToConstant: 12),
                statusDot.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 2),
                statusDot.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor, constant: 2),
                labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 10),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),
                actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                actions.centerYAnchor.constraint(equalTo: centerYAnchor),
                linkButton.heightAnchor.constraint(equalToConstant: 24),
                busyIndicator.widthAnchor.constraint(equalToConstant: 16),
                busyIndicator.heightAnchor.constraint(equalToConstant: 16),
                toggleButton.heightAnchor.constraint(equalToConstant: 24),
                deleteButton.heightAnchor.constraint(equalToConstant: 24),
            ] + softWidthConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        iconTask?.cancel()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            prepareForReuse()
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateColors()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconTask?.cancel()
        iconTask = nil
        representedID = nil
        representedIconURL = nil
        showsRemoteIcon = false
        containerImageView.image = nil
        busyIndicator.stopAnimation(nil)
        ports = []
        onOpenPort = nil
        onToggle = nil
        onDelete = nil
    }

    func configure(
        container: ContainerViewModel,
        useDNS: Bool,
        onOpenPort: @escaping @MainActor (PortMapping) -> Void,
        onToggle: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor () -> Void
    ) {
        prepareForReuse()

        representedID = container.id
        nameLabel.stringValue = container.name
        imageLabel.stringValue = container.image
        fallbackColor =
            !container.isRunning && !container.isTransitioning
            ? .tertiaryLabelColor
            : Self.color(for: container.image)
        statusDot.layer?.backgroundColor = Self.color(for: container.state).cgColor

        self.useDNS = useDNS
        hostDomain = container.hostDomain(useDNS: useDNS)
        ports =
            useDNS
            ? container.ports
            : container.ports.filter { $0.hostPort > 0 }
        linkButton.isHidden = ports.isEmpty
        linkButton.toolTip = ports.count > 1 ? "Open container port menu" : "Open container port"
        linkButton.setAccessibilityLabel(
            ports.count > 1
                ? "Open \(container.name) port menu"
                : "Open \(container.name) at \(address(for: ports.first))"
        )
        self.onOpenPort = onOpenPort

        toggleButton.image = NSImage(
            systemSymbolName: container.isRunning ? "stop.fill" : "play.fill",
            accessibilityDescription: nil
        )
        toggleButton.toolTip = container.isRunning ? "Stop container" : "Start container"
        toggleButton.setAccessibilityLabel(
            "\(container.isRunning ? "Stop" : "Start") \(container.name)"
        )
        deleteButton.toolTip = "Delete container"
        deleteButton.setAccessibilityLabel("Delete \(container.name)")

        let isBusy = container.isTransitioning
        busyIndicator.isHidden = !isBusy
        toggleButton.isHidden = isBusy
        deleteButton.isHidden = isBusy
        toggleButton.isEnabled = !isBusy
        deleteButton.isEnabled = !isBusy
        if isBusy {
            busyIndicator.setAccessibilityLabel("Updating \(container.name)")
            busyIndicator.startAnimation(nil)
        } else {
            self.onToggle = onToggle
            self.onDelete = onDelete
        }

        showFallbackIcon()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(container.name), \(container.image), \(container.state.label)"
        )
        updateColors()
        loadIcon(container.iconURL, representedID: container.id)
    }

    private func configureButton(
        _ button: NSButton,
        identifier: String,
        action: Selector
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func loadIcon(_ iconURL: String?, representedID: String) {
        guard
            let iconURL,
            !iconURL.isEmpty,
            let url = URL(string: iconURL)
        else {
            return
        }

        representedIconURL = url
        iconTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard
                    let image = NSImage(data: data),
                    let self,
                    self.representedID == representedID,
                    representedIconURL == url
                else {
                    return
                }
                showsRemoteIcon = true
                containerImageView.image = image
                containerImageView.contentTintColor = nil
            } catch {
                // Keep the deterministic fallback icon.
            }
        }
    }

    private static func color(for image: String) -> NSColor {
        let hash = image.utf8.reduce(0) { value, byte in
            value &* 31 &+ Int(byte)
        }
        let index = Int(UInt(bitPattern: hash) % UInt(palette.count))
        return palette[index]
    }

    private static func color(for state: ContainerState) -> NSColor {
        switch state {
        case .running: .systemGreen
        case .stopped: .secondaryLabelColor
        case .restarting, .paused: .systemOrange
        case .dead: .systemRed
        }
    }

    private func showFallbackIcon() {
        showsRemoteIcon = false
        containerImageView.image = NSImage(
            systemSymbolName: "shippingbox",
            accessibilityDescription: nil
        )
        containerImageView.contentTintColor = fallbackColor
    }

    private func updateColors() {
        let isSelected = backgroundStyle == .emphasized
        nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        imageLabel.textColor =
            isSelected
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
            : .secondaryLabelColor
        linkButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        toggleButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        deleteButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        containerImageView.contentTintColor = showsRemoteIcon ? nil : fallbackColor
        statusDot.layer?.borderWidth = 2
        statusDot.layer?.borderColor =
            (isSelected ? NSColor.controlAccentColor : NSColor.textBackgroundColor).cgColor
    }

    private func address(for port: PortMapping?) -> String {
        guard let port else { return hostDomain }
        let displayPort = useDNS ? port.containerPort : port.hostPort
        return useDNS && displayPort == 80
            ? hostDomain
            : "\(hostDomain):\(displayPort)"
    }

    @objc private func linkPressed() {
        guard !ports.isEmpty else { return }
        guard ports.count > 1 else {
            onOpenPort?(ports[0])
            return
        }

        let menu = NSMenu()
        for (index, port) in ports.enumerated() {
            let item = NSMenuItem(
                title: address(for: port),
                action: #selector(portPressed(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: linkButton.frame.minX, y: linkButton.frame.minY),
            in: self
        )
    }

    @objc private func portPressed(_ sender: NSMenuItem) {
        guard ports.indices.contains(sender.tag) else { return }
        onOpenPort?(ports[sender.tag])
    }

    @objc private func togglePressed() {
        onToggle?()
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
