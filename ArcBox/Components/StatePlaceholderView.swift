import AppKit

@MainActor
final class StatePlaceholderView: NSView {
    enum State {
        case loading(title: String?)
        case empty(systemImage: String, title: String, message: String?)
        case error(title: String, message: String?)
        case noSelection(systemImage: String, title: String)
        case plain(title: String)
    }

    struct Action {
        let title: String
        let handler: @MainActor () -> Void
    }

    private let progressIndicator = NSProgressIndicator()
    private let imageContainer = NSBox()
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private let contentContainer = NSBox()
    private let contentStack = NSStackView()
    private let stackView = NSStackView()
    private var imageContainerSize: [NSLayoutConstraint] = []
    private var imageViewSize: [NSLayoutConstraint] = []
    private var contentInsets: [NSLayoutConstraint] = []
    private var actionHandler: (@MainActor () -> Void)?

    init(state: State, action: Action? = nil) {
        super.init(frame: .zero)
        setUp()
        update(state, action: action)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: State, action: Action? = nil) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        imageContainer.isHidden = true
        contentContainer.isHidden = true
        contentContainer.fillColor = .clear
        contentInsets.forEach { $0.constant = 0 }
        imageContainerSize.forEach { $0.constant = 64 }
        imageViewSize.forEach { $0.constant = 48 }
        titleLabel.isHidden = false

        let title: String
        let message: String?

        switch state {
        case .loading(let loadingTitle):
            title = loadingTitle ?? ""
            message = nil
            titleLabel.isHidden = loadingTitle == nil
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            titleLabel.font = .systemFont(ofSize: 13)
            titleLabel.textColor = .secondaryLabelColor
        case .empty(let systemImage, let emptyTitle, let emptyMessage):
            title = emptyTitle
            message = emptyMessage
            showImage(
                systemName: systemImage,
                color: .tertiaryLabelColor,
                pointSize: 32,
                backgroundColor: .clear
            )
            imageContainerSize.forEach { $0.constant = 32 }
            imageViewSize.forEach { $0.constant = 32 }
            titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            titleLabel.textColor = .labelColor
        case .error(let errorTitle, let errorMessage):
            title = errorTitle
            message = errorMessage
            showImage(
                systemName: "exclamationmark.triangle",
                color: .tertiaryLabelColor,
                pointSize: 26,
                backgroundColor: .quaternarySystemFill
            )
            titleLabel.font = .systemFont(ofSize: 13)
            titleLabel.textColor = .secondaryLabelColor
            contentContainer.fillColor = .quaternarySystemFill
            contentInsets[0].constant = 16
            contentInsets[1].constant = -16
            contentInsets[2].constant = 16
            contentInsets[3].constant = -16
        case .noSelection(let systemImage, let selectionTitle):
            title = selectionTitle
            message = nil
            showImage(
                systemName: systemImage,
                color: .tertiaryLabelColor,
                pointSize: 32,
                backgroundColor: .clear
            )
            imageContainerSize.forEach { $0.constant = 32 }
            imageViewSize.forEach { $0.constant = 32 }
            titleLabel.font = .systemFont(ofSize: 15)
            titleLabel.textColor = .secondaryLabelColor
        case .plain(let plainTitle):
            title = plainTitle
            message = nil
            titleLabel.font = .systemFont(ofSize: 13)
            titleLabel.textColor = .secondaryLabelColor
        }

        titleLabel.stringValue = title
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        progressIndicator.setAccessibilityLabel(title)
        stackView.setAccessibilityLabel(title)
        stackView.setAccessibilityHelp(message)

        actionHandler = action?.handler
        actionButton.title = action?.title ?? ""
        actionButton.isHidden = action == nil
        actionButton.controlSize = state.isError ? .small : .regular
        actionButton.setAccessibilityLabel(action?.title)
        contentContainer.isHidden = message == nil && action == nil
        stackView.spacing = state.isError ? 16 : 12
    }

    private func setUp() {
        progressIndicator.identifier = NSUserInterfaceItemIdentifier("StatePlaceholderProgress")
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true

        imageContainer.boxType = .custom
        imageContainer.borderWidth = 0
        imageContainer.cornerRadius = 32
        imageContainer.fillColor = .clear
        imageContainer.translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)

        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping

        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(performAction)

        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 12
        contentStack.setViews([messageLabel, actionButton], in: .center)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.boxType = .custom
        contentContainer.borderWidth = 0
        contentContainer.cornerRadius = 10
        contentContainer.fillColor = .clear
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentStack)

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.setAccessibilityElement(true)
        stackView.setAccessibilityRole(.group)
        stackView.setViews(
            [progressIndicator, imageContainer, titleLabel, contentContainer],
            in: .center
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            imageView.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
        imageContainerSize = [
            imageContainer.widthAnchor.constraint(equalToConstant: 64),
            imageContainer.heightAnchor.constraint(equalToConstant: 64),
        ]
        imageViewSize = [
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
        ]
        NSLayoutConstraint.activate(imageContainerSize + imageViewSize)
        contentInsets = [
            contentStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(contentInsets)
    }

    private func showImage(
        systemName: String,
        color: NSColor,
        pointSize: CGFloat,
        backgroundColor: NSColor
    ) {
        imageView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        imageView.symbolConfiguration = .init(pointSize: pointSize, weight: .regular)
        imageView.contentTintColor = color
        imageContainer.fillColor = backgroundColor
        imageContainer.isHidden = false
    }

    @objc private func performAction() {
        actionHandler?()
    }
}

extension StatePlaceholderView.State {
    fileprivate var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}
