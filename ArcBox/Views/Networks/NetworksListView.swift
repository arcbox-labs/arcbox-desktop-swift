import ArcBoxClient
import DockerClient
import SwiftUI

/// Column 2: networks list with toolbar
struct NetworksListView: View {
    @Environment(NetworksViewModel.self) private var vm
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
                NetworksListControllerView(
                    viewModel: vm,
                    loadingTitle: daemonManager.setupPhase.isDockerReady
                        ? "Loading networks…"
                        : "Starting Docker engine…",
                    onRetry: {
                        Task { await vm.loadNetworks(docker: docker) }
                    },
                    onDelete: { id in
                        Task { await vm.removeNetwork(id, docker: docker) }
                    }
                )
            }
        }
        .navigationTitle("Networks")
        .navigationSubtitle("\(vm.networkCount) total")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(
                    action: { vm.showNewNetworkSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("New network")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: Bindable(vm).showNewNetworkSheet) {
            NewNetworkSheet()
        }
        .listErrorToast(
            operationError: Bindable(vm).lastError,
            refreshError: Bindable(vm).refreshError,
            resourceName: "networks"
        )
        .task(id: daemonManager.setupPhase.isDockerReady && docker != nil) {
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            await vm.loadNetworks(docker: docker)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerNetworkChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            Task { await vm.loadNetworks(docker: docker) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dockerDataChanged)) { _ in
            guard daemonManager.setupPhase.isDockerReady, docker != nil else { return }
            Task { await vm.loadNetworks(docker: docker) }
        }
    }
}

private struct NetworksListControllerView: NSViewControllerRepresentable {
    let viewModel: NetworksViewModel
    let loadingTitle: String
    let onRetry: @MainActor () -> Void
    let onDelete: @MainActor (String) -> Void

    func makeNSViewController(context _: Context) -> NetworksListViewController {
        NetworksListViewController(
            viewModel: viewModel,
            loadingTitle: loadingTitle,
            onRetry: onRetry,
            onDelete: onDelete
        )
    }

    func updateNSViewController(
        _ controller: NetworksListViewController,
        context _: Context
    ) {
        controller.update(
            loadingTitle: loadingTitle,
            onRetry: onRetry,
            onDelete: onDelete
        )
    }
}
