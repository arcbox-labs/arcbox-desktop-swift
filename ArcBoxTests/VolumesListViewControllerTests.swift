import AppKit
import XCTest

@testable import ArcBox

final class VolumesListViewControllerTests: XCTestCase {
    @MainActor
    func testRepeatedModelChangesUpdateRowsAndSelectionWithoutRetainingController() async throws {
        let viewModel = VolumesViewModel()
        viewModel.loadState = .loaded

        var controller: VolumesListViewController? = VolumesListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading volumes…",
            onRetry: {},
            onDelete: { _ in }
        )
        weak var weakController = controller

        let tableView = try XCTUnwrap(findTableView(in: controller?.view))
        XCTAssertTrue(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertEqual(tableView.numberOfRows, 0)

        viewModel.volumes = [
            volume(name: "data", inUse: true),
            volume(name: "cache", inUse: false),
        ]
        try await waitUntil { tableView.numberOfRows == 4 }

        XCTAssertFalse(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertEqual(tableView.numberOfRows, 4)

        viewModel.searchText = "cache"
        try await waitUntil { tableView.numberOfRows == 2 }
        XCTAssertEqual(tableView.numberOfRows, 2)

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 4 }
        viewModel.selectedID = "cache"
        try await waitUntil { tableView.selectedRow == 3 }
        XCTAssertEqual(tableView.selectedRow, 3)

        viewModel.searchText = "data"
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "cache")

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 4 && tableView.selectedRow == 3 }

        tableView.deselectAll(nil)
        XCTAssertNil(viewModel.selectedID)

        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "data")

        viewModel.volumes = [volume(name: "cache", inUse: false)]
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }

        controller = nil
        XCTAssertNil(weakController)

        viewModel.searchText = "cache"
        await Task.yield()
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out waiting for AppKit observation update")
    }

    @MainActor
    private func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView {
            return tableView
        }
        return view.subviews.lazy.compactMap(findTableView).first
    }

    private func volume(name: String, inUse: Bool) -> VolumeViewModel {
        VolumeViewModel(
            name: name,
            driver: "local",
            mountPoint: "/volumes/\(name)",
            sizeBytes: 1_000,
            createdAt: .distantPast,
            inUse: inUse,
            containerNames: inUse ? ["container"] : []
        )
    }
}
