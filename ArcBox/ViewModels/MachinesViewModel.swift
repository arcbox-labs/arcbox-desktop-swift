import ArcBoxClient
import SwiftUI
import os

/// Detail tab options for machines (matches container pattern)
enum MachineDetailTab: String, @MainActor DetailTab {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Machine list state backed by the arcbox.v1 MachineService.
@MainActor
@Observable
class MachinesViewModel {
    var machines: [MachineViewModel] = []
    var selectedID: String?
    var activeTab: MachineDetailTab = .info
    var searchText: String = ""
    var isSearching: Bool = false
    var loadState: LoadPhase = .waiting
    var refreshError: String?
    let listLoadGate = SingleFlightLoadGate()
    var showCreateSheet: Bool = false

    /// User-visible error from the last failed operation.
    var lastError: String?

    var filteredMachines: [MachineViewModel] {
        guard !searchText.isEmpty else { return machines }
        return machines.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.distro.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedMachine: MachineViewModel? {
        guard let selectedID else { return nil }
        return machines.first { $0.id == selectedID }
    }

    var runningCount: Int {
        machines.filter(\.isRunning).count
    }

    var totalCount: Int { machines.count }

    func selectMachine(_ id: String) {
        selectedID = id
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Shared helpers (used by the gRPC extension)

    func updateMachine(_ id: String, mutate: (inout MachineViewModel) -> Void) {
        guard let index = machines.firstIndex(where: { $0.id == id }) else { return }
        mutate(&machines[index])
    }

    func setTransitioning(_ id: String, _ value: Bool) {
        updateMachine(id) { $0.isTransitioning = value }
    }

    var transitioningIDs: Set<String> {
        Set(machines.filter(\.isTransitioning).map(\.id))
    }

    /// Log, report, and surface an error; returns the user-facing message.
    @discardableResult
    func reportError(_ error: Error, operation: String, surface: Bool = true) -> String {
        Log.machine.error(
            "Machine \(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
        )
        ErrorReporting.capture(error, domain: .machine, operation: operation)
        let message = ArcBoxClient.userMessage(for: error)
        if surface {
            lastError = message
        }
        return message
    }
}
