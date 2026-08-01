import AppKit
import ArcBoxClient
import XCTest

@testable import ArcBox

final class MachinesListViewControllerTests: XCTestCase {
    @MainActor
    func testStatesActionsSelectionAndControllerLifetime() async throws {
        let viewModel = MachinesViewModel()
        var didRetry = false
        var toggledIDs: [String] = []
        var controller: MachinesListViewController? = MachinesListViewController(
            viewModel: viewModel,
            onRetry: { didRetry = true },
            onToggle: { toggledIDs.append($0) },
            onDelete: { _ in }
        )
        weak var weakController = controller

        let rootView = try XCTUnwrap(controller?.view)
        let tableView = try XCTUnwrap(findTableView(in: rootView))
        XCTAssertTrue(try XCTUnwrap(tableView.enclosingScrollView).isHidden)

        viewModel.loadState = .failed("Daemon unavailable")
        try await waitUntil { self.visibleButton(titled: "Retry", in: rootView) != nil }
        try assertLoadError(in: rootView)
        visibleButton(titled: "Retry", in: rootView)?.performClick(nil)
        XCTAssertTrue(didRetry)

        viewModel.loadState = .loaded
        try await waitUntil { self.hasText("No Linux machines yet", in: rootView) }
        try assertEmptyState(in: rootView)

        viewModel.machines = [
            machine(id: "b", name: "same", state: .stopped),
            machine(id: "a", name: "same", state: .stopped),
        ]
        XCTAssertEqual(viewModel.filteredMachines.map(\.id), ["a", "b"])

        var busyMachine = machine(id: "busy", name: "busy", state: .starting)
        busyMachine.isTransitioning = true
        viewModel.machines = [
            machine(
                id: "running",
                name: "alpha",
                state: .running,
                distro: "zzzzzzzzzzzzzz"
            ),
            machine(id: "stopped", name: "beta", state: .stopped),
            busyMachine,
        ]
        try await waitUntil { tableView.numberOfRows == 4 }
        XCTAssertFalse(try XCTUnwrap(tableView.enclosingScrollView).isHidden)
        XCTAssertNil(row(named: "Running", in: tableView))
        XCTAssertNotNil(row(named: "Stopped", in: tableView))

        try assertBusyMachine(named: "busy", in: tableView)

        let runningRow = try selectAndToggleRunningMachine(named: "alpha", in: tableView)
        XCTAssertEqual(toggledIDs, ["running"])

        var updatedToggleIDs: [String] = []
        controller?.update(
            onRetry: {},
            onToggle: { updatedToggleIDs.append($0) },
            onDelete: { _ in }
        )
        let stoppedRow = try XCTUnwrap(row(named: "beta", in: tableView))
        let stoppedCell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: stoppedRow, makeIfNecessary: true)
        )
        tableView.selectRowIndexes(IndexSet(integer: stoppedRow), byExtendingSelection: false)
        try XCTUnwrap(button("MachineToggleButton", in: stoppedCell)).performClick(nil)
        XCTAssertEqual(updatedToggleIDs, ["stopped"])

        viewModel.updateMachine("stopped") { $0.isTransitioning = true }
        try XCTUnwrap(button("MachineToggleButton", in: stoppedCell)).performClick(nil)
        XCTAssertEqual(updatedToggleIDs, ["stopped"])
        try await waitUntil {
            guard
                let row = self.row(named: "beta", in: tableView),
                let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
            else {
                return false
            }
            return self.button("MachineToggleButton", in: cell)?.isHidden == true
        }

        viewModel.updateMachine("stopped") { $0.isTransitioning = false }
        try await waitUntil {
            guard
                let row = self.row(named: "beta", in: tableView),
                let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
            else {
                return false
            }
            return self.button("MachineToggleButton", in: cell)?.isHidden == false
        }

        tableView.selectRowIndexes(IndexSet(integer: runningRow), byExtendingSelection: false)
        XCTAssertEqual(viewModel.selectedID, "running")

        viewModel.selectedID = "stopped"
        try await waitUntil {
            tableView.selectedRow == self.row(named: "beta", in: tableView)
        }

        viewModel.searchText = "alpha"
        try await waitUntil { tableView.numberOfRows == 1 && tableView.selectedRow == -1 }
        XCTAssertEqual(viewModel.selectedID, "stopped")

        viewModel.searchText = ""
        try await waitUntil {
            tableView.numberOfRows == 4
                && tableView.selectedRow == self.row(named: "beta", in: tableView)
        }

        viewModel.machines.removeAll { $0.id == "stopped" }
        try await waitUntil { viewModel.selectedID == nil && tableView.selectedRow == -1 }

        controller = nil
        XCTAssertNil(weakController)

        viewModel.searchText = "alpha"
        await Task.yield()
    }

    @MainActor
    func testSearchWithoutMatchesShowsNoResults() async throws {
        let viewModel = MachinesViewModel()
        viewModel.loadState = .loaded
        viewModel.machines = [machine(id: "running", name: "alpha", state: .running)]
        let controller = MachinesListViewController(
            viewModel: viewModel,
            onRetry: {},
            onToggle: { _ in },
            onDelete: { _ in }
        )

        viewModel.searchText = "missing"

        try await waitUntil {
            self.hasText("No Results", in: controller.view)
                && self.findTableView(in: controller.view)?.numberOfRows == 0
        }
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
        if let textField = view as? NSTextField, textField.stringValue == text {
            return true
        }
        return view.subviews.contains { self.hasText(text, in: $0) }
    }

    @MainActor
    private func textField(titled title: String, in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField, textField.stringValue == title {
            return textField
        }
        return view.subviews.lazy.compactMap {
            self.textField(titled: title, in: $0)
        }.first
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
    private func assertBusyMachine(
        named name: String,
        in tableView: NSTableView
    ) throws {
        let row = try XCTUnwrap(row(named: name, in: tableView))
        let cell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
        )
        cell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        cell.layoutSubtreeIfNeeded()
        let toggleButton = try XCTUnwrap(button("MachineToggleButton", in: cell))
        XCTAssertTrue(toggleButton.isHidden)
        XCTAssertTrue(try XCTUnwrap(button("MachineDeleteButton", in: cell)).isHidden)
        let progressIndicator = try XCTUnwrap(progressIndicator(in: cell))
        XCTAssertFalse(progressIndicator.isHidden)
        XCTAssertEqual(
            cell.bounds.maxX - progressIndicator.frame.maxX,
            20,
            accuracy: 0.5
        )
        XCTAssertEqual(
            try XCTUnwrap(toggleButton.superview as? NSStackView).frame.width,
            0,
            accuracy: 0.5
        )
    }

    @MainActor
    private func assertEmptyState(in rootView: NSView) throws {
        rootView.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        rootView.layoutSubtreeIfNeeded()

        let iconBox = try XCTUnwrap(
            view(identifier: "MachineEmptyIcon", in: rootView) as? NSBox
        )
        XCTAssertEqual(iconBox.frame.size, NSSize(width: 64, height: 64))
        XCTAssertEqual(iconBox.cornerRadius, 32)
        XCTAssertEqual(iconBox.fillColor, .quaternarySystemFill)

        let title = try XCTUnwrap(textField(titled: "No Linux machines yet", in: rootView))
        XCTAssertEqual(title.font?.pointSize, 13)
        XCTAssertEqual(title.textColor, .secondaryLabelColor)

        let card = try XCTUnwrap(
            view(identifier: "MachineEmptyCard", in: rootView) as? NSBox
        )
        XCTAssertEqual(card.cornerRadius, 10)
        XCTAssertEqual(card.fillColor, .quaternarySystemFill)
        XCTAssertTrue(hasText("• Native ARM64 performance on Apple Silicon", in: card))
    }

    @MainActor
    private func assertLoadError(in rootView: NSView) throws {
        rootView.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        rootView.layoutSubtreeIfNeeded()

        let icon = try XCTUnwrap(
            view(identifier: "MachineLoadErrorIcon", in: rootView)
        )
        XCTAssertEqual(
            icon.alignmentRect(forFrame: icon.frame).size,
            NSSize(width: 32, height: 32)
        )

        let message = try XCTUnwrap(textField(titled: "Daemon unavailable", in: rootView))
        XCTAssertEqual(message.font?.pointSize, 13)
        XCTAssertEqual(message.textColor, .secondaryLabelColor)

        let retry = try XCTUnwrap(visibleButton(titled: "Retry", in: rootView))
        XCTAssertEqual(retry.controlSize, .regular)
        XCTAssertEqual(retry.bezelStyle, .rounded)
        XCTAssertFalse(hasText("Failed to load machines", in: rootView))
    }

    @MainActor
    private func selectAndToggleRunningMachine(
        named name: String,
        in tableView: NSTableView
    ) throws -> Int {
        let row = try XCTUnwrap(row(named: name, in: tableView))
        let cell = try XCTUnwrap(
            tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
        )
        cell.frame = NSRect(x: 0, y: 0, width: 360, height: AppMetrics.rowHeight)
        cell.layoutSubtreeIfNeeded()
        let toggleButton = try XCTUnwrap(button("MachineToggleButton", in: cell))
        let actions = try XCTUnwrap(toggleButton.superview as? NSStackView)
        XCTAssertTrue(toggleButton.isHidden)
        XCTAssertEqual(actions.frame.width, 0, accuracy: 0.5)
        XCTAssertEqual(
            (cell as? NSTableCellView)?.imageView?.contentTintColor,
            .systemCyan
        )

        let statusDot = try XCTUnwrap(view(identifier: "MachineStatusDot", in: cell))
        XCTAssertEqual(statusDot.layer?.borderWidth, 2)
        XCTAssertEqual(statusDot.layer?.borderColor, NSColor.textBackgroundColor.cgColor)

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        (cell as? NSTableCellView)?.backgroundStyle = .emphasized
        cell.layoutSubtreeIfNeeded()
        XCTAssertFalse(toggleButton.isHidden)
        XCTAssertGreaterThan(actions.frame.width, 0)
        XCTAssertEqual(statusDot.layer?.borderColor, NSColor.controlAccentColor.cgColor)
        toggleButton.performClick(nil)
        return row
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

    @MainActor
    private func progressIndicator(in view: NSView) -> NSProgressIndicator? {
        if let indicator = view as? NSProgressIndicator,
            indicator.identifier == NSUserInterfaceItemIdentifier("MachineBusyIndicator")
        {
            return indicator
        }
        return view.subviews.lazy.compactMap {
            self.progressIndicator(in: $0)
        }.first
    }

    @MainActor
    private func view(identifier: String, in view: NSView) -> NSView? {
        if view.identifier == NSUserInterfaceItemIdentifier(identifier) {
            return view
        }
        return view.subviews.lazy.compactMap {
            self.view(identifier: identifier, in: $0)
        }.first
    }

    @MainActor
    private func machine(
        id: String,
        name: String,
        state: MachineState,
        distro: String = "ubuntu"
    ) -> MachineViewModel {
        var summary = Arcbox_V1_MachineSummary()
        summary.id = id
        summary.name = name
        summary.state = state.rawValue
        summary.cpus = 4
        summary.memory = 4 << 30
        summary.diskSize = 50 << 30
        summary.distro = distro
        summary.distroVersion = "24.04"
        return MachineViewModel(from: summary)
    }
}
