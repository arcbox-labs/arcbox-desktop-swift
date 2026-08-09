import AppKit
import XCTest

@testable import ArcBox

/// Guards the toolbar geometry of the single three-column main-window split.
@MainActor
final class ContentViewColumnLayoutTests: XCTestCase {
    func testContentToolbarItemsStayOverTheirColumnAtTheNarrowestWidth() throws {
        let window = try mainWindow()
        let splitView = try XCTUnwrap(
            findSplitView(in: window.contentView),
            "no three-column NSSplitView in the main window"
        )
        XCTAssertEqual(splitView.arrangedSubviews.count, 3)

        let originalPosition = splitView.arrangedSubviews[1].frame.maxX
        defer {
            splitView.setPosition(originalPosition, ofDividerAt: 1)
            pumpRunLoop()
        }

        splitView.setPosition(0, ofDividerAt: 1)
        pumpRunLoop()

        let panes = splitView.arrangedSubviews.map { $0.convert($0.bounds, to: nil) }
        let dividerX = panes[2].minX
        let contentWidth = dividerX - panes[0].width

        XCTAssertEqual(contentWidth, ColumnWidth.contentMin, accuracy: 2)

        let items = contentColumnItemFrames(in: window)
        XCTAssertFalse(items.isEmpty, "no content-column toolbar items found")

        let overhang = items.map { $0.maxX - dividerX }.max() ?? 0
        XCTAssertLessThanOrEqual(
            overhang,
            0,
            "content toolbar items overhang the detail column by \(overhang) pt"
        )
    }

    private func contentColumnItemFrames(in window: NSWindow) -> [NSRect] {
        guard let items = window.toolbar?.items else { return [] }
        let identifiers = items.map(\.itemIdentifier.rawValue)
        guard
            let start = identifiers.firstIndex(where: { $0.hasSuffix("splitViewSeparator-0") }),
            let end = identifiers.firstIndex(where: { $0.hasSuffix("splitViewSeparator-1") }),
            start < end
        else {
            return []
        }

        return items[(start + 1)..<end].compactMap { item in
            guard let view = item.view, let superview = view.superview else { return nil }
            let frame = superview.convert(view.frame, to: nil)
            return frame.width > 0 ? frame : nil
        }
    }

    private func mainWindow() throws -> NSWindow {
        let deadline = Date().addingTimeInterval(10)
        var found: NSWindow?
        while found == nil, Date() < deadline {
            found = NSApp.windows.first {
                $0.toolbar != nil && findSplitView(in: $0.contentView) != nil
            }
            if found == nil {
                pumpRunLoop()
            }
        }

        let window = try XCTUnwrap(found, "the app's three-column main window never appeared")
        window.makeKeyAndOrderFront(nil)
        pumpRunLoop()
        return window
    }

    private func findSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let splitView = view as? NSSplitView, splitView.arrangedSubviews.count == 3 {
            return splitView
        }
        return view.subviews.lazy.compactMap { self.findSplitView(in: $0) }.first
    }

    private func pumpRunLoop(for duration: TimeInterval = 0.3) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}
