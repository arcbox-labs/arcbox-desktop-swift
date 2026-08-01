import SwiftUI

/// Column 2: row-based machine list (matches ContainersListView pattern)
struct MachinesView: View {
    @Environment(MachinesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    var body: some View {
        MachinesListControllerView(
            viewModel: vm,
            onRetry: {
                Task { await vm.loadMachines(client: client) }
            },
            onToggle: { id in
                Task {
                    guard
                        let machine = vm.machines.first(where: { $0.id == id }),
                        !machine.isBusy
                    else {
                        return
                    }
                    if machine.isRunning {
                        await vm.stopMachine(id, client: client)
                    } else {
                        await vm.startMachine(id, client: client)
                    }
                }
            },
            onDelete: { id in
                Task {
                    guard
                        let machine = vm.machines.first(where: { $0.id == id }),
                        !machine.isBusy
                    else {
                        return
                    }
                    await vm.deleteMachine(id, client: client)
                }
            }
        )
        .navigationTitle("Machines")
        .navigationSubtitle("\(vm.runningCount) / \(vm.totalCount) running")
        .searchable(text: Bindable(vm).searchText, isPresented: Bindable(vm).isSearching)
        .onChange(of: vm.isSearching) { _, newValue in
            if !newValue { vm.searchText = "" }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(
                    action: { vm.showCreateSheet = true },
                    label: {
                        Image(systemName: "plus")
                    }
                )
                .accessibilityLabel("New machine")
            }
        }
        .sheet(isPresented: Bindable(vm).showCreateSheet) {
            MachineCreateSheet()
        }
        .task(id: client != nil) {
            await vm.loadMachines(client: client)
        }
        // MachineEventMonitor streams MachineService.Events and posts this on
        // create/start/idle/stop/remove (and on the server's resync signal), so
        // the list tracks out-of-band changes — external CLI, a VM that exits on
        // its own, a machine reset to stopped after daemon recovery — without
        // polling. loadMachines preserves in-flight transition and detail state.
        .onReceive(NotificationCenter.default.publisher(for: .machineChanged)) { _ in
            Task { await vm.loadMachines(client: client) }
        }
        .listErrorToast(
            operationError: Bindable(vm).lastError,
            refreshError: Bindable(vm).refreshError,
            resourceName: "machines"
        )
    }
}

private struct MachinesListControllerView: NSViewControllerRepresentable {
    let viewModel: MachinesViewModel
    let onRetry: @MainActor () -> Void
    let onToggle: @MainActor (String) -> Void
    let onDelete: @MainActor (String) -> Void

    func makeNSViewController(context _: Context) -> MachinesListViewController {
        MachinesListViewController(
            viewModel: viewModel,
            onRetry: onRetry,
            onToggle: onToggle,
            onDelete: onDelete
        )
    }

    func updateNSViewController(
        _ controller: MachinesListViewController,
        context _: Context
    ) {
        controller.update(
            onRetry: onRetry,
            onToggle: onToggle,
            onDelete: onDelete
        )
    }
}
