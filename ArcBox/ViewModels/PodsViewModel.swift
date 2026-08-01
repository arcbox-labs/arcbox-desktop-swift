import K8sClient
import SwiftUI

/// Detail tab for pods
enum PodDetailTab: String, @MainActor DetailTab {
    case info = "Info"
    case logs = "Logs"
    case terminal = "Terminal"

    var id: String { rawValue }
}

/// Pod list state
@MainActor
@Observable
class PodsViewModel {
    var pods: [PodViewModel] = []
    var selectedID: String?
    var activeTab: PodDetailTab = .info
    var listWidth: CGFloat = 320
    var isLoading: Bool = false
    var searchText: String = ""
    var isSearching: Bool = false

    var podCount: Int { pods.count }
    var runningCount: Int { pods.filter(\.isRunning).count }
    var filteredPods: [PodViewModel] {
        guard !searchText.isEmpty else { return pods }
        let query = searchText.lowercased()
        return pods.filter {
            $0.name.lowercased().contains(query)
                || $0.namespace.lowercased().contains(query)
                || $0.phase.rawValue.lowercased().contains(query)
        }
    }

    var selectedPod: PodViewModel? {
        guard let id = selectedID else { return nil }
        return filteredPods.first { $0.id == id }
    }

    func selectPod(_ id: String) {
        selectedID = id
    }

    /// Replace the list with a watch snapshot. Called by ``KubernetesState``, which owns the
    /// client and the stream.
    func apply(_ items: [Pod]) {
        pods = items.compactMap { Self.mapPod($0) }
    }

    /// Clear all pod data when K8s is stopped.
    func clear() {
        pods = []
        selectedID = nil
    }

    // MARK: - Mapping

    private static func mapPod(_ pod: Pod) -> PodViewModel? {
        guard let meta = pod.metadata, let name = meta.name else { return nil }
        let uid = meta.uid ?? name

        let containers = pod.spec?.containers ?? []
        let statuses = pod.status?.containerStatuses ?? []
        let readyCount = statuses.filter { $0.ready == true }.count
        let restartCount = statuses.reduce(0) { $0 + ($1.restartCount ?? 0) }

        let phase: PodPhase
        switch pod.status?.phase {
        case "Running": phase = .running
        case "Pending": phase = .pending
        case "Succeeded": phase = .succeeded
        case "Failed": phase = .failed
        default: phase = .unknown
        }

        return PodViewModel(
            id: uid,
            name: name,
            namespace: meta.namespace ?? "default",
            phase: phase,
            containerCount: containers.count,
            readyCount: readyCount,
            restartCount: restartCount,
            createdAt: meta.creationTimestamp ?? Date()
        )
    }
}
