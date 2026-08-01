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
