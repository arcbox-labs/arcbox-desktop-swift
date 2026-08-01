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
        controller.view.frame = NSRect(x: 0, y: 0, width: 180, height: 600)
        controller.view.layoutSubtreeIfNeeded()
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        let rows = (0..<outlineView.numberOfRows).map(outlineView.item(atRow:))

        XCTAssertEqual(rows.count, 15)
        XCTAssertEqual(rows.compactMap { $0 as? NavItem.Section }.count, 5)
        XCTAssertEqual(rows.compactMap { $0 as? NavItem }.count, 10)
        XCTAssertEqual(outlineView.item(atRow: outlineView.selectedRow) as? NavItem, .containers)
        XCTAssertEqual(outlineView.style, .sourceList)
        let nativeSourceList = NSOutlineView()
        nativeSourceList.style = .sourceList
        XCTAssertEqual(outlineView.rowHeight, nativeSourceList.rowHeight)

        let firstSection = try XCTUnwrap(outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true))
        XCTAssertEqual(findTextField(in: firstSection)?.stringValue, "System")

        let accountButton = try XCTUnwrap(
            findView(identifier: "SidebarAccountButton", in: controller.view)
        )
        let avatar = try XCTUnwrap(
            findView(identifier: "SidebarAccountAvatar", in: accountButton)
        )
        XCTAssertEqual(accountButton.frame.minX, 12, accuracy: 0.5)
        XCTAssertEqual(accountButton.frame.minY, 8, accuracy: 0.5)
        XCTAssertEqual(accountButton.frame.height, 36, accuracy: 0.5)
        XCTAssertEqual(avatar.frame.size, NSSize(width: 24, height: 24))
        XCTAssertFalse(containsSeparator(in: controller.view))

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

    @MainActor
    private func findView(identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        return view.subviews.lazy.compactMap {
            self.findView(identifier: identifier, in: $0)
        }.first
    }

    @MainActor
    private func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField {
            return textField
        }
        return view.subviews.lazy.compactMap(findTextField).first
    }

    @MainActor
    private func containsSeparator(in view: NSView) -> Bool {
        if let box = view as? NSBox, box.boxType == .separator {
            return true
        }
        return view.subviews.contains(where: containsSeparator)
    }
}
