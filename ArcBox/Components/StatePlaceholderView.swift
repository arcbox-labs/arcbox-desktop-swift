import AppKit

@MainActor
final class StatePlaceholderView: NSView {
    enum State {
        case loading(title: String)
        case empty(systemImage: String, title: String, message: String?)
        case error(title: String, message: String?)
    }

    struct Action {
        let title: String
        let handler: @MainActor () -> Void
    }

    private let progressIndicator = NSProgressIndicator()
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private let stackView = NSStackView()
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
        imageView.isHidden = true
        messageLabel.isHidden = true

        let title: String
        let message: String?

        switch state {
        case .loading(let loadingTitle):
            title = loadingTitle
            message = nil
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        case .empty(let systemImage, let emptyTitle, let emptyMessage):
            title = emptyTitle
            message = emptyMessage
            showImage(systemName: systemImage, color: .tertiaryLabelColor)
        case .error(let errorTitle, let errorMessage):
            title = errorTitle
            message = errorMessage
            showImage(systemName: "exclamationmark.triangle", color: .systemRed)
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
        actionButton.setAccessibilityLabel(action?.title)
    }

    private func setUp() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true

        imageView.imageScaling = .scaleProportionallyDown
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        imageView.setAccessibilityElement(false)

        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.maximumNumberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        actionButton.target = self
        actionButton.action = #selector(performAction)

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.setAccessibilityElement(true)
        stackView.setAccessibilityRole(.group)
        stackView.setViews(
            [progressIndicator, imageView, titleLabel, messageLabel, actionButton],
            in: .center
        )
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            imageView.widthAnchor.constraint(equalToConstant: 48),
            imageView.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }

    private func showImage(systemName: String, color: NSColor) {
        imageView.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        imageView.contentTintColor = color
        imageView.isHidden = false
    }

    @objc private func performAction() {
        actionHandler?()
    }
}
