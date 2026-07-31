import XCTest

@testable import ArcBox

/// Create and pull operations used to return `nil`/`false` on failure without touching
/// `lastError`, so the error toast either stayed silent or showed the previous operation's
/// message. Each one must now clear `lastError` on entry and populate it on every failure path.
@MainActor
final class CreateOperationErrorTests: XCTestCase {

    private var containerOptions: ContainerCreateOptions {
        ContainerCreateOptions(
            image: "alpine:latest",
            name: "",
            platform: nil,
            command: "",
            entrypoint: "",
            workingDir: "",
            autoRemove: false,
            restartPolicy: "no",
            privileged: false,
            readOnlyRootfs: false,
            dockerInit: false
        )
    }

    // MARK: - Failures are reported

    func testCreateContainerReportsFailure() async {
        let vm = ContainersViewModel()
        let id = await vm.createContainer(options: containerOptions, docker: nil)
        XCTAssertNil(id)
        XCTAssertNotNil(vm.lastError)
    }

    func testPullImageReportsFailure() async {
        let vm = ImagesViewModel()
        let ok = await vm.pullImage("alpine:latest", platform: nil, docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testCreateVolumeReportsFailure() async {
        let vm = VolumesViewModel()
        let ok = await vm.createVolume(name: "data", docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testCreateNetworkReportsFailure() async {
        let vm = NetworksViewModel()
        let ok = await vm.createNetwork(name: "bridge-1", enableIPv6: false, docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testCreateNetworkRejectsBlankName() async {
        let vm = NetworksViewModel()
        let ok = await vm.createNetwork(name: "   ", enableIPv6: false, docker: nil)
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.lastError, "Network name is required.")
    }

    // MARK: - Stale errors are cleared

    /// The reported symptom: the toast showed a message left over from an earlier action.
    func testCreateNetworkReplacesAStaleError() async {
        let vm = NetworksViewModel()
        vm.lastError = "left over from a previous delete"
        _ = await vm.createNetwork(name: "   ", enableIPv6: false, docker: nil)
        XCTAssertEqual(vm.lastError, "Network name is required.")
    }

    func testCreateContainerDoesNotKeepAStaleError() async {
        let vm = ContainersViewModel()
        vm.lastError = "left over from a previous stop"
        _ = await vm.createContainer(options: containerOptions, docker: nil)
        XCTAssertNotEqual(vm.lastError, "left over from a previous stop")
    }

    func testPullImageDoesNotKeepAStaleError() async {
        let vm = ImagesViewModel()
        vm.lastError = "left over from a previous remove"
        _ = await vm.pullImage("alpine:latest", platform: nil, docker: nil)
        XCTAssertNotEqual(vm.lastError, "left over from a previous remove")
    }

    func testCreateVolumeDoesNotKeepAStaleError() async {
        let vm = VolumesViewModel()
        vm.lastError = "left over from a previous delete"
        _ = await vm.createVolume(name: "data", docker: nil)
        XCTAssertNotEqual(vm.lastError, "left over from a previous delete")
    }
}
