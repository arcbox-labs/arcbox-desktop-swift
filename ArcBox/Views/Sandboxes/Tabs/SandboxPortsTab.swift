import ArcBoxClient
import SwiftUI

/// Ports tab: expose sandbox ports on the host (loopback) and remove mappings.
struct SandboxPortsTab: View {
    let sandbox: SandboxViewModel

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.arcboxClient) private var client

    @State private var sandboxPortText = ""
    @State private var hostPortText = ""
    @State private var networkProtocol = "tcp"
    @State private var isWorking = false

    private var mappings: [SandboxExposedPort] {
        vm.exposedPorts[sandbox.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(
            id: PortLoadID(
                sandboxID: sandbox.id,
                client: client.map(ObjectIdentifier.init),
                runtimeReady: runtimeReady
            )
        ) {
            await vm.loadExposedPorts(
                for: sandbox.id,
                client: runtimeReady ? client : nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .sandboxChanged)) { _ in
            guard runtimeReady, client != nil else { return }
            refresh()
        }
        .errorToast(message: Bindable(vm).exposedPortsRefreshError)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Sandbox port", text: $sandboxPortText, prompt: Text("8080"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)

            TextField("Host port", text: $hostPortText, prompt: Text("auto"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Picker("", selection: $networkProtocol) {
                Text("TCP").tag("tcp")
                Text("UDP").tag("udp")
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Spacer()

            Button("Expose", action: expose)
                .disabled(!canExpose)

            Button(action: refresh) {
                Label("Refresh port mappings", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.exposedPortsSandboxID != sandbox.id {
            loadingPlaceholder("Preparing port mappings…")
        } else {
            switch vm.exposedPortsLoadState {
            case .waiting:
                loadingPlaceholder("Waiting for ArcBox daemon…")
            case .loading:
                loadingPlaceholder("Loading port mappings…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Load Port Mappings", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry", action: refresh)
                        .disabled(!canRefresh)
                }
            case .loaded:
                loadedContent
            }
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if mappings.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "network")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textMuted)
                Text("No exposed ports.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Expose one above, or use the CLI or SDK and refresh.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mappings) { mapping in
                        mappingRow(mapping)
                        Divider()
                    }
                }
            }
        }
    }

    private func loadingPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mappingRow(_ mapping: SandboxExposedPort) -> some View {
        HStack(spacing: 10) {
            Text("\(mapping.networkProtocol.uppercased()) \(mapping.sandboxPort)")
                .font(.system(size: 12, design: .monospaced))

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)

            if mapping.networkProtocol == "tcp", let url = mapping.localURL {
                Link("localhost:\(mapping.hostPort)", destination: url)
                    .font(.system(size: 12, design: .monospaced))
                    .help("Open in browser")
            } else {
                Text("localhost:\(mapping.hostPort)")
                    .font(.system(size: 12, design: .monospaced))
            }

            Spacer()

            Button {
                unexpose(mapping)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!actionsAvailable)
            .help("Remove mapping")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canExpose: Bool {
        guard actionsAvailable else { return false }
        guard let port = UInt32(sandboxPortText), port > 0, port < 65536 else { return false }
        if !hostPortText.isEmpty {
            guard let host = UInt32(hostPortText), host > 0, host < 65536 else { return false }
        }
        return true
    }

    private var actionsAvailable: Bool {
        runtimeReady
            && client != nil
            && vm.exposedPortsSandboxID == sandbox.id
            && vm.exposedPortsLoadState == .loaded
            && !vm.isLoadingExposedPorts
            && !isWorking
    }

    private var canRefresh: Bool {
        runtimeReady && client != nil && !vm.isLoadingExposedPorts && !isWorking
    }

    private var runtimeReady: Bool {
        daemonManager.state.isRunning && daemonManager.setupPhase.isDockerReady
    }

    private func expose() {
        guard let port = UInt32(sandboxPortText) else { return }
        let hostPort = UInt32(hostPortText) ?? 0
        isWorking = true
        Task {
            _ = await vm.exposePort(
                sandboxID: sandbox.id,
                sandboxPort: port,
                hostPort: hostPort,
                networkProtocol: networkProtocol,
                client: client
            )
            isWorking = false
        }
    }

    private func unexpose(_ mapping: SandboxExposedPort) {
        isWorking = true
        Task {
            await vm.unexposePort(
                sandboxID: sandbox.id,
                sandboxPort: mapping.sandboxPort,
                networkProtocol: mapping.networkProtocol,
                client: client
            )
            isWorking = false
        }
    }

    private func refresh() {
        let sandboxID = sandbox.id
        Task {
            guard
                !Task.isCancelled,
                vm.selectedID == sandboxID,
                runtimeReady,
                client != nil
            else { return }
            await vm.loadExposedPorts(for: sandboxID, client: client)
        }
    }
}

private struct PortLoadID: Equatable {
    let sandboxID: String
    let client: ObjectIdentifier?
    let runtimeReady: Bool
}
