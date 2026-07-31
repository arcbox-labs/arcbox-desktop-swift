import ArcBoxClient
import K8sClient
import OSLog
import SwiftUI

/// Owns the Kubernetes session: the one `K8sClient`, the watch streams, and the two view models
/// they feed.
///
/// These responsibilities used to be split across the list views (refresh cadence), the view
/// models (a `K8sClient` each) and this type (the `enabled` flag), so nothing could enforce that
/// teardown and refresh happened in a defined order. Every transition now funnels through
/// ``setEnabled(_:client:)``, and snapshots are written back only when they belong to the current
/// ``generation`` — a superseded response is dropped rather than racing a teardown.
@MainActor
@Observable
class KubernetesState {
    /// Reconnect backoff bounds, applied when a watch stream fails.
    private static let minBackoff = Duration.seconds(2)
    private static let maxBackoff = Duration.seconds(15)

    private(set) var enabled: Bool = false
    var isStarting: Bool = false
    var isStopping: Bool = false
    var startError: String?

    /// Owned here so the session can guarantee they are cleared exactly when the client is.
    let podsModel = PodsViewModel()
    let servicesModel = ServicesViewModel()

    private var k8sClient: K8sClient?
    private var sessionTask: Task<Void, Never>?
    /// Bumped on every teardown; in-flight work compares against it before writing back.
    private var generation: Int = 0
    /// Whether the current connection attempt delivered data, so backoff resets on a
    /// connection that worked and then dropped rather than growing forever.
    private var receivedSnapshot = false

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
        if newValue, let client {
            startSession(client: client)
        } else {
            endSession()
        }
    }

    private func startSession(client: ArcBoxClient) {
        sessionTask?.cancel()
        let generation = self.generation
        sessionTask = Task { [weak self] in
            await self?.runSession(generation: generation, client: client)
        }
    }

    private func endSession() {
        generation &+= 1
        sessionTask?.cancel()
        sessionTask = nil
        // Releasing the client invalidates its URLSessions and frees the TLS delegates.
        k8sClient = nil
        podsModel.clear()
        servicesModel.clear()
    }

    // MARK: - Watch

    /// Hold watches on pods and services open, reconnecting with backoff when they fail.
    ///
    /// Routine interruptions — the server closing an idle watch, or expiring the
    /// `resourceVersion` — are handled inside the streams and never reach here.
    private func runSession(generation: Int, client: ArcBoxClient) async {
        var failures = 0

        while !Task.isCancelled, generation == self.generation {
            setLoading(true)
            receivedSnapshot = false

            do {
                let k8s = try await resolveClient(client, generation: generation)
                guard generation == self.generation else { return }

                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await self.streamPods(k8s, generation: generation) }
                    group.addTask { try await self.streamServices(k8s, generation: generation) }
                    try await group.waitForAll()
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                Log.pods.error(
                    "Kubernetes watch failed: \(error.localizedDescription, privacy: .private)")
                ErrorReporting.capture(error, domain: .kubernetes, operation: "watch")
                // Keep the user's selection so it restores if the cluster comes back.
                podsModel.dropItems()
                servicesModel.dropItems()
                // Drop the client so the next attempt re-fetches the kubeconfig and reconnects.
                k8sClient = nil
            }

            guard !Task.isCancelled, generation == self.generation else { return }
            failures = receivedSnapshot ? 1 : failures + 1
            try? await Task.sleep(for: Self.backoff(afterFailures: failures))
        }
    }

    private func streamPods(_ k8s: K8sClient, generation: Int) async throws {
        for try await pods in k8s.podStream() {
            guard generation == self.generation else { return }
            podsModel.apply(pods)
            noteSnapshot()
        }
    }

    private func streamServices(_ k8s: K8sClient, generation: Int) async throws {
        for try await services in k8s.serviceStream() {
            guard generation == self.generation else { return }
            servicesModel.apply(services)
            noteSnapshot()
        }
    }

    private func noteSnapshot() {
        receivedSnapshot = true
        setLoading(false)
    }

    private static func backoff(afterFailures failures: Int) -> Duration {
        let doubled = minBackoff * Double(1 << min(failures - 1, 3))
        return min(doubled, maxBackoff)
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
