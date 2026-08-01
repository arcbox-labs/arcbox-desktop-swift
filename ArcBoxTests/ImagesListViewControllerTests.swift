import AppKit
import XCTest

@testable import ArcBox

final class ImagesListViewControllerTests: XCTestCase {
    @MainActor
    func testStateSearchSelectionAndControllerLifetime() async throws {
        let viewModel = ImagesViewModel()
        var didRetry = false
        var controller: ImagesListViewController? = ImagesListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading images…",
            onRetry: { didRetry = true },
            onDelete: { _ in }
        )
        weak var weakController = controller

        let rootView = try XCTUnwrap(controller?.view)
        let tableView = try XCTUnwrap(findTableView(in: rootView))
        XCTAssertTrue(try XCTUnwrap(tableView.enclosingScrollView).isHidden)

        viewModel.loadState = .failed("Docker unavailable")
        try await waitUntil { self.visibleButton(titled: "Retry", in: rootView) != nil }
        visibleButton(titled: "Retry", in: rootView)?.performClick(nil)
        XCTAssertTrue(didRetry)

        viewModel.loadState = .loaded
        try await waitUntil { self.hasText("No images yet", in: rootView) }

        viewModel.images = [
            image(id: "nginx", repository: "nginx", inUse: true),
            image(id: "postgres", repository: "postgres", inUse: false),
            image(id: "redis", repository: "redis", inUse: false),
        ]
        try await waitUntil { tableView.numberOfRows == 5 }
        XCTAssertFalse(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertEqual(
            tableView.menu?.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Copy Name", "Copy ID", "Delete"]
        )

        let nginxRow = try XCTUnwrap(row(named: "nginx:latest", in: tableView))
        let nginxCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: nginxRow, makeIfNecessary: true)
        )
        let deleteButton = try XCTUnwrap(deleteButton(in: nginxCell))
        XCTAssertFalse(deleteButton.isHidden)
        XCTAssertTrue(deleteButton.isEnabled)

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0 && self.hasText("No Results", in: rootView)
        }

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 5 }
        tableView.selectRowIndexes(IndexSet(integer: nginxRow), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "nginx")

        viewModel.selectedID = "redis"
        try await waitUntil {
            tableView.selectedRow == self.row(named: "redis:latest", in: tableView)
        }

        viewModel.searchText = "nginx"
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "redis")

        viewModel.searchText = ""
        try await waitUntil {
            tableView.numberOfRows == 5
                && tableView.selectedRow == self.row(named: "redis:latest", in: tableView)
        }

        viewModel.images.removeAll { $0.id == "redis" }
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }

        controller = nil
        XCTAssertNil(weakController)

        viewModel.searchText = "nginx"
        await Task.yield()
    }

    @MainActor
    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(
            condition(),
            "Timed out waiting for AppKit observation update",
            file: file,
            line: line
        )
    }

    @MainActor
    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        return view.subviews.lazy.compactMap { self.findTableView(in: $0) }.first
    }

    @MainActor
    private func visibleButton(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title, !button.isHidden {
            return button
        }
        return view.subviews.lazy.compactMap {
            self.visibleButton(titled: title, in: $0)
        }.first
    }

    @MainActor
    private func hasText(_ text: String, in view: NSView) -> Bool {
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { self.hasText(text, in: $0) }
    }

    @MainActor
    private func row(named name: String, in tableView: NSTableView) -> Int? {
        (0..<tableView.numberOfRows).first { row in
            let cell =
                tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? NSTableCellView
            return cell?.textField?.stringValue == name
        }
    }

    @MainActor
    private func deleteButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
            button.identifier == NSUserInterfaceItemIdentifier("ImageDeleteButton")
        {
            return button
        }
        return view.subviews.lazy.compactMap { self.deleteButton(in: $0) }.first
    }

    private func image(
        id: String,
        repository: String,
        inUse: Bool
    ) -> ImageViewModel {
        ImageViewModel(
            id: id,
            dockerId: "sha256:\(id)",
            repository: repository,
            tag: "latest",
            sizeBytes: 1_000,
            createdAt: .distantPast,
            inUse: inUse,
            os: "linux",
            architecture: "arm64",
            iconURL: nil
        )
    }
}
