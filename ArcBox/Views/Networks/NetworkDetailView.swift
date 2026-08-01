import ArcBoxClient
import DockerClient
import SwiftUI

/// Transitional SwiftUI toolbar host for the native network detail controller.
struct NetworkDetailView: View {
    @Environment(NetworksViewModel.self) private var vm
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.dockerClient) private var docker

    var body: some View {
        let runningContainerIDs = Set(containersVM.containers.filter(\.isRunning).map(\.id))

        NetworkDetailControllerView(
            viewModel: vm,
            loadContainers: makeContainerLoader(),
            runningContainerIDs: runningContainerIDs
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Info")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func makeContainerLoader() -> NetworkDetailViewController.LoadContainers? {
        guard daemonManager.setupPhase.isDockerReady, let docker else { return nil }
        return { networkID in
            let response = try await docker.api.NetworkInspect(path: .init(id: networkID))
            let network = try response.ok.body.json

            return (network.Containers?.additionalProperties ?? [:])
                .map { containerID, container in
                    NetworkDetailViewController.ContainerEntry(
                        id: containerID,
                        name: container.Name ?? String(containerID.prefix(12)),
                        ipv4: container.IPv4Address ?? "",
                        mac: container.MacAddress ?? ""
                    )
                }
                .sorted {
                    let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                    return comparison == .orderedSame
                        ? $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
                        : comparison == .orderedAscending
                }
        }
    }
}

private struct NetworkDetailControllerView: NSViewControllerRepresentable {
    let viewModel: NetworksViewModel
    let loadContainers: NetworkDetailViewController.LoadContainers?
    let runningContainerIDs: Set<String>

    func makeNSViewController(context _: Context) -> NetworkDetailViewController {
        NetworkDetailViewController(
            viewModel: viewModel,
            loadContainers: loadContainers,
            runningContainerIDs: runningContainerIDs
        )
    }

    func updateNSViewController(
        _ controller: NetworkDetailViewController,
        context _: Context
    ) {
        controller.update(
            loadContainers: loadContainers,
            runningContainerIDs: runningContainerIDs
        )
    }
}
