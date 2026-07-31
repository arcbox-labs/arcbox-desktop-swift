import AppKit
import XCTest

@testable import ArcBox

/// Guards the invariant behind `ColumnWidth.contentMin`: at the narrowest the
/// content column is allowed to be, its toolbar items must still sit over the
/// column itself.
///
/// The window toolbar cannot compress a column's section below its intrinsic
/// width. Let the column go narrower than that and AppKit stops moving the
/// section with the split divider, so the list's sort/add buttons end up
/// floating over the detail column. Adding a third `.primaryAction` item to a
/// list column is what would break this.
@MainActor
final class ContentViewColumnLayoutTests: XCTestCase {

    func testContentToolbarItemsStayOverTheirColumnAtTheNarrowestWidth() throws {
        let window = try mainWindow()
        let splitView = try XCTUnwrap(
            findSplitView(in: window.contentView), "no NSSplitView in the main window")
        XCTAssertEqual(splitView.arrangedSubviews.count, 3, "expected a three-column split view")

        let originalPosition = splitView.arrangedSubviews[1].frame.maxX
        defer {
            splitView.setPosition(originalPosition, ofDividerAt: 1)
            pumpRunLoop()
        }

        // 0 collapses onto whatever floor NavigationSplitView enforces.
        splitView.setPosition(0, ofDividerAt: 1)
        pumpRunLoop()

        let panes = splitView.arrangedSubviews.map { $0.convert($0.bounds, to: nil) }
        let dividerX = panes[2].minX
        let contentWidth = dividerX - panes[0].width

        XCTAssertEqual(
            contentWidth, ColumnWidth.contentMin, accuracy: 2,
            "the content column floor is not ColumnWidth.contentMin")

        let items = contentColumnItemFrames(in: window)
        XCTAssertFalse(
            items.isEmpty,
            "no content-column toolbar items found; items: \(toolbarDump(window))")

        let overhang = items.map { $0.maxX - dividerX }.max() ?? 0
        XCTAssertLessThanOrEqual(
            overhang, 0,
            """
            content-column toolbar items overhang the split divider by \(overhang)pt at the \
            column floor (\(contentWidth)pt): they render over the detail column instead of \
            over the list. The column's toolbar section no longer fits — raise \
            ColumnWidth.contentMin above it, or drop a toolbar item.
            """)
    }

    // MARK: - Helpers

    /// Toolbar items SwiftUI emits for the content column sit between the
    /// tracking separators for split divider 0 (sidebar|content) and 1
    /// (content|detail).
    private func contentColumnItemFrames(in window: NSWindow) -> [NSRect] {
        guard let items = window.toolbar?.items else { return [] }
        let identifiers = items.map(\.itemIdentifier.rawValue)
        guard
            let start = identifiers.firstIndex(where: { $0.hasSuffix("splitViewSeparator-0") }),
            let end = identifiers.firstIndex(where: { $0.hasSuffix("splitViewSeparator-1") }),
            start < end
        else { return [] }

        return items[(start + 1)..<end].compactMap { item in
            guard let view = item.view, let superview = view.superview else { return nil }
            let frame = superview.convert(view.frame, to: nil)
            return frame.width > 0 ? frame : nil
        }
    }

    private func toolbarDump(_ window: NSWindow) -> String {
        (window.toolbar?.items ?? [])
            .map { "\($0.itemIdentifier.rawValue)[view: \($0.view == nil ? "nil" : "yes")]" }
            .joined(separator: ", ")
    }

    private func mainWindow() throws -> NSWindow {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let window = NSApp.windows.first(where: {
                $0.toolbar != nil && findSplitView(in: $0.contentView) != nil
            }) {
                // Toolbar item views are only realized for an on-screen window.
                window.makeKeyAndOrderFront(nil)
                pumpRunLoop()
                return window
            }
            pumpRunLoop()
        }
        throw XCTSkip(
            "main window with a toolbar never appeared — this environment cannot host it")
    }

    private func findSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView, split.arrangedSubviews.count == 3 { return split }
        for subview in view.subviews {
            if let split = findSplitView(in: subview) { return split }
        }
        return nil
    }

    private func pumpRunLoop(for duration: TimeInterval = 0.3) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}
