import AppKit

@MainActor
final class AboutViewController: NSViewController {
    let changelogContent = NSStackView()
    private var releasesTask: Task<Void, Never>?

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let contentStack = verticalStack(
            [
                headerSection(),
                versionInfoSection(),
                whatsNewSection(),
                helpSection(),
                footerSection(),
            ], spacing: 20)
        documentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
        ])

        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        releasesTask = Task { [weak self] in
            let releases = await Task.detached(priority: .utility) {
                ChangelogParser.loadFromBundle(limit: 3)
            }.value
            guard !Task.isCancelled else { return }
            self?.showReleases(releases)
        }
    }

    deinit {
        releasesTask?.cancel()
    }

    func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.alignment = .width
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func label(
        _ text: String,
        font: NSFont,
        color: NSColor = .labelColor,
        alignment: NSTextAlignment = .natural
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = alignment
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func padded(_ content: NSView, horizontal: CGFloat, vertical: CGFloat) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontal),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontal),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vertical),
        ])
        return container
    }

    func card(containing content: NSView, cornerRadius: CGFloat = 8) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.borderWidth = 0.5
        box.cornerRadius = cornerRadius
        box.fillColor = .controlBackgroundColor
        box.titlePosition = .noTitle
        box.contentViewMargins = .zero
        box.contentView = content
        return box
    }

    func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
