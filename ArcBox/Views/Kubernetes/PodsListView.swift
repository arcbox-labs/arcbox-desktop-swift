import ArcBoxClient
import SwiftUI

/// Column 2: pods list with toolbar
struct PodsListView: View {
    @Environment(KubernetesState.self) private var k8s
    @Environment(PodsViewModel.self) private var vm
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        VStack(spacing: 0) {
            if !k8s.enabled {
                KubernetesDisabledView(isStarting: k8s.isStarting, startError: k8s.startError) {
                    Task { await k8s.start(client: arcboxClient) }
                }
            } else if vm.pods.isEmpty {
                VStack {
                    Spacer()
                    if vm.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Text("No pods")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.filteredPods) { pod in
                            PodRowView(
                                pod: pod,
                                isSelected: vm.selectedID == pod.id,
                                onSelect: { vm.selectPod(pod.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Pods")
        .navigationSubtitle(k8s.enabled ? "\(vm.podCount) total" : "Disabled")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(
                        "Kubernetes",
                        isOn: Binding(
                            get: { k8s.enabled || k8s.isStarting },
                            set: { newValue in
                                toggleKubernetes(newValue)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(k8s.isStarting || k8s.isStopping)
                    .help(k8s.enabled ? "Stop Kubernetes" : "Start Kubernetes")
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(
                        "Kubernetes",
                        isOn: Binding(
                            get: { k8s.enabled || k8s.isStarting },
                            set: { newValue in
                                toggleKubernetes(newValue)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(k8s.isStarting || k8s.isStopping)
                    .help(k8s.enabled ? "Stop Kubernetes" : "Start Kubernetes")
                }
            }
        }
        // Refreshing is owned by KubernetesState, which starts and stops it with `enabled`.
        .task {
            await k8s.checkStatus(client: arcboxClient)
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
