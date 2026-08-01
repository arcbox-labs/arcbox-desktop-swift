import AppKit
import XCTest

@testable import ArcBox

final class KubernetesListViewControllerTests: XCTestCase {
    @MainActor
    func testPodsStatesRetrySearchAndSelection() async throws {
        let state = KubernetesState(lifecycle: .ready)
        let viewModel = PodsViewModel()
        var didRetry = false
        let controller = PodsListViewController(
            state: state,
            viewModel: viewModel,
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: { didRetry = true }
        )
        let rootView = controller.view
        let tableView = try XCTUnwrap(findTableView(in: rootView))

        XCTAssertTrue(hasText("Loading pods…", in: rootView))

        viewModel.streamPhase = .live
        try await waitUntil { self.hasText("No pods", in: rootView) }

        viewModel.streamPhase = .reconnecting(attempt: 2, lastError: "Connection lost")
        try await waitUntil {
            self.visibleButton(titled: "Retry", in: rootView) != nil
        }
        visibleButton(titled: "Retry", in: rootView)?.performClick(nil)
        XCTAssertTrue(didRetry)

        viewModel.pods = [
            pod(id: "alpha", name: "alpha"),
            pod(id: "beta", name: "beta"),
        ]
        viewModel.streamPhase = .live
        try await waitUntil { tableView.numberOfRows == 2 }

        viewModel.selectedID = "beta"
        try await waitUntil { tableView.selectedRow == 1 }

        viewModel.searchText = "alpha"
        try await waitUntil { tableView.numberOfRows == 1 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedPod?.id, "beta")

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0
                && self.hasText("No Results", in: rootView)
        }
        XCTAssertEqual(viewModel.selectedID, "beta")
        viewModel.streamPhase = .reconnecting(attempt: 3, lastError: nil)
        try await waitUntil {
            self.hasText(
                "No pods match “missing”.\nReconnecting to Kubernetes (attempt 3)",
                in: rootView
            )
        }

        viewModel.searchText = ""
        try await waitUntil { tableView.numberOfRows == 2 && tableView.selectedRow == 1 }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "alpha")

        viewModel.pods.removeAll { $0.id == "alpha" }
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }
    }

    @MainActor
    func testServicesDisabledActionRowsAndSearch() async throws {
        let disabledState = KubernetesState(lifecycle: .disabled)
        let disabledViewModel = ServicesViewModel()
        var didStart = false
        let disabledController = ServicesListViewController(
            state: disabledState,
            viewModel: disabledViewModel,
            canControl: true,
            onCheckStatus: {},
            onStart: { didStart = true },
            onStop: {},
            onRetryStreams: {}
        )
        let disabledRoot = disabledController.view

        try XCTUnwrap(visibleButton(titled: "Turn On", in: disabledRoot)).performClick(nil)
        XCTAssertTrue(didStart)

        let readyState = KubernetesState(lifecycle: .ready)
        let viewModel = ServicesViewModel()
        viewModel.services = [
            service(id: "api", name: "api"),
            service(id: "database", name: "database"),
        ]
        viewModel.streamPhase = .live
        let controller = ServicesListViewController(
            state: readyState,
            viewModel: viewModel,
            canControl: true,
            onCheckStatus: {},
            onStart: {},
            onStop: {},
            onRetryStreams: {}
        )
        let rootView = controller.view
        let tableView = try XCTUnwrap(findTableView(in: rootView))

        XCTAssertEqual(tableView.numberOfRows, 2)
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "database")

        viewModel.searchText = "api"
        try await waitUntil { tableView.numberOfRows == 1 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedService?.id, "database")

        viewModel.searchText = "missing"
        try await waitUntil {
            tableView.numberOfRows == 0
                && self.hasText("No Results", in: rootView)
        }
    }

    @MainActor
    func testObservationDoesNotRetainControllers() async {
        let state = KubernetesState(lifecycle: .ready)
        let podsModel = PodsViewModel()
        let servicesModel = ServicesViewModel()
        weak var weakPodsController: PodsListViewController?
        weak var weakServicesController: ServicesListViewController?

        autoreleasepool {
            var podsController: PodsListViewController? = PodsListViewController(
                state: state,
                viewModel: podsModel,
                canControl: true,
                onCheckStatus: {},
                onStart: {},
                onStop: {},
                onRetryStreams: {}
            )
            var servicesController: ServicesListViewController? = ServicesListViewController(
                state: state,
                viewModel: servicesModel,
                canControl: true,
                onCheckStatus: {},
                onStart: {},
                onStop: {},
                onRetryStreams: {}
            )
            _ = podsController?.view
            _ = servicesController?.view
            weakPodsController = podsController
            weakServicesController = servicesController
            podsController = nil
            servicesController = nil
        }

        XCTAssertNil(weakPodsController)
        XCTAssertNil(weakServicesController)
        podsModel.searchText = ""
        servicesModel.searchText = ""
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
        return view.subviews.lazy.compactMap {
            self.findTableView(in: $0)
        }.first
    }

    @MainActor
    private func visibleButton(titled title: String, in view: NSView) -> NSButton? {
        guard !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let button = view as? NSButton, button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap {
            self.visibleButton(titled: title, in: $0)
        }.first
    }

    @MainActor
    private func hasText(_ text: String, in view: NSView) -> Bool {
        guard !view.isHiddenOrHasHiddenAncestor else { return false }
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { self.hasText(text, in: $0) }
    }

    private func pod(id: String, name: String) -> PodViewModel {
        PodViewModel(
            id: id,
            name: name,
            namespace: "default",
            phase: .running,
            containerCount: 1,
            readyCount: 1,
            restartCount: 0,
            createdAt: .distantPast
        )
    }

    private func service(id: String, name: String) -> ServiceViewModel {
        ServiceViewModel(
            id: id,
            name: name,
            namespace: "default",
            type: .clusterIP,
            clusterIP: "10.0.0.1",
            ports: [],
            createdAt: .distantPast
        )
    }
}
