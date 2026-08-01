import AppKit
import XCTest

@testable import ArcBox

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testDefaultFrameAndChromeMatchSwiftUIWindow() throws {
        let autosaveName = "ArcBoxTests.MainWindow.\(UUID().uuidString)"
        defer { removeSavedFrame(named: autosaveName) }

        let controller = MainWindowController(
            contentViewController: NSViewController(),
            frameAutosaveName: autosaveName
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.frame.size, NSSize(width: 1_200, height: 800))
        XCTAssertEqual(window.contentMinSize, NSSize(width: 900, height: 600))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertEqual(window.frameAutosaveName, autosaveName)
    }

    func testRestoresSavedFrame() throws {
        let autosaveName = "ArcBoxTests.MainWindow.\(UUID().uuidString)"
        defer { removeSavedFrame(named: autosaveName) }

        let savedFrame = NSRect(x: 80, y: 80, width: 1_040, height: 720)
        let source = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        source.setFrame(savedFrame, display: false)
        source.saveFrame(usingName: autosaveName)

        let controller = MainWindowController(
            contentViewController: NSViewController(),
            frameAutosaveName: autosaveName
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.frame.origin.x, savedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, savedFrame.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, savedFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, savedFrame.height, accuracy: 1)
    }

    private func removeSavedFrame(named name: String) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }
}
