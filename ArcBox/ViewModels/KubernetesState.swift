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
    /// One supervisor per resource, so a failure on one does not take the other's list down.
    private var podsTask: Task<Void, Never>?
    private var servicesTask: Task<Void, Never>?
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
        if newValue, let client {
            startSession(client: client)
        } else {
            endSession()
        }
    }

    private func startSession(client: ArcBoxClient) {
        cancelStreams()
        let generation = self.generation
        podsTask = Task { [weak self] in
            await self?.supervise(
                self?.podsModel, operation: "watch_pods", generation: generation, client: client
            ) { $0.podStream() }
        }
        servicesTask = Task { [weak self] in
            await self?.supervise(
                self?.servicesModel, operation: "watch_services", generation: generation,
                client: client
            ) { $0.serviceStream() }
        }
    }

    private func cancelStreams() {
        podsTask?.cancel()
        podsTask = nil
        servicesTask?.cancel()
        servicesTask = nil
    }

    private func endSession() {
        generation &+= 1
        cancelStreams()
        // Releasing the client invalidates its URLSessions and frees the TLS delegates.
        k8sClient = nil
        podsModel.clear()
        servicesModel.clear()
    }

    // MARK: - Watch

    /// Hold one resource's watch open, reconnecting with backoff when it fails.
    ///
    /// Runs per resource rather than as a pair: pods and services fail for their own reasons
    /// (an RBAC denial reaches one endpoint, not both), and coupling them would take a healthy
    /// list down with a broken one.
    ///
    /// Routine interruptions — the server closing an idle watch, or expiring the
    /// `resourceVersion` — are handled inside the stream and never reach here.
    private func supervise<Model: K8sListModel>(
        _ model: Model?,
        operation: String,
        generation: Int,
        client: ArcBoxClient,
        stream: @escaping @Sendable (K8sClient) -> AsyncThrowingStream<[Model.Resource], any Error>
    ) async {
        guard let model else { return }
        var failures = 0

        while !Task.isCancelled, generation == self.generation {
            model.isLoading = true
            var delivered = false
            var used: K8sClient?

            do {
                let k8s = try await resolveClient(client, generation: generation)
                guard generation == self.generation else { return }
                used = k8s

                for try await items in stream(k8s) {
                    guard generation == self.generation else { return }
                    model.apply(items)
                    model.isLoading = false
                    delivered = true
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                Log.pods.error(
                    "Kubernetes \(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
                )
                ErrorReporting.capture(error, domain: .kubernetes, operation: operation)
                // Keep the last known list on screen. A dropped watch is routine — the idle
                // timeout alone will end a quiet one — and blanking the UI for every reconnect
                // is worse than briefly showing data that is a few seconds stale. Only an
                // actual teardown clears it.
                //
                // Drop the client so the next attempt re-fetches the kubeconfig and reconnects.
                if let used { invalidateClient(ifCurrent: used) }
            }

            guard !Task.isCancelled, generation == self.generation else { return }
            failures = delivered ? 1 : failures + 1
            try? await Task.sleep(for: Self.backoff(afterFailures: failures))
        }
    }

    private static func backoff(afterFailures failures: Int) -> Duration {
        let doubled = minBackoff * Double(1 << min(failures - 1, 3))
        return min(doubled, maxBackoff)
    }

    /// Both supervisors share one client. Only the supervisor that actually saw it fail may
    /// discard it, or a healthy stream's client would be thrown away underneath it.
    private func invalidateClient(ifCurrent client: K8sClient) {
        if k8sClient === client { k8sClient = nil }
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
}

/// A list fed by ``KubernetesState``'s watch supervisor. Lets one supervisor serve both
/// resources without the two loops being written out twice.
@MainActor
protocol K8sListModel: AnyObject {
    associatedtype Resource: K8sResource
    var isLoading: Bool { get set }
    func apply(_ items: [Resource])
    func clear()
}

extension PodsViewModel: K8sListModel {}
extension ServicesViewModel: K8sListModel {}
