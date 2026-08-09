import ArcBoxClient
import SwiftUI

/// Transitional SwiftUI toolbar and lifecycle host for the native Pods list.
struct PodsListView: View {
    @Environment(KubernetesState.self) private var k8s
    @Environment(PodsViewModel.self) private var vm
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        PodsListControllerView(
            state: k8s,
            viewModel: vm,
            canControl: arcboxClient != nil,
            onCheckStatus: {
                Task { await k8s.checkStatus(client: arcboxClient) }
            },
            onStart: {
                Task { await k8s.start(client: arcboxClient) }
            },
            onStop: {
                Task { await k8s.stop(client: arcboxClient) }
            },
            onRetryStreams: {
                k8s.retryStreams(client: arcboxClient)
            }
        )
        .navigationTitle("Pods")
        .navigationSubtitle(navigationSubtitle)
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue {
                vm.searchText = ""
            }
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(
                        "Kubernetes",
                        isOn: Binding(
                            get: { k8s.lifecycle.toggleIsOn },
                            set: { newValue in
                                toggleKubernetes(newValue)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(arcboxClient == nil || !k8s.lifecycle.canToggle)
                    .help(k8s.lifecycle.toggleIsOn ? "Stop Kubernetes" : "Start Kubernetes")
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(
                        "Kubernetes",
                        isOn: Binding(
                            get: { k8s.lifecycle.toggleIsOn },
                            set: { newValue in
                                toggleKubernetes(newValue)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(arcboxClient == nil || !k8s.lifecycle.canToggle)
                    .help(k8s.lifecycle.toggleIsOn ? "Stop Kubernetes" : "Start Kubernetes")
                }
            }
        }
        .task(id: arcboxClient.map(ObjectIdentifier.init)) {
            await k8s.checkStatus(client: arcboxClient)
        }
    }

    private var navigationSubtitle: String {
        switch k8s.lifecycle {
        case .checking: "Checking"
        case .disabled: "Disabled"
        case .starting: "Starting"
        case .ready: "\(vm.podCount) total"
        case .stopping: "Stopping"
        case .failed: "Unavailable"
        }
    }

    private func toggleKubernetes(_ shouldEnable: Bool) {
        Task {
            if shouldEnable {
                await k8s.start(client: arcboxClient)
            } else {
                await k8s.stop(client: arcboxClient)
            }
        }
    }
}

private struct PodsListControllerView: NSViewControllerRepresentable {
    let state: KubernetesState
    let viewModel: PodsViewModel
    let canControl: Bool
    let onCheckStatus: @MainActor () -> Void
    let onStart: @MainActor () -> Void
    let onStop: @MainActor () -> Void
    let onRetryStreams: @MainActor () -> Void

    func makeNSViewController(context _: Context) -> PodsListViewController {
        PodsListViewController(
            state: state,
            viewModel: viewModel,
            canControl: canControl,
            onCheckStatus: onCheckStatus,
            onStart: onStart,
            onStop: onStop,
            onRetryStreams: onRetryStreams
        )
    }

    func updateNSViewController(
        _ controller: PodsListViewController,
        context _: Context
    ) {
        controller.update(
            canControl: canControl,
            onCheckStatus: onCheckStatus,
            onStart: onStart,
            onStop: onStop,
            onRetryStreams: onRetryStreams
        )
    }
}
