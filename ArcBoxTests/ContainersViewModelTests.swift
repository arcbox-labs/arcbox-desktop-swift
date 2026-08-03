import ArcBoxClient
import DockerClient
import SwiftProtobuf
import XCTest

@testable import ArcBox

@MainActor
final class ContainersViewModelTests: XCTestCase {

    private var vm: ContainersViewModel!

    override func setUp() {
        super.setUp()
        vm = ContainersViewModel()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(vm.containers.isEmpty)
        XCTAssertNil(vm.selectedID)
        XCTAssertEqual(vm.runningCount, 0)
        XCTAssertEqual(vm.loadState, .waiting)
        XCTAssertNil(vm.refreshError)
        XCTAssertNil(vm.lastError)
    }

    // MARK: - Load Phase

    func testInitialLoadFailureBecomesBlockingError() {
        var phase = LoadPhase.waiting

        let retainingLoadedContent = phase.beginLoading()
        let refreshError = phase.fail(
            "connection refused",
            retainingLoadedContent: retainingLoadedContent
        )

        XCTAssertEqual(phase, .failed("connection refused"))
        XCTAssertNil(refreshError)
    }

    func testRefreshFailureKeepsLoadedContentAndReturnsWarning() {
        var phase = LoadPhase.loaded

        let retainingLoadedContent = phase.beginLoading()
        let refreshError = phase.fail(
            "connection reset",
            retainingLoadedContent: retainingLoadedContent
        )

        XCTAssertEqual(phase, .loaded)
        XCTAssertEqual(refreshError, "connection reset")
    }

    func testSingleFlightLoadGateCoalescesPendingWorkAndWaitsForRound() async {
        let gate = SingleFlightLoadGate()
        var events: [String] = []
        var releaseFirst = false

        let first = Task {
            await gate.run {
                events.append("first ran")
                while !releaseFirst {
                    await Task.yield()
                }
            }
            events.append("first returned")
        }
        while !events.contains("first ran") {
            await Task.yield()
        }

        let middle = Task {
            events.append("middle called")
            await gate.run {
                events.append("middle ran")
            }
            events.append("middle returned")
        }
        while !events.contains("middle called") {
            await Task.yield()
        }

        let latest = Task {
            events.append("latest called")
            await gate.run {
                events.append("latest ran")
            }
            events.append("latest returned")
        }
        while !events.contains("latest called") {
            await Task.yield()
        }

        XCTAssertFalse(events.contains("middle returned"))
        XCTAssertFalse(events.contains("latest returned"))
        releaseFirst = true

        await first.value
        await middle.value
        await latest.value

        XCTAssertFalse(events.contains("middle ran"))
        XCTAssertTrue(events.contains("latest ran"))
        XCTAssertTrue(events.contains("middle returned"))
        XCTAssertTrue(events.contains("latest returned"))
    }

    func testSingleFlightLoadGateRunsPendingWorkAfterFirstWaiterIsCancelled() async {
        let gate = SingleFlightLoadGate()
        var events: [String] = []
        var releaseFirst = false

        let first = Task {
            await gate.run {
                events.append("first ran")
                while !releaseFirst {
                    if Task.isCancelled {
                        events.append("first cancelled")
                        return
                    }
                    await Task.yield()
                }
            }
        }
        while !events.contains("first ran") {
            await Task.yield()
        }

        let pending = Task {
            events.append("pending called")
            await gate.run {
                events.append(Task.isCancelled ? "pending cancelled" : "pending ran")
            }
        }
        while !events.contains("pending called") {
            await Task.yield()
        }

        first.cancel()
        releaseFirst = true
        await first.value
        await pending.value

        XCTAssertTrue(events.contains("pending ran"))
        XCTAssertFalse(events.contains("pending cancelled"))
    }

    // MARK: - Selection

    func testSelectContainer() {
        vm.selectContainer("test-id")
        XCTAssertEqual(vm.selectedID, "test-id")
    }

    func testSelectContainerOverwritesPrevious() {
        vm.selectContainer("first")
        vm.selectContainer("second")
        XCTAssertEqual(vm.selectedID, "second")
    }

    func testSelectedContainerNilWhenNoMatch() {
        vm.selectContainer("nonexistent")
        XCTAssertNil(vm.selectedContainer)
    }

    func testSelectedContainerReturnsMatch() {
        let c = makeContainer(id: "c1", name: "nginx")
        vm.containers = [c]
        vm.selectContainer("c1")
        XCTAssertEqual(vm.selectedContainer?.id, "c1")
    }

    // MARK: - Group Toggling

    func testToggleGroupExpands() {
        XCTAssertFalse(vm.isGroupExpanded("project-a"))
        vm.toggleGroup("project-a")
        XCTAssertTrue(vm.isGroupExpanded("project-a"))
    }

    func testToggleGroupCollapses() {
        vm.toggleGroup("project-a")
        vm.toggleGroup("project-a")
        XCTAssertFalse(vm.isGroupExpanded("project-a"))
    }

    func testMultipleGroupsIndependent() {
        vm.toggleGroup("a")
        vm.toggleGroup("b")
        XCTAssertTrue(vm.isGroupExpanded("a"))
        XCTAssertTrue(vm.isGroupExpanded("b"))
        vm.toggleGroup("a")
        XCTAssertFalse(vm.isGroupExpanded("a"))
        XCTAssertTrue(vm.isGroupExpanded("b"))
    }

    // MARK: - Running Count

    func testRunningCountZeroWhenEmpty() {
        XCTAssertEqual(vm.runningCount, 0)
    }

    func testRunningCountReflectsState() {
        vm.containers = [
            makeContainer(id: "1", name: "a", state: .running),
            makeContainer(id: "2", name: "b", state: .stopped),
            makeContainer(id: "3", name: "c", state: .running),
        ]
        XCTAssertEqual(vm.runningCount, 2)
    }

    // MARK: - Search Filtering

    func testSearchEmptyReturnsAll() {
        vm.containers = [
            makeContainer(id: "1", name: "nginx"),
            makeContainer(id: "2", name: "redis"),
        ]
        vm.searchText = ""
        XCTAssertEqual(vm.standaloneContainers.count, 2)
    }

    func testSearchFiltersByName() {
        vm.containers = [
            makeContainer(id: "1", name: "nginx-web"),
            makeContainer(id: "2", name: "redis-cache", image: "redis:7"),
        ]
        vm.searchText = "nginx"
        XCTAssertEqual(vm.standaloneContainers.count, 1)
        XCTAssertEqual(vm.standaloneContainers.first?.name, "nginx-web")
    }

    func testSearchFiltersByImage() {
        vm.containers = [
            makeContainer(id: "1", name: "web", image: "nginx:latest"),
            makeContainer(id: "2", name: "cache", image: "redis:7"),
        ]
        vm.searchText = "redis"
        XCTAssertEqual(vm.standaloneContainers.count, 1)
        XCTAssertEqual(vm.standaloneContainers.first?.name, "cache")
    }

    func testSearchIsCaseInsensitive() {
        vm.containers = [
            makeContainer(id: "1", name: "NGINX")
        ]
        vm.searchText = "nginx"
        XCTAssertEqual(vm.standaloneContainers.count, 1)
    }

    // MARK: - Compose Groups

    func testComposeGroupsSeparated() {
        vm.containers = [
            makeContainer(id: "1", name: "web", composeProject: "myapp"),
            makeContainer(id: "2", name: "db", composeProject: "myapp"),
            makeContainer(id: "3", name: "standalone"),
        ]
        XCTAssertEqual(vm.composeGroups.count, 1)
        XCTAssertEqual(vm.composeGroups.first?.project, "myapp")
        XCTAssertEqual(vm.composeGroups.first?.containers.count, 2)
        XCTAssertEqual(vm.standaloneContainers.count, 1)
    }

    func testComposeGroupsFilteredBySearch() {
        vm.containers = [
            makeContainer(id: "1", name: "web", composeProject: "frontend"),
            makeContainer(id: "2", name: "api", composeProject: "backend"),
        ]
        vm.searchText = "web"
        XCTAssertEqual(vm.composeGroups.count, 1)
        XCTAssertEqual(vm.composeGroups.first?.project, "frontend")
    }

    func testSearchByComposeProject() {
        vm.containers = [
            makeContainer(id: "1", name: "svc", composeProject: "myproject")
        ]
        vm.searchText = "myproject"
        XCTAssertEqual(vm.composeGroups.count, 1)
    }

    func testDescendingSortUsesStableIDTieBreak() {
        vm.sortAscending = false

        for ids in [["a", "b"], ["b", "a"]] {
            let containers = ids.map { makeContainer(id: $0, name: "same") }
            XCTAssertEqual(vm.sortedContainers(containers).map(\.id), ["b", "a"])
        }
    }

    // MARK: - DNS Domains

    func testHostDomainPlainContainer() {
        let c = makeContainer(id: "1", name: "nginx")
        XCTAssertEqual(c.hostDomain(useDNS: true), "nginx.arcbox.local")
        XCTAssertEqual(c.hostDomain(useDNS: false), "localhost")
    }

    func testHostDomainComposeContainer() {
        let c = makeContainer(
            id: "1", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        XCTAssertEqual(c.hostDomain(useDNS: true), "web.myapp.arcbox.local")
        XCTAssertEqual(c.hostDomain(useDNS: false), "localhost")
    }

    func testAllDomainsPlainContainer() {
        let c = makeContainer(id: "1", name: "redis")
        let domains = c.allDomains(useDNS: true)
        XCTAssertEqual(domains, ["redis.arcbox.local"])
    }

    func testAllDomainsComposeContainer() {
        let c = makeContainer(
            id: "1", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        let domains = c.allDomains(useDNS: true)
        XCTAssertEqual(
            domains,
            [
                "web.myapp.arcbox.local",
                "myapp-web-1.arcbox.local",
            ])
    }

    func testAllDomainsDNSDisabled() {
        let c = makeContainer(
            id: "1", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        XCTAssertEqual(c.allDomains(useDNS: false), ["localhost"])
    }

    func testIsComposeFlag() {
        let plain = makeContainer(id: "1", name: "nginx")
        XCTAssertFalse(plain.isCompose)

        let compose = makeContainer(
            id: "2", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        XCTAssertTrue(compose.isCompose)

        let partialProject = makeContainer(id: "3", name: "x", composeProject: "proj")
        XCTAssertFalse(partialProject.isCompose)

        let partialService = makeContainer(id: "4", name: "x", composeService: "svc")
        XCTAssertFalse(partialService.isCompose)
    }

    // MARK: - Last Error

    func testLastErrorClearing() {
        vm.lastError = "previous error"
        vm.selectContainer("x")
        XCTAssertEqual(vm.lastError, "previous error")
    }

    func testContainerStartResponseRejectsDocumentedFailures() {
        let notFound = Operations.ContainerStart.Output.notFound(
            .init(body: .json(.init(message: "No such container.")))
        )
        let serverError = Operations.ContainerStart.Output.internalServerError(
            .init(body: .json(.init(message: "Runtime failed.")))
        )

        XCTAssertEqual(notFound.startFailureMessage, "No such container.")
        XCTAssertEqual(serverError.startFailureMessage, "Runtime failed.")
        XCTAssertNil(Operations.ContainerStart.Output.noContent.startFailureMessage)
        XCTAssertNil(Operations.ContainerStart.Output.notModified.startFailureMessage)
    }

    func testContainerStopAndDeleteResponseClassification() {
        let stopFailure = Operations.ContainerStop.Output.internalServerError(
            .init(body: .json(.init(message: "Stop failed.")))
        )
        let deleteFailure = Operations.ContainerDelete.Output.conflict(
            .init(body: .json(.init(message: "Container is running.")))
        )

        XCTAssertNil(Operations.ContainerStop.Output.noContent.stopFailureMessage)
        XCTAssertNil(Operations.ContainerStop.Output.notModified.stopFailureMessage)
        XCTAssertEqual(stopFailure.stopFailureMessage, "Stop failed.")
        XCTAssertEqual(
            Operations.ContainerStop.Output.undocumented(statusCode: 418, .init()).stopFailureMessage,
            "Unexpected response status 418."
        )

        XCTAssertNil(Operations.ContainerDelete.Output.noContent.deleteFailureMessage)
        XCTAssertEqual(deleteFailure.deleteFailureMessage, "Container is running.")
        XCTAssertEqual(
            Operations.ContainerDelete.Output.undocumented(statusCode: 418, .init()).deleteFailureMessage,
            "Unexpected response status 418."
        )
    }

    // MARK: - Helpers

    private func makeContainer(
        id: String,
        name: String,
        image: String = "nginx:latest",
        state: ContainerState = .stopped,
        composeProject: String? = nil,
        composeService: String? = nil
    ) -> ContainerViewModel {
        ContainerViewModel(
            id: id,
            name: name,
            image: image,
            state: state,
            ports: [],
            createdAt: Date(),
            composeProject: composeProject,
            composeService: composeService,
            labels: [:],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
    }
}

@MainActor
final class SandboxesLoadStateTests: XCTestCase {
    func testDescendingSortUsesIDAsTieBreaker() {
        var alpha = Arcbox_Sandbox_V1_SandboxSummary()
        alpha.id = "alpha"
        alpha.labels = ["name": "same"]
        var beta = Arcbox_Sandbox_V1_SandboxSummary()
        beta.id = "beta"
        beta.labels = ["name": "same"]

        let vm = SandboxesViewModel()
        vm.sandboxes = [SandboxViewModel(from: alpha), SandboxViewModel(from: beta)]
        vm.sortAscending = false

        XCTAssertEqual(vm.sortedSandboxes.map(\.id), ["beta", "alpha"])
    }

    func testCreateReportsUnavailableDaemon() async {
        let vm = SandboxesViewModel()

        let id = await vm.createSandbox(SandboxCreateSpec(), client: nil)

        XCTAssertNil(id)
        XCTAssertEqual(vm.lastError, "ArcBox daemon is unavailable.")
    }

    func testUnavailableClientDoesNotResolveEmptyListAsLoaded() async {
        let vm = SandboxesViewModel()

        await vm.loadSandboxes(client: nil)

        XCTAssertEqual(vm.loadState, .waiting)
        XCTAssertTrue(vm.sandboxes.isEmpty)
    }

    func testUnavailableClientClearsStaleSnapshotsAndWaitsForNewTarget() async {
        var summary = Arcbox_Sandbox_V1_SnapshotSummary()
        summary.id = "snapshot-1"
        summary.sandboxID = "old-sandbox"
        summary.name = "old"

        let vm = SandboxesViewModel()
        vm.snapshots = [SandboxSnapshotViewModel(from: summary)]
        vm.snapshotsSandboxID = "old-sandbox"
        vm.snapshotsLoadState = .loaded
        vm.snapshotsRefreshError = "old error"

        await vm.loadSnapshots(for: "new-sandbox", client: nil)

        XCTAssertEqual(vm.snapshotsSandboxID, "new-sandbox")
        XCTAssertEqual(vm.snapshotsLoadState, .waiting)
        XCTAssertNil(vm.snapshotsRefreshError)
        XCTAssertTrue(vm.snapshots.isEmpty)
    }

    func testSandboxModelMapsTypedStateTimestampAndSignalExit() throws {
        let createdAt = Date(timeIntervalSince1970: 1_756_700_123.25)
        var info = Arcbox_Sandbox_V1_SandboxInfo()
        info.id = "sandbox-1"
        info.state = .running
        info.createdAt = .init(date: createdAt)
        info.lastExitedAt = .init(date: createdAt.addingTimeInterval(30))
        info.lastExitStatus.signal = 9

        let sandbox = SandboxViewModel(from: info)
        let mappedCreatedAt = try XCTUnwrap(sandbox.createdAt)

        XCTAssertEqual(sandbox.state, .running)
        XCTAssertTrue(sandbox.state.isDataPlaneReady)
        XCTAssertFalse(sandbox.state.canRemove)
        XCTAssertEqual(mappedCreatedAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(sandbox.lastExitStatus, .signal(9))
    }

    func testSandboxModelKeepsAbsentTimestampNilAndUnknownState() {
        var summary = Arcbox_Sandbox_V1_SandboxSummary()
        summary.id = "sandbox-1"
        summary.state = .UNRECOGNIZED(99)

        let sandbox = SandboxViewModel(from: summary)

        XCTAssertEqual(sandbox.state, .unknown)
        XCTAssertFalse(sandbox.state.isActive)
        XCTAssertFalse(sandbox.state.isDataPlaneReady)
        XCTAssertFalse(sandbox.state.canRemove)
        XCTAssertNil(sandbox.createdAt)
    }

    func testSandboxEventMapsTypedKindAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_756_700_456.5)
        var event = Arcbox_Sandbox_V1_SandboxEvent()
        event.sandboxID = "sandbox-1"
        event.kind = .idle
        event.time = .init(date: timestamp)

        let record = SandboxEventRecord(from: event)

        XCTAssertEqual(record.sandboxID, "sandbox-1")
        XCTAssertEqual(record.kind, .idle)
        XCTAssertEqual(record.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }
}
