import ArcBoxClient
import SwiftUI

/// Column 2: services list with toolbar
struct ServicesListView: View {
    @Environment(KubernetesState.self) private var k8s
    @Environment(ServicesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var arcboxClient

    var body: some View {
        VStack(spacing: 0) {
            if !k8s.enabled {
                KubernetesDisabledView(isStarting: k8s.isStarting, startError: k8s.startError) {
                    Task { await k8s.start(client: arcboxClient) }
                }
            } else if vm.services.isEmpty {
                VStack {
                    Spacer()
                    if vm.isLoading {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Text("No services")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.filteredServices) { service in
                            ServiceRowView(
                                service: service,
                                isSelected: vm.selectedID == service.id,
                                onSelect: { vm.selectService(service.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Services")
        .navigationSubtitle(k8s.enabled ? "\(vm.serviceCount) total" : "Disabled")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        // Refreshing is owned by KubernetesState, which starts and stops it with `enabled`.
        .task {
            await k8s.checkStatus(client: arcboxClient)
        }
    }
}
