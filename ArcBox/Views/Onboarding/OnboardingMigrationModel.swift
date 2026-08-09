import ArcBoxClient
import Foundation
import GRPCCore
import Observation

struct OnboardingMigrationPreview: Equatable {
    let source: DockerMigrationSource
    let daemonName: String
    let serverVersion: String
    let imageCount: UInt32
    let volumeCount: UInt32
    let networkCount: UInt32
    let containerCount: UInt32
    let warnings: [String]
    let unsupportedResources: [String]
    let replacementsRequired: Bool
    let stopsSourceContainers: Bool

    init(
        source: DockerMigrationSource,
        response: Arcbox_V1_PrepareMigrationResponse
    ) {
        self.source = source
        daemonName = response.plan.source.daemonName
        serverVersion = response.plan.source.serverVersion
        imageCount = response.imageCount
        volumeCount = response.volumeCount
        networkCount = response.networkCount
        containerCount = response.containerCount
        warnings = response.warnings
        unsupportedResources = response.unsupportedResources
        replacementsRequired = response.replacementsRequired
        stopsSourceContainers = !response.plan.blockers.isEmpty
    }

    var totalResourceCount: UInt64 {
        UInt64(imageCount)
            + UInt64(volumeCount)
            + UInt64(networkCount)
            + UInt64(containerCount)
    }

    var canRun: Bool {
        unsupportedResources.isEmpty
    }

    var confirmationMessages: [String] {
        var messages: [String] = []
        if replacementsRequired {
            messages.append("Matching ArcBox resources will be replaced.")
        }
        if stopsSourceContainers {
            messages.append("Source containers using migrated volumes will be stopped.")
        }
        return messages
    }

    func matches(_ response: Arcbox_V1_PrepareMigrationResponse) -> Bool {
        response.sourceKind == source.kind.rawValue
            && URL(fileURLWithPath: response.sourceSocketPath).standardizedFileURL.path
                == URL(fileURLWithPath: source.socketPath).standardizedFileURL.path
            && response.imageCount == imageCount
            && response.volumeCount == volumeCount
            && response.networkCount == networkCount
            && response.containerCount == containerCount
            && response.replacementsRequired == replacementsRequired
            && Set(response.warnings) == Set(warnings)
    }
}

struct OnboardingMigrationProgress: Equatable {
    let phase: String
    let resource: String
    let message: String
    let completed: UInt32
    let total: UInt32

    var fractionCompleted: Double? {
        guard total > 0 else { return nil }
        return min(Double(completed) / Double(total), 1)
    }
}

@Observable
@MainActor
final class OnboardingMigrationModel {
    enum State: Equatable {
        case idle
        case checking
        case unavailable
        case empty(DockerMigrationSource)
        case review(OnboardingMigrationPreview)
        case preparing(OnboardingMigrationPreview)
        case migrating(OnboardingMigrationPreview, OnboardingMigrationProgress)
        case completed(OnboardingMigrationPreview, warnings: [String])
        case failed(OnboardingMigrationPreview?, message: String)

        var isExecuting: Bool {
            switch self {
            case .preparing, .migrating:
                true
            default:
                false
            }
        }
    }

    private(set) var state: State = .idle {
        didSet {
            guard oldValue.isExecuting != state.isExecuting else { return }
            onMigrationActivityChanged(state.isExecuting)
        }
    }

    @ObservationIgnored
    private let clientProvider: @MainActor () -> ArcBoxClient?

    @ObservationIgnored
    private let onMigrationActivityChanged: @MainActor (Bool) -> Void

    private static var prepareCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(120)
        return options
    }

    init(
        clientProvider: @escaping @MainActor () -> ArcBoxClient?,
        onMigrationActivityChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.clientProvider = clientProvider
        self.onMigrationActivityChanged = onMigrationActivityChanged
    }

    func loadPreview() async {
        if case .checking = state { return }
        state = .checking

        let source: DockerMigrationSource
        do {
            guard let detectedSource = try await DockerContextManager.detectMigrationSource()
            else {
                state = .unavailable
                return
            }
            source = detectedSource
        } catch is CancellationError {
            return
        } catch {
            state = .failed(nil, message: error.localizedDescription)
            return
        }
        guard !Task.isCancelled else { return }
        guard let client = clientProvider() else {
            state = .failed(nil, message: "ArcBox runtime is not ready.")
            return
        }

        var request = Arcbox_V1_PrepareMigrationRequest()
        request.sourceKind = source.kind.rawValue
        request.sourceSocketPath = source.socketPath
        request.allowReplacements = true
        request.dryRun = true

        do {
            let response = try await client.migration.prepareMigration(
                request,
                options: Self.prepareCallOptions
            )
            guard !Task.isCancelled else { return }
            guard response.hasPlan else {
                state = .failed(
                    nil,
                    message: "ArcBox returned an incomplete migration preview."
                )
                return
            }

            let preview = OnboardingMigrationPreview(source: source, response: response)
            if preview.totalResourceCount == 0 && preview.unsupportedResources.isEmpty {
                state = .empty(source)
            } else {
                state = .review(preview)
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(nil, message: ArcBoxClient.userMessage(for: error))
        }
    }

    func startMigration() {
        guard case .review(let preview) = state else { return }
        state = .preparing(preview)
        Task { await runMigration(preview) }
    }

    func retry() {
        Task { await loadPreview() }
    }

    private func runMigration(_ preview: OnboardingMigrationPreview) async {
        guard preview.canRun else { return }
        guard let client = clientProvider() else {
            state = .failed(preview, message: "ArcBox runtime is not ready.")
            return
        }

        let prepared: Arcbox_V1_PrepareMigrationResponse
        do {
            var prepareRequest = Arcbox_V1_PrepareMigrationRequest()
            prepareRequest.sourceKind = preview.source.kind.rawValue
            prepareRequest.sourceSocketPath = preview.source.socketPath
            prepareRequest.allowReplacements = true

            prepared = try await client.migration.prepareMigration(
                prepareRequest,
                options: Self.prepareCallOptions
            )
            guard !Task.isCancelled else { return }
            guard prepared.unsupportedResources.isEmpty else {
                state = .failed(
                    nil,
                    message: prepared.unsupportedResources.joined(separator: "\n")
                )
                return
            }
            guard preview.matches(prepared) else {
                state = .failed(
                    nil,
                    message:
                        "The source environment changed after the preview. "
                        + "Review the updated migration plan before continuing."
                )
                return
            }
            guard !prepared.planID.isEmpty else {
                state = .failed(
                    preview,
                    message: "ArcBox did not return an executable migration plan."
                )
                return
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(preview, message: ArcBoxClient.userMessage(for: error))
            return
        }

        var runRequest = Arcbox_V1_RunMigrationRequest()
        runRequest.planID = prepared.planID
        runRequest.allowReplacements = true

        state = .migrating(
            preview,
            OnboardingMigrationProgress(
                phase: "prepare",
                resource: "",
                message: "Starting migration…",
                completed: 0,
                total: 0
            )
        )

        await observeMigration(client: client, request: runRequest, preview: preview)
    }

    private func observeMigration(
        client: ArcBoxClient,
        request: Arcbox_V1_RunMigrationRequest,
        preview: OnboardingMigrationPreview
    ) async {
        var retryDelaySeconds: UInt64 = 1
        while !Task.isCancelled {
            do {
                let reachedTerminalEvent = try await client.migration.runMigration(
                    request
                ) { response in
                    for try await event in response.messages {
                        try Task.checkCancellation()
                        await self.receive(event, preview: preview)
                        if event.done { return true }
                    }
                    return false
                }
                if reachedTerminalEvent { return }
                retryDelaySeconds = 1
            } catch let error as RPCError {
                if error.code == .notFound {
                    state = .failed(
                        preview,
                        message:
                            "The ArcBox daemon restarted before migration completed. "
                            + "Review the source environment before trying again."
                    )
                    return
                }
                guard Self.shouldReconnect(after: error.code) else {
                    state = .failed(preview, message: ArcBoxClient.userMessage(for: error))
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                state = .failed(preview, message: ArcBoxClient.userMessage(for: error))
                return
            }

            state = .migrating(
                preview,
                OnboardingMigrationProgress(
                    phase: "reconnecting",
                    resource: "",
                    message: "Reconnecting to the migration…",
                    completed: 0,
                    total: 0
                )
            )
            do {
                try await Task.sleep(for: .seconds(retryDelaySeconds))
            } catch {
                return
            }
            retryDelaySeconds = min(retryDelaySeconds * 2, 8)
        }
    }

    nonisolated static func shouldReconnect(after code: RPCError.Code) -> Bool {
        code == .unavailable
    }

    private func receive(
        _ event: Arcbox_V1_RunMigrationEvent,
        preview: OnboardingMigrationPreview
    ) {
        if event.done {
            if event.success {
                state = .completed(preview, warnings: event.warnings)
            } else {
                state = .failed(
                    preview,
                    message: event.message.isEmpty ? "Migration failed." : event.message
                )
            }
            return
        }

        state = .migrating(
            preview,
            OnboardingMigrationProgress(
                phase: event.phase,
                resource: event.resource,
                message: event.message,
                completed: event.completed,
                total: event.total
            )
        )
    }
}
