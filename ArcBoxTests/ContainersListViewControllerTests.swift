import AppKit
import XCTest

@testable import ArcBox

final class ContainersListViewControllerTests: XCTestCase {
    @MainActor
    func testStatesHierarchyAndSearch() async throws {
        let viewModel = ContainersViewModel()
        var didRetry = false
        let controller = makeController(
            viewModel: viewModel,
            onRetry: { didRetry = true }
        )

        let rootView = controller.view
        let outlineView = try XCTUnwrap(findOutlineView(in: rootView))
        XCTAssertTrue(try XCTUnwrap(outlineView.enclosingScrollView).isHidden)

        viewModel.loadState = .failed("Docker unavailable")
        try await waitUntil { self.visibleButton(titled: "Retry", in: rootView) != nil }
        visibleButton(titled: "Retry", in: rootView)?.performClick(nil)
        XCTAssertTrue(didRetry)

        viewModel.loadState = .loaded
        try await waitUntil { self.hasText("No containers yet", in: rootView) }

        viewModel.expandedGroups = ["active", "idle"]
        viewModel.containers = hierarchyContainers()
        try await waitUntil { outlineView.numberOfRows == 9 }
        XCTAssertFalse(try XCTUnwrap(outlineView.enclosingScrollView).isHidden)
        for title in ["In Use", "active", "web", "db", "solo", "Stopped", "idle", "worker", "sleeping"] {
            XCTAssertNotNil(row(named: title, in: outlineView))
        }

        viewModel.searchText = "missing"
        try await waitUntil {
            outlineView.numberOfRows == 0
                && self.hasText("No Results", in: rootView)
        }
    }

    @MainActor
    func testObservationDoesNotRetainController() async {
        let viewModel = ContainersViewModel()
        weak var weakController: ContainersListViewController?

        autoreleasepool {
            var controller: ContainersListViewController? = makeController(viewModel: viewModel)
            _ = controller?.view
            weakController = controller
            controller = nil
        }

        XCTAssertNil(weakController)
        viewModel.searchText = ""
        await Task.yield()
    }

    @MainActor
    func testSelectionSurvivesCollapseAndSearchUntilSourceIsRemoved() async throws {
        let viewModel = ContainersViewModel()
        viewModel.loadState = .loaded
        viewModel.expandedGroups = ["active"]
        viewModel.containers = [
            container(id: "web", name: "web", state: .running, project: "active"),
            container(id: "db", name: "db", state: .stopped, project: "active"),
        ]
        var selectedIDs: [String] = []
        let controller = makeController(
            viewModel: viewModel,
            onSelect: { selectedIDs.append($0) }
        )
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        try await waitUntil { outlineView.numberOfRows == 4 }

        outlineView.selectRowIndexes(
            IndexSet(integer: try XCTUnwrap(row(named: "web", in: outlineView))),
            byExtendingSelection: false
        )
        try await waitUntil {
            viewModel.selectedID == "web" && selectedIDs == ["web"]
        }

        viewModel.toggleGroup("active")
        try await waitUntil { outlineView.numberOfRows == 2 && outlineView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "web")

        viewModel.toggleGroup("active")
        try await waitUntil {
            outlineView.numberOfRows == 4
                && outlineView.selectedRow == self.row(named: "web", in: outlineView)
        }

        viewModel.searchText = "db"
        try await waitUntil { outlineView.numberOfRows == 3 && outlineView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "web")

        viewModel.searchText = ""
        try await waitUntil {
            outlineView.selectedRow == self.row(named: "web", in: outlineView)
        }

        viewModel.containers.removeAll { $0.id == "web" }
        try await waitUntil { viewModel.selectedID == nil && outlineView.selectedRow == -1 }
    }

    @MainActor
    func testUpdatedCallbacksAndBusyActionsRejectStaleCells() async throws {
        let viewModel = ContainersViewModel()
        viewModel.loadState = .loaded
        viewModel.expandedGroups = ["active"]
        viewModel.containers = hierarchyContainers()
        var oldToggleIDs: [String] = []
        var newToggleIDs: [String] = []
        var groupCalls: [(String, [String])] = []
        let controller = makeController(
            viewModel: viewModel,
            onToggle: { oldToggleIDs.append($0) }
        )
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        try await waitUntil { outlineView.numberOfRows == 8 }

        let soloCell = try cell(named: "solo", in: outlineView)
        let soloToggle = try XCTUnwrap(
            button("ContainerToggleButton", in: soloCell)
        )
        soloToggle.performClick(nil)
        XCTAssertEqual(oldToggleIDs, ["solo"])

        controller.update(
            loadingTitle: "Loading containers…",
            useDNS: false,
            actions: .init(
                retry: {},
                select: { _ in },
                toggle: { newToggleIDs.append($0) },
                delete: { _ in },
                toggleGroup: { groupCalls.append(($0, $1)) },
                deleteGroup: { _, _ in }
            )
        )
        soloToggle.performClick(nil)
        XCTAssertEqual(newToggleIDs, ["solo"])

        viewModel.setTransitioning("solo", true)
        soloToggle.performClick(nil)
        XCTAssertEqual(newToggleIDs, ["solo"])

        let groupCell = try cell(named: "active", in: outlineView)
        let groupToggle = try XCTUnwrap(
            button("ContainerGroupToggleButton", in: groupCell)
        )
        viewModel.setTransitioning("web", true)
        groupToggle.performClick(nil)
        XCTAssertTrue(groupCalls.isEmpty)

        viewModel.setTransitioning("web", false)
        viewModel.searchText = "web"
        try await waitUntil { outlineView.numberOfRows == 3 }
        let filteredGroupCell = try cell(named: "active", in: outlineView)
        try XCTUnwrap(
            button("ContainerGroupToggleButton", in: filteredGroupCell)
        ).performClick(nil)
        XCTAssertEqual(groupCalls.count, 1)
        XCTAssertEqual(groupCalls[0].0, "active")
        XCTAssertEqual(groupCalls[0].1, ["web"])
    }

    @MainActor
    private func makeController(
        viewModel: ContainersViewModel,
        onRetry: @escaping @MainActor () -> Void = {},
        onSelect: @escaping @MainActor (String) -> Void = { _ in },
        onToggle: @escaping @MainActor (String) -> Void = { _ in }
    ) -> ContainersListViewController {
        ContainersListViewController(
            viewModel: viewModel,
            loadingTitle: "Loading containers…",
            useDNS: false,
            actions: .init(
                retry: onRetry,
                select: onSelect,
                toggle: onToggle,
                delete: { _ in },
                toggleGroup: { _, _ in },
                deleteGroup: { _, _ in }
            )
        )
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
    private func findOutlineView(in view: NSView) -> NSOutlineView? {
        if let outlineView = view as? NSOutlineView {
            return outlineView
        }
        return view.subviews.lazy.compactMap {
            self.findOutlineView(in: $0)
        }.first
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
    private func row(named name: String, in outlineView: NSOutlineView) -> Int? {
        (0..<outlineView.numberOfRows).first { row in
            let cell =
                outlineView.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? NSTableCellView
            return cell?.textField?.stringValue == name
        }
    }

    @MainActor
    private func cell(
        named name: String,
        in outlineView: NSOutlineView
    ) throws -> NSView {
        let row = try XCTUnwrap(row(named: name, in: outlineView))
        return try XCTUnwrap(
            outlineView.view(atColumn: 0, row: row, makeIfNecessary: true)
        )
    }

    @MainActor
    private func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
            button.identifier == NSUserInterfaceItemIdentifier(identifier)
        {
            return button
        }
        return view.subviews.lazy.compactMap {
            self.button(identifier, in: $0)
        }.first
    }

    private func hierarchyContainers() -> [ContainerViewModel] {
        [
            container(id: "web", name: "web", state: .running, project: "active"),
            container(id: "db", name: "db", state: .stopped, project: "active"),
            container(id: "worker", name: "worker", state: .stopped, project: "idle"),
            container(id: "solo", name: "solo", state: .running),
            container(id: "sleeping", name: "sleeping", state: .stopped),
        ]
    }

    private func container(
        id: String,
        name: String,
        state: ContainerState,
        project: String? = nil
    ) -> ContainerViewModel {
        ContainerViewModel(
            id: id,
            name: name,
            image: "nginx:latest",
            state: state,
            ports: [],
            createdAt: .distantPast,
            composeProject: project,
            composeService: project == nil ? nil : name,
            labels: [:],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
    }
}
