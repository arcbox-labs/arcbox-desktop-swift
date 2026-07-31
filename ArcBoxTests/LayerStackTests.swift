import XCTest

@testable import ArcBox

final class LayerStackTests: XCTestCase {
    func testFreshStackDescribesNothing() {
        let stack = LayerStack()

        XCTAssertNil(stack.rootURL)
        XCTAssertNil(stack.layers)
        XCTAssertFalse(stack.describesAStack)
        XCTAssertEqual(stack.missingLayers, 0)
    }

    func testSingleLayerSubjectDescribesNoStack() async throws {
        // Nothing to be incomplete about, so nothing to tell the user.
        let export = try makeGuestExport(containing: ["volumes"])
        let stack = await LayerStack.resolve(
            guestPaths: ["/var/lib/docker/volumes"], exportRoot: export)

        XCTAssertNotNil(stack.rootURL)
        XCTAssertNil(stack.layers)
        XCTAssertFalse(stack.describesAStack)
        XCTAssertEqual(stack.missingLayers, 0)
    }

    func testTruncationToASingleLayerStillDescribesTheStack() async throws {
        // The case the badge used to go silent on: one browsable layer left,
        // so there is no merged stack to hang a warning off — but most of the
        // filesystem is missing and the user has to be told.
        let export = try makeGuestExport(containing: ["volumes"])
        let stack = await LayerStack.resolve(
            guestPaths: [
                "/var/lib/docker/volumes",
                "/somewhere/else/layer1",
                "/somewhere/else/layer2",
            ], exportRoot: export)

        XCTAssertNotNil(stack.rootURL)
        XCTAssertTrue(stack.describesAStack)
        XCTAssertEqual(stack.reportedLayers, 3)
        XCTAssertEqual(stack.missingLayers, 2)
    }

    func testExclusionsUnionAcrossListings() {
        // Two directories failing on two different layers are two layers with
        // holes; keeping the worst single count would report one.
        var stack = LayerStack()
        stack.exclude([0])
        stack.exclude([2])
        stack.exclude([0])

        XCTAssertEqual(stack.excludedIndices, [0, 2])
        XCTAssertEqual(stack.missingLayers, 2)
    }

    func testUnresolvedDistinguishesPathProblemsFromAMissingExport() {
        XCTAssertEqual(LayerStack.unresolved(guestPaths: []), .noPaths)
        // Outside the exported roots: a path problem, no VM restart will fix.
        XCTAssertEqual(
            LayerStack.unresolved(guestPaths: ["/somewhere/else"]), .outsideExport)
        // Maps fine but is not there: the export is not mounted.
        XCTAssertEqual(
            LayerStack.unresolved(guestPaths: ["/var/lib/docker/definitely-absent-\(UUID())"]),
            .exportUnavailable)
    }

    func testAnUnbrowsableStackDescribesNothing() async {
        // Nothing was merged, so a badge reading "merged from 0 of 2 layers"
        // beside the unresolved-filesystem error would state something that
        // did not happen.
        let stack = await LayerStack.resolve(guestPaths: [
            "/somewhere/else/upper",
            "/somewhere/else/lower",
        ])

        XCTAssertNil(stack.rootURL)
        XCTAssertEqual(stack.reportedLayers, 2)
        XCTAssertFalse(stack.describesAStack)
    }
}
