import AppKit

@MainActor
protocol ResourceListActionDisplaying: AnyObject {
    func setShowsActions(_ showsActions: Bool)
}

@MainActor
final class ResourceListRowView: NSTableRowView {
    private let horizontalInset: CGFloat
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(horizontalInset: CGFloat) {
        self.horizontalInset = horizontalInset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            updatePresentation()
        }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected || isHovered else { return }

        let color =
            isSelected
            ? NSColor.controlAccentColor
            : NSColor.labelColor.withAlphaComponent(0.03)
        color.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: horizontalInset, dy: 0),
            xRadius: 6,
            yRadius: 6
        ).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}

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

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        updateActionVisibility()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updatePresentation()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updatePresentation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func updatePresentation() {
        needsDisplay = true
        updateActionVisibility()
    }

    private func updateActionVisibility() {
        let showsActions = isHovered || isSelected
        for case let display as ResourceListActionDisplaying in subviews {
            display.setShowsActions(showsActions)
        }
    }
}

@MainActor
final class ResourceActionButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        imagePosition = .imageOnly
        symbolConfiguration = .init(pointSize: 12, weight: .regular)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let hoverTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(hoverTrackingArea)
        self.hoverTrackingArea = hoverTrackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.labelColor.withAlphaComponent(0.03).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }
}
