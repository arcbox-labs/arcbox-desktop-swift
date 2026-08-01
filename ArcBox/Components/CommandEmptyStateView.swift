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

        let imageView = NSImageView(
            image: NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        imageView.symbolConfiguration = .init(pointSize: 32, weight: .regular)
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.setAccessibilityElement(false)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let promptLabel = NSTextField(labelWithString: prompt)
        promptLabel.font = .systemFont(ofSize: 11)
        promptLabel.textColor = .secondaryLabelColor

        let commandViews = commands.map(CommandView.init)
        let stack = NSStackView(views: [imageView, titleLabel, promptLabel] + commandViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: titleLabel)
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel(title)
        stack.setAccessibilityHelp(prompt)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
        ])
        NSLayoutConstraint.activate(
            commandViews.map {
                $0.widthAnchor.constraint(equalTo: stack.widthAnchor)
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
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyCommand)
        copyButton.toolTip = "Copy command"
        copyButton.setAccessibilityLabel("Copy command: \(command.command)")

        let commandRow = NSStackView(views: [commandLabel, copyButton])
        commandRow.orientation = .horizontal
        commandRow.alignment = .centerY
        commandRow.spacing = 8

        let descriptionLabel = NSTextField(labelWithString: command.description)
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [commandRow, descriptionLabel])
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
            commandRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            descriptionLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copyButton.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        )
        copyButton.contentTintColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: nil
            )
            self?.copyButton.contentTintColor = nil
        }
    }
}
