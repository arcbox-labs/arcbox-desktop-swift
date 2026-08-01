import AppKit
import XCTest

@testable import ArcBox

final class SidebarViewControllerTests: XCTestCase {
    @MainActor
    func testRowsAndSelectionSynchronization() throws {
        var selections: [NavItem] = []
        let controller = SidebarViewController(
            selection: .containers,
            onSelect: { selections.append($0) },
            onAccount: {}
        )

        controller.loadView()
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        let rows = (0..<outlineView.numberOfRows).map(outlineView.item(atRow:))

        XCTAssertEqual(rows.count, 15)
        XCTAssertEqual(rows.compactMap { $0 as? NavItem.Section }.count, 5)
        XCTAssertEqual(rows.compactMap { $0 as? NavItem }.count, 10)
        XCTAssertEqual(outlineView.item(atRow: outlineView.selectedRow) as? NavItem, .containers)

        let imagesRow = try XCTUnwrap(
            rows.firstIndex { $0 as? NavItem == .images }
        )
        outlineView.selectRowIndexes(
            IndexSet(integer: imagesRow),
            byExtendingSelection: false
        )
        XCTAssertEqual(selections, [.images])

        controller.select(.volumes)
        XCTAssertEqual(outlineView.item(atRow: outlineView.selectedRow) as? NavItem, .volumes)
        XCTAssertEqual(selections, [.images])
    }

    @MainActor
    private func findOutlineView(in view: NSView) -> NSOutlineView? {
        if let outlineView = view as? NSOutlineView {
            return outlineView
        }
        return view.subviews.lazy.compactMap(findOutlineView).first
    }
}
