import XCTest

@testable import ArcBox

final class LayeredRootFSTests: XCTestCase {
    // MARK: merge precedence

    private func item(
        _ name: String, isWhiteout: Bool = false, layer: String = "l"
    )
        -> LocalRootFSService.LayerItem
    {
        let entry = LocalFileEntry(
            url: URL(fileURLWithPath: "/\(layer)/\(name)"),
            name: name,
            isDirectory: false,
            isPackage: false,
            isSymbolicLink: false,
            sizeBytes: 0,
            modifiedDate: nil,
            kind: "Document",
            children: nil,
            loadError: nil
        )
        return LocalRootFSService.LayerItem(entry: entry, isWhiteout: isWhiteout)
    }

    func testHigherLayerWinsSameName() {
        let merged = LayeredRootFS.merge([
            [item("app.conf", layer: "upper")],
            [item("app.conf", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["app.conf"])
        // The container's own copy must win over the image's, or the tab
        // would show pre-edit content for every modified file.
        XCTAssertEqual(merged[0].url.path, "/upper/app.conf")
    }

    func testLayersUnionDistinctNames() {
        let merged = LayeredRootFS.merge([
            [item("written-by-container", layer: "upper")],
            [item("from-image", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["from-image", "written-by-container"])
    }

    func testWhiteoutHidesItselfAndLowerEntry() {
        // Deleting an image file inside a container leaves a whiteout in the
        // upper layer; both it and the file it deletes must disappear.
        let merged = LayeredRootFS.merge([
            [item("deleted", isWhiteout: true, layer: "upper")],
            [item("deleted", layer: "lower"), item("kept", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["kept"])
    }

    func testWhiteoutOnlyShadowsLowerLayers() {
        // A whiteout in a middle layer must not hide a higher layer's file.
        let merged = LayeredRootFS.merge([
            [item("resurrected", layer: "upper")],
            [item("resurrected", isWhiteout: true, layer: "mid")],
            [item("resurrected", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["resurrected"])
        XCTAssertEqual(merged[0].url.path, "/upper/resurrected")
    }

    func testMergedEntriesAreSortedByName() {
        let merged = LayeredRootFS.merge([
            [item("zeta", layer: "upper")],
            [item("alpha", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["alpha", "zeta"])
    }

    // MARK: relative path mapping

    func testRelativePathResolvesAcrossLayers() throws {
        let unwrapped = try XCTUnwrap(
            LayeredRootFS(layers: [
                URL(fileURLWithPath: "/mnt/upper"),
                URL(fileURLWithPath: "/mnt/lower"),
            ]))

        XCTAssertEqual(unwrapped.relativePath(forHostURL: URL(fileURLWithPath: "/mnt/upper")), "")
        XCTAssertEqual(
            unwrapped.relativePath(forHostURL: URL(fileURLWithPath: "/mnt/lower/etc/nginx")),
            "etc/nginx"
        )
        // A URL from outside the stack must not be mistaken for layer content.
        XCTAssertNil(unwrapped.relativePath(forHostURL: URL(fileURLWithPath: "/elsewhere/etc")))
    }

    func testRelativePathDoesNotMatchSiblingPrefix() throws {
        // "/mnt/upper-backup" shares a string prefix with "/mnt/upper" but is
        // a different directory; treating it as layer content would browse
        // the wrong tree.
        let stack = try XCTUnwrap(LayeredRootFS(layers: [URL(fileURLWithPath: "/mnt/upper")]))

        XCTAssertNil(
            stack.relativePath(forHostURL: URL(fileURLWithPath: "/mnt/upper-backup/etc")))
    }

    func testEmptyStackIsRejected() {
        XCTAssertNil(LayeredRootFS(layers: []))
    }

    func testSingleLayerIsNotComposed() throws {
        let stack = try XCTUnwrap(LayeredRootFS(layers: [URL(fileURLWithPath: "/mnt/only")]))
        XCTAssertFalse(stack.isComposed)
    }

    // MARK: on-disk merge

    func testListDirectoryMergesRealDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let upper = root.appendingPathComponent("upper/etc", isDirectory: true)
        let lower = root.appendingPathComponent("lower/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: upper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "container".write(to: upper.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "image".write(to: lower.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "image".write(to: lower.appendingPathComponent("resolv.conf"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("upper", isDirectory: true),
                root.appendingPathComponent("lower", isDirectory: true),
            ]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), ["hosts", "resolv.conf"])
        XCTAssertEqual(try String(contentsOf: listing.entries[0].url, encoding: .utf8), "container")
        XCTAssertEqual(listing.unreadableLayers, [])
    }

    func testListDirectorySkipsLayersMissingTheDirectory() throws {
        // Most layers do not carry most directories; a layer without the path
        // must contribute nothing rather than failing the whole listing.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lower = root.appendingPathComponent("lower/opt", isDirectory: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("upper", isDirectory: true),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "x".write(to: lower.appendingPathComponent("tool"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("upper", isDirectory: true),
                root.appendingPathComponent("lower", isDirectory: true),
            ]))

        let listing = stack.listDirectory(relativePath: "opt", showHiddenFiles: false)
        XCTAssertEqual(listing.entries.map(\.name), ["tool"])
        // A layer that simply lacks the path is normal, not a read failure —
        // counting it would put a permanent warning on every browse.
        XCTAssertEqual(listing.unreadableLayers, [])
    }

    // MARK: whiteout classification

    func testRealCharacterDeviceIsNotAWhiteout() throws {
        // Overlay whiteouts are character devices of rdev 0:0. Layers also
        // carry legitimate character devices (an image shipping /dev/null,
        // a privileged container's nodes); classifying those as deletions
        // would hide both the device and whatever it shadows below.
        let devices = try LocalRootFSService.listLayerItems(
            at: URL(fileURLWithPath: "/dev"), showHiddenFiles: true)
        let null = try XCTUnwrap(devices.first { $0.entry.name == "null" })

        XCTAssertFalse(null.isWhiteout)
    }

    func testRegularFileIsNotAWhiteout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("file"), atomically: true, encoding: .utf8)

        let items = try LocalRootFSService.listLayerItems(at: root, showHiddenFiles: false)

        XCTAssertEqual(items.map(\.isWhiteout), [false])
    }

    func testListDirectoryCountsUnreadableLayers() throws {
        // A path that exists but will not list (here: a regular file where a
        // directory is expected) is a real hole in the merge — the caller has
        // to be able to tell the user the view is incomplete.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let good = root.appendingPathComponent("good/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("broken", isDirectory: true),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "x".write(to: good.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "not a directory".write(
            to: root.appendingPathComponent("broken/etc"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("good", isDirectory: true),
                root.appendingPathComponent("broken", isDirectory: true),
            ]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), ["hosts"])
        // Identify *which* layer failed: a caller browsing several
        // directories unions these, and a bare count would collapse
        // failures in different layers into one.
        XCTAssertEqual(listing.unreadableLayers, [1])
    }

    func testDistinctDirectoriesReportDistinctFailingLayers() throws {
        // The case a bare count loses: /etc fails on one layer and /opt on
        // another, so a caller unioning these sees two layers with holes,
        // not one.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let a = root.appendingPathComponent("a", isDirectory: true)
        let b = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(
            at: a.appendingPathComponent("opt"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: b.appendingPathComponent("etc"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Each layer has one path that exists but cannot be listed.
        try "x".write(to: a.appendingPathComponent("etc"), atomically: true, encoding: .utf8)
        try "x".write(to: b.appendingPathComponent("opt"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(LayeredRootFS(layers: [a, b]))

        XCTAssertEqual(
            stack.listDirectory(relativePath: "etc", showHiddenFiles: false).unreadableLayers, [0])
        XCTAssertEqual(
            stack.listDirectory(relativePath: "opt", showHiddenFiles: false).unreadableLayers, [1])
    }
}
