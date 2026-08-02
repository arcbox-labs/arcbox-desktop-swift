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

    func testCloseBehaviorMatchesWindowPurpose() throws {
        var firstRunCloseRequested = false
        let firstRunController = OnboardingWindowController(
            contentViewController: NSViewController(),
            onClose: { firstRunCloseRequested = true }
        )
        let firstRunWindow = try XCTUnwrap(firstRunController.window)

        XCTAssertFalse(firstRunController.windowShouldClose(firstRunWindow))
        XCTAssertTrue(firstRunCloseRequested)

        let replayController = OnboardingWindowController(
            contentViewController: NSViewController(),
            allowsClosing: true,
            onClose: { XCTFail("replay close must not request app termination") }
        )
        let replayWindow = try XCTUnwrap(replayController.window)

        XCTAssertTrue(replayController.windowShouldClose(replayWindow))
    }
}
