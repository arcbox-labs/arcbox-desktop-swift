import ArcBoxClient
import DockerClient
import SwiftUI

/// Column 2: volumes list with toolbar
struct VolumesListView: View {
    @Environment(VolumesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.startupOrchestrator) private var orchestrator
    @Environment(\.dockerClient) private var docker

    var body: some View {
        VStack(spacing: 0) {
            if let orchestrator, !orchestrator.isReady {
                StartupProgressView(orchestrator: orchestrator)
            } else if !daemonManager.state.isRunning {
                DaemonLoadingView(state: daemonManager.state)
            } else {
                VolumesListControllerView(
                    viewModel: vm,
                    loadingTitle: daemonManager.setupPhase.isDockerReady
                        ? "Loading volumes…"
                        : "Starting Docker engine…",
                    onRetry: {
                        Task { await vm.loadVolumes(docker: docker) }
                    },
                    onDelete: { name in
                        Task { await vm.removeVolume(name, docker: docker) }
                    }
                )
            }
        }
        .navigationTitle("Volumes")
        .navigationSubtitle(vm.totalSize)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(
                    action: { vm.showNewVolumeSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("New volume")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: Bindable(vm).showNewVolumeSheet) {
            NewVolumeSheet()
        }
        .listErrorToast(
            operationError: Bindable(vm).lastError,
            refreshError: Bindable(vm).refreshError,
            resourceName: "volumes"
        )
        .task(id: daemonManager.setupPhase.isDockerReady && docker != nil) {
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            await vm.loadVolumes(docker: docker)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerVolumeChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            Task { await vm.loadVolumes(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            Task { await vm.loadVolumes(docker: docker) }
        }
    }
}

private struct VolumesListControllerView: NSViewControllerRepresentable {
    let viewModel: VolumesViewModel
    let loadingTitle: String
    let onRetry: @MainActor () -> Void
    let onDelete: @MainActor (String) -> Void

    func makeNSViewController(context _: Context) -> VolumesListViewController {
        VolumesListViewController(
            viewModel: viewModel,
            loadingTitle: loadingTitle,
            onRetry: onRetry,
            onDelete: onDelete
        )
    }

    func updateNSViewController(
        _ controller: VolumesListViewController,
        context _: Context
    ) {
        controller.update(
            loadingTitle: loadingTitle,
            onRetry: onRetry,
            onDelete: onDelete
        )
    }
}
