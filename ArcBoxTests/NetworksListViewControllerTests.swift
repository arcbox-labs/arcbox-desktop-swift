import AppKit
import DockerClient
import XCTest

@testable import ArcBox

final class NetworksListViewControllerTests: XCTestCase {
    @MainActor
    func testDescendingSortUsesIDToBreakEqualValues() {
        let viewModel = NetworksViewModel()
        viewModel.sortAscending = false

        for ids in [["a", "b"], ["b", "a"]] {
            viewModel.networks = ids.map {
                network(id: $0, name: "same", containerCount: 0)
            }
            XCTAssertEqual(viewModel.sortedNetworks.map(\.id), ["b", "a"])
        }
    }

    @MainActor
    func testRemoveNetworkRejectsNamesAndUnknownIDsBeforeCallingDocker() async throws {
        let viewModel = NetworksViewModel()
        viewModel.networks = [
            network(id: "system-id", name: "host", containerCount: 0)
        ]
        let missingSocket = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let docker = DockerClient(socketPath: missingSocket)

        await viewModel.removeNetwork("host", docker: docker)
        try await docker.shutdown()

        XCTAssertNil(viewModel.lastError)
    }

    @MainActor
    func testStateSearchSelectionAndSystemNetworkDeletionRules() async throws {
        let viewModel = NetworksViewModel()
        var didRetry = false
        var controller: NetworksListViewController? = NetworksListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading networks…",
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
        try await waitUntil { self.hasText("No networks yet", in: rootView) }

        viewModel.networks = [
            network(id: "system", name: "host", containerCount: 0),
            network(id: "custom", name: "frontend", containerCount: 2),
            network(id: "unused", name: "backend", containerCount: 0),
        ]
        try await waitUntil { tableView.numberOfRows == 5 }
        XCTAssertFalse(try XCTUnwrap(tableView.enclosingScrollView).isHidden)

        let systemRow = try XCTUnwrap(row(named: "host", in: tableView))
        let systemCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: systemRow, makeIfNecessary: true)
        )
        let systemDeleteButton = try XCTUnwrap(deleteButton(in: systemCell))
        XCTAssertTrue(systemDeleteButton.isHidden)
        XCTAssertFalse(systemDeleteButton.isEnabled)

        let customRow = try XCTUnwrap(row(named: "frontend", in: tableView))
        let customCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: customRow, makeIfNecessary: true)
        )
        let customDeleteButton = try XCTUnwrap(deleteButton(in: customCell))
        XCTAssertFalse(customDeleteButton.isHidden)
        XCTAssertTrue(customDeleteButton.isEnabled)

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0 && self.hasText("No Results", in: rootView)
        }

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 5 }
        tableView.selectRowIndexes(IndexSet(integer: systemRow), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "system")

        viewModel.selectedID = "custom"
        try await waitUntil {
            tableView.selectedRow == self.row(named: "frontend", in: tableView)
        }

        viewModel.searchText = "host"
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "custom")

        viewModel.searchText = ""
        try await waitUntil {
            tableView.numberOfRows == 5
                && tableView.selectedRow == self.row(named: "frontend", in: tableView)
        }

        viewModel.networks.removeAll { $0.id == "custom" }
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }

        controller = nil
        XCTAssertNil(weakController)

        viewModel.searchText = "host"
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
            button.identifier == NSUserInterfaceItemIdentifier("NetworkDeleteButton")
        {
            return button
        }
        return view.subviews.lazy.compactMap { self.deleteButton(in: $0) }.first
    }

    private func network(
        id: String,
        name: String,
        containerCount: Int
    ) -> NetworkViewModel {
        NetworkViewModel(
            id: id,
            name: name,
            driver: "bridge",
            scope: "local",
            createdAt: .distantPast,
            internal: false,
            attachable: false,
            containerCount: containerCount
        )
    }
}
