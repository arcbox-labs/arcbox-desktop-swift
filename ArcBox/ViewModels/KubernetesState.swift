import ArcBoxClient
import K8sClient
import OSLog
import SwiftUI

/// Owns the Kubernetes session: the one `K8sClient`, the one refresh loop, and the two view
/// models they feed.
///
/// These three responsibilities used to be split across the list views (refresh cadence), the
/// view models (a `K8sClient` each) and this type (the `enabled` flag), so nothing could enforce
/// that teardown and refresh happened in a defined order. Every transition now funnels through
/// ``setEnabled(_:client:)``, and results are written back only when they belong to the current
/// ``generation`` — a superseded response is dropped rather than racing a teardown.
@MainActor
@Observable
class KubernetesState {
    /// Cadence once the cluster has answered, or has stopped answering for good.
    private static let pollInterval = Duration.seconds(10)
    /// Faster cadence while waiting for a freshly started API server to come up.
    private static let warmupInterval = Duration.seconds(2)
    /// Warmup attempts before settling into ``pollInterval``.
    private static let warmupAttempts = 15

    private(set) var enabled: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false
    var startError: String?

    /// Owned here so the session can guarantee they are cleared exactly when the client is.
    let podsModel = PodsViewModel()
    let servicesModel = ServicesViewModel()

    private var k8sClient: K8sClient?
    private var refreshTask: Task<Void, Never>?
    /// Bumped on every teardown; in-flight work compares against it before writing back.
    private var generation: Int = 0

    /// Check current K8s cluster status via gRPC.
    func checkStatus(client: ArcBoxClient?) async {
        guard let client else { return }
        do {
            let status: Arcbox_V1_KubernetesStatusResponse = try await client.kubernetes.status(
                .init(), options: ArcBoxClient.defaultCallOptions)
            setEnabled(status.running && status.apiReady, client: client)
        } catch {
            ErrorReporting.capture(error, domain: .kubernetes, operation: "check_status")
            setEnabled(false, client: client)
        }
    }

    /// Start the Kubernetes cluster and wait until it is fully ready.
    func start(client: ArcBoxClient?) async {
        guard let client, !isStarting else { return }
        isStarting = true
        startError = nil
        do {
            let response: Arcbox_V1_KubernetesStartResponse = try await client.kubernetes.start(
                .init(), options: ArcBoxClient.defaultCallOptions)
            Log.pods.info(
                "Kubernetes start: running=\(response.running) apiReady=\(response.apiReady) endpoint=\(response.endpoint)"
            )

            // Poll until API is fully ready or timeout (~60s).
            var interrupted = false
            for attempt in 0..<30 {
                if Task.isCancelled || isStopping {
                    interrupted = true
                    break
                }
                if attempt > 0 {
                    try await Task.sleep(for: .seconds(2))
                }
                let status: Arcbox_V1_KubernetesStatusResponse = try await client.kubernetes.status(
                    .init(), options: ArcBoxClient.defaultCallOptions)
                if status.running && status.apiReady {
                    setEnabled(true, client: client)
                    isStarting = false
                    return
                }
            }
            setEnabled(false, client: client)
            if !interrupted {
                startError = "Kubernetes failed to start within 60 seconds"
                Log.pods.warning("Kubernetes start timed out after 60s")
            }
        } catch {
            startError = error.localizedDescription
            Log.pods.error("Error starting Kubernetes: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .kubernetes, operation: "start")
            setEnabled(false, client: client)
        }
        isStarting = false
    }

    /// Stop the Kubernetes cluster.
    func stop(client: ArcBoxClient?) async {
        guard let client, !isStopping else { return }
        isStopping = true
        do {
            let _: Arcbox_V1_KubernetesStopResponse = try await client.kubernetes.stop(
                .init(), options: ArcBoxClient.defaultCallOptions)
            setEnabled(false, client: client)
        } catch {
            Log.pods.error("Error stopping Kubernetes: \(error)")
            ErrorReporting.capture(error, domain: .kubernetes, operation: "stop")
            // Re-check actual status on failure
            await checkStatus(client: client)
        }
        isStopping = false
    }

    // MARK: - Session lifecycle

    /// The only place `enabled` changes, so the session is always started or torn down with it.
    private func setEnabled(_ newValue: Bool, client: ArcBoxClient?) {
        guard newValue != enabled else { return }
        enabled = newValue
        if newValue {
            startRefreshing(client: client)
        } else {
            endSession()
        }
    }

    private func startRefreshing(client: ArcBoxClient?) {
        refreshTask?.cancel()
        let generation = self.generation
        refreshTask = Task { [weak self] in
            await self?.runRefreshLoop(generation: generation, client: client)
        }
    }

    private func endSession() {
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        // Releasing the client invalidates its URLSession and frees the TLS delegate.
        k8sClient = nil
        podsModel.clear()
        servicesModel.clear()
    }

    // MARK: - Refresh

    private func runRefreshLoop(generation: Int, client: ArcBoxClient?) async {
        var attempts = 0
        var settled = false
        while !Task.isCancelled, generation == self.generation {
            let succeeded = await refresh(generation: generation, client: client)
            attempts += 1
            if succeeded || attempts >= Self.warmupAttempts {
                settled = true
            }
            try? await Task.sleep(for: settled ? Self.pollInterval : Self.warmupInterval)
        }
    }

    /// Fetch both resource kinds over the shared client. Returns `true` when the cluster answered.
    private func refresh(generation: Int, client: ArcBoxClient?) async -> Bool {
        guard let client else { return false }
        setLoading(true)
        defer {
            if generation == self.generation { setLoading(false) }
        }

        do {
            let k8s = try await resolveClient(client, generation: generation)
            guard generation == self.generation else { return false }

            async let podList = Perf.measure("pod.list") { try await k8s.listAllPods() }
            async let serviceList = Perf.measure("service.list") { try await k8s.listAllServices() }
            let (pods, services) = try await (podList, serviceList)

            guard generation == self.generation else { return false }
            podsModel.apply(pods)
            servicesModel.apply(services)
            return true
        } catch {
            guard generation == self.generation else { return false }
            Log.pods.error(
                "Error refreshing Kubernetes resources: \(error.localizedDescription, privacy: .private)")
            ErrorReporting.capture(error, domain: .kubernetes, operation: "refresh")
            // Keep the user's selection so it restores if the cluster comes back.
            podsModel.dropItems()
            servicesModel.dropItems()
            // Drop the client so the next tick re-fetches the kubeconfig and reconnects.
            k8sClient = nil
            return false
        }
    }

    private func resolveClient(_ client: ArcBoxClient, generation: Int) async throws -> K8sClient {
        if let k8sClient { return k8sClient }
        let response: Arcbox_V1_KubernetesKubeconfigResponse = try await client.kubernetes
            .getKubeconfig(.init(), options: ArcBoxClient.defaultCallOptions)
        guard generation == self.generation else { throw CancellationError() }
        let created = try K8sClient(config: try KubeConfig(yaml: response.kubeconfig))
        k8sClient = created
        return created
    }

    private func setLoading(_ loading: Bool) {
        podsModel.isLoading = loading
        servicesModel.isLoading = loading
    }
}
