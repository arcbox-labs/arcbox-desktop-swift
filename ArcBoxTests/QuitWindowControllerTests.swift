import AppKit
import AuthenticationServices
import XCTest

@testable import ArcBox

@MainActor
final class QuitWindowControllerTests: XCTestCase {
    func testQuitCardIsTheOnlyNonInteractiveWindowSurface() throws {
        let controller = QuitWindowController()
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.frame.size, QuitWindowController.cardSize)
        XCTAssertEqual(window.styleMask, .borderless)
        XCTAssertEqual(window.level, .modalPanel)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isMovable)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertNil(window.standardWindowButton(.closeButton))
        XCTAssertNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNil(window.standardWindowButton(.zoomButton))
    }
}

@MainActor
final class WebAuthenticationControllerTests: XCTestCase {
    func testAuthenticationCannotStartAfterTermination() async throws {
        let controller = WebAuthenticationController()
        controller.cancelForTermination()

        do {
            _ = try await controller.authenticate(
                using: XCTUnwrap(URL(string: "https://example.com")),
                callbackURLScheme: "arcbox"
            )
            XCTFail("Authentication started during app termination")
        } catch let error as ASWebAuthenticationSessionError {
            XCTAssertEqual(error.code, .canceledLogin)
        }
    }
}
