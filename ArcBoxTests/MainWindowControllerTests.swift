import AppKit
import SwiftUI
import XCTest

@testable import ArcBox

@MainActor
final class MainWindowControllerTests: XCTestCase {
    func testDefaultFrameAndChromeMatchSwiftUIWindow() throws {
        let autosaveName = "ArcBoxTests.MainWindow.\(UUID().uuidString)"
        defer { removeSavedFrame(named: autosaveName) }

        let host = NSHostingController(
            rootView: Color.clear
                .frame(minWidth: 900, minHeight: 600)
                .toolbar {
                    ToolbarItem {
                        Button("Action") {}
                    }
                }
        )
        host.sceneBridgingOptions = .all

        let controller = MainWindowController(
            contentViewController: host,
            frameAutosaveName: autosaveName
        )
        controller.showWindow(nil)
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        waitForToolbarLayout(in: window)
        let chromeHeight = window.frame.height - window.contentLayoutRect.height

        XCTAssertEqual(window.frame.size, NSSize(width: 1_200, height: 800))
        XCTAssertEqual(window.minSize.width, 900, accuracy: 1)
        XCTAssertEqual(window.minSize.height, 600 + chromeHeight, accuracy: 1)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .visible)
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

    private func waitForToolbarLayout(in window: NSWindow) {
        var lastContentLayoutRect = NSRect.zero
        var stablePasses = 0

        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            let contentLayoutRect = window.contentLayoutRect
            if window.toolbar != nil, contentLayoutRect == lastContentLayoutRect {
                stablePasses += 1
                if stablePasses == 2 {
                    return
                }
            } else {
                stablePasses = 0
            }
            lastContentLayoutRect = contentLayoutRect
        }

        XCTFail("SwiftUI toolbar did not settle")
    }
}
