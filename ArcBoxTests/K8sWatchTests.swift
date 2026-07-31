import XCTest

@testable import K8sClient

@available(macOS 15.0, *)
final class K8sWatchTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.kubernetes.decode(type, from: Data(json.utf8))
    }

    // MARK: - Event dispatch

    /// The envelope has to decode the type without touching `object`, because `object` is a
    /// Status on ERROR events and would fail to decode as the watched resource.
    func testEnvelopeDecodesTypeOfAnErrorEventCarryingAStatus() throws {
        let line = """
            {"type":"ERROR","object":{"kind":"Status","message":"too old resource version","code":410}}
            """
        XCTAssertEqual(try decode(WatchEventEnvelope.self, line).type, .error)

        let status = try decode(WatchEvent<K8sStatus>.self, line).object
        XCTAssertEqual(status.code, 410)
        XCTAssertEqual(status.message, "too old resource version")
    }

    func testEnvelopeDecodesEachEventType() throws {
        let cases: [(String, WatchEventType)] = [
            ("ADDED", .added), ("MODIFIED", .modified), ("DELETED", .deleted),
            ("BOOKMARK", .bookmark), ("ERROR", .error),
        ]
        for (wire, expected) in cases {
            let line = "{\"type\":\"\(wire)\",\"object\":{}}"
            XCTAssertEqual(try decode(WatchEventEnvelope.self, line).type, expected, wire)
        }
    }

    func testBookmarkCarriesOnlyAResourceVersion() throws {
        let line = """
            {"type":"BOOKMARK","object":{"kind":"Pod","apiVersion":"v1","metadata":{"resourceVersion":"4021"}}}
            """
        let bookmark = try decode(WatchEvent<BookmarkObject>.self, line).object
        XCTAssertEqual(bookmark.metadata?.resourceVersion, "4021")
    }

    func testResourceEventDecodesTheObjectAndItsResourceVersion() throws {
        let line = """
            {"type":"MODIFIED","object":{"metadata":{"name":"web","namespace":"default",\
            "uid":"abc","resourceVersion":"77"},"status":{"phase":"Running"}}}
            """
        let pod = try decode(WatchEvent<Pod>.self, line).object
        XCTAssertEqual(pod.metadata?.uid, "abc")
        XCTAssertEqual(pod.metadata?.resourceVersion, "77")
        XCTAssertEqual(pod.status?.phase, "Running")
    }

    // MARK: - Identity

    func testKeyPrefersUID() throws {
        let pod = try decode(
            Pod.self,
            """
            {"metadata":{"name":"web","namespace":"default","uid":"stable-uid"}}
            """)
        XCTAssertEqual(K8sClient.key(for: pod), "stable-uid")
    }

    /// Without a uid, two objects of the same name in different namespaces must not collide.
    func testKeyFallsBackToNamespacedNameWhenUIDIsAbsent() throws {
        let web = try decode(Pod.self, #"{"metadata":{"name":"web","namespace":"default"}}"#)
        let other = try decode(Pod.self, #"{"metadata":{"name":"web","namespace":"kube-system"}}"#)
        XCTAssertEqual(K8sClient.key(for: web), "default/web")
        XCTAssertNotEqual(K8sClient.key(for: web), K8sClient.key(for: other))
    }

    // MARK: - Ordering

    /// Snapshots come out of a dictionary, so without an explicit order the rows would
    /// reshuffle on every watch event.
    func testOrderedSortsByNamespaceThenName() throws {
        let pods = try [
            ("kube-system", "coredns"), ("default", "web"), ("default", "api"),
            ("kube-system", "metrics"),
        ].map { namespace, name in
            try decode(Pod.self, #"{"metadata":{"name":"\#(name)","namespace":"\#(namespace)"}}"#)
        }
        let keyed = Dictionary(uniqueKeysWithValues: pods.map { (K8sClient.key(for: $0), $0) })

        let ordered = K8sClient.ordered(keyed).map {
            "\($0.metadata?.namespace ?? "")/\($0.metadata?.name ?? "")"
        }
        XCTAssertEqual(
            ordered, ["default/api", "default/web", "kube-system/coredns", "kube-system/metrics"])
    }

    func testOrderedIsStableAcrossRepeatedCalls() throws {
        let pods = try (0..<20).map { index in
            try decode(
                Pod.self,
                #"{"metadata":{"name":"pod-\#(index)","namespace":"default","uid":"u\#(index)"}}"#)
        }
        let keyed = Dictionary(uniqueKeysWithValues: pods.map { (K8sClient.key(for: $0), $0) })

        let first = K8sClient.ordered(keyed).map { $0.metadata?.name }
        for _ in 0..<10 {
            XCTAssertEqual(K8sClient.ordered(keyed).map { $0.metadata?.name }, first)
        }
    }
}
