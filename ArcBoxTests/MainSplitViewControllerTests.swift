import AppKit
import XCTest

@testable import ArcBox

@MainActor
final class MainSplitViewControllerTests: XCTestCase {
    func testSidebarFloorAndContentReplacement() {
        let sidebar = NSViewController()
        sidebar.view = NSView()
        let content = NSViewController()
        content.view = NSView()
        let replacement = NSViewController()
        replacement.view = NSView()

        let controller = MainSplitViewController(
            sidebarViewController: sidebar,
            contentViewController: content
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        controller.view.layoutSubtreeIfNeeded()
        controller.splitView.setPosition(0, ofDividerAt: 0)
        controller.splitView.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.splitViewItems.count, 2)
        XCTAssertTrue(controller.splitViewItems[1].viewController === content)
        XCTAssertEqual(sidebar.view.frame.width, 180, accuracy: 1)

        controller.replaceContentViewController(replacement)

        XCTAssertEqual(controller.splitViewItems.count, 2)
        XCTAssertTrue(controller.splitViewItems[0].viewController === sidebar)
        XCTAssertTrue(controller.splitViewItems[1].viewController === replacement)
    }
}
