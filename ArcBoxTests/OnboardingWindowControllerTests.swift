import AppKit
import XCTest

@testable import ArcBox

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {
    func testWindowIsFixedPurposeAndDoesNotRestore() throws {
        let controller = OnboardingWindowController(
            contentViewController: NSViewController(),
            onClose: {}
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.frame.size, OnboardingWindowController.windowSize)
        XCTAssertEqual(window.title, "Welcome to ArcBox")
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.styleMask.contains(.miniaturizable))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isRestorable)
        XCTAssertEqual(window.tabbingMode, .disallowed)
    }
}
