import AppKit

@MainActor
final class CommandEmptyStateView: NSView {
    struct Command {
        let command: String
        let description: String
    }

    init(
        systemImage: String,
        title: String,
        prompt: String,
        commands: [Command]
    ) {
        super.init(frame: .zero)

        let iconBox = NSBox()
        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 32
        iconBox.fillColor = .quaternarySystemFill
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(
            image: NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        imageView.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(imageView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center

        let promptLabel = NSTextField(labelWithString: prompt)
        promptLabel.font = .systemFont(ofSize: 11)
        promptLabel.textColor = .secondaryLabelColor

        let commandViews = commands.map(CommandView.init)
        let contentStack = NSStackView(views: [promptLabel] + commandViews)
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let card = NSBox()
        card.boxType = .custom
        card.borderWidth = 0
        card.cornerRadius = 10
        card.fillColor = .quaternarySystemFill
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        let stack = NSStackView(views: [iconBox, titleLabel, card])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel(title)
        stack.setAccessibilityHelp(prompt)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            iconBox.widthAnchor.constraint(equalToConstant: 64),
            iconBox.heightAnchor.constraint(equalToConstant: 64),
            imageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        NSLayoutConstraint.activate(
            commandViews.map {
                $0.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
            })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class CommandView: NSView {
    private let command: String
    private let copyButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isCopied = false

    init(_ command: CommandEmptyStateView.Command) {
        self.command = command.command
        super.init(frame: .zero)

        let commandLabel = NSTextField(labelWithString: command.command)
        commandLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandLabel.isSelectable = true
        commandLabel.lineBreakMode = .byTruncatingMiddle
        commandLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
        copyButton.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.alphaValue = 0
        copyButton.target = self
        copyButton.action = #selector(copyCommand)
        copyButton.toolTip = "Copy command"
        copyButton.setAccessibilityLabel("Copy command: \(command.command)")

        let commandRow = NSStackView(views: [commandLabel, copyButton])
        commandRow.orientation = .horizontal
        commandRow.alignment = .centerY
        commandRow.spacing = 8
        commandRow.translatesAutoresizingMaskIntoConstraints = false

        let commandBox = NSBox()
        commandBox.boxType = .custom
        commandBox.borderWidth = 0
        commandBox.cornerRadius = 4
        commandBox.fillColor = .textBackgroundColor
        commandBox.addSubview(commandRow)

        let descriptionLabel = NSTextField(labelWithString: command.description)
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [commandBox, descriptionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            commandBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            commandRow.leadingAnchor.constraint(equalTo: commandBox.leadingAnchor, constant: 8),
            commandRow.trailingAnchor.constraint(equalTo: commandBox.trailingAnchor),
            commandRow.topAnchor.constraint(equalTo: commandBox.topAnchor),
            commandRow.bottomAnchor.constraint(equalTo: commandBox.bottomAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
            descriptionLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateCopyButton()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateCopyButton()
    }

    @objc private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copyButton.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        )
        copyButton.contentTintColor = .systemGreen
        isCopied = true
        updateCopyButton()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: nil
            )
            copyButton.contentTintColor = .secondaryLabelColor
            isCopied = false
            updateCopyButton()
        }
    }

    private func updateCopyButton() {
        copyButton.alphaValue = isHovered || isCopied ? 1 : 0
    }
}
