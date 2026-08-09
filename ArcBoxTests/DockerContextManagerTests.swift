import Foundation
import XCTest

@testable import ArcBox

final class DockerContextManagerTests: XCTestCase {
    func testSelectsPreviousExternalContextAfterArcBoxBecomesCurrent() throws {
        let data = Data(
            """
            {"Current":true,"DockerEndpoint":"unix:///Users/test/.arcbox/run/docker.sock","Name":"arcbox"}
            {"Current":false,"DockerEndpoint":"unix:///var/run/docker.sock","Name":"default"}
            {"Current":false,"DockerEndpoint":"unix:///Users/test/.orbstack/run/docker.sock","Name":"orbstack"}
            """.utf8
        )

        let source = try DockerContextManager.selectMigrationSource(
            from: try DockerContextManager.decodeDockerContexts(data),
            previousContext: "orbstack",
            homeDirectory: "/Users/test",
            socketExists: { $0 == "/Users/test/.orbstack/run/docker.sock" }
        )

        XCTAssertEqual(
            source,
            DockerMigrationSource(
                kind: .orbStack,
                contextName: "orbstack",
                socketPath: "/Users/test/.orbstack/run/docker.sock"
            )
        )
    }

    func testRejectsMalformedContextOutput() {
        XCTAssertThrowsError(
            try DockerContextManager.decodeDockerContexts(
                Data("{not-json}\n".utf8)
            )
        )
    }

    func testIgnoresDefaultRemoteAndStaleContexts() {
        let contexts = [
            DockerContextDescription(
                current: true,
                dockerEndpoint: "unix:///var/run/docker.sock",
                name: "default"
            ),
            DockerContextDescription(
                current: false,
                dockerEndpoint: "ssh://docker.example.com",
                name: "remote"
            ),
            DockerContextDescription(
                current: false,
                dockerEndpoint: "unix:///Users/test/.docker/run/docker.sock",
                name: "desktop-linux"
            ),
        ]

        XCTAssertNil(
            try DockerContextManager.selectMigrationSource(
                from: contexts,
                previousContext: nil,
                homeDirectory: "/Users/test",
                socketExists: { _ in false }
            )
        )
    }

    func testRejectsAmbiguousExternalContexts() {
        let contexts = [
            DockerContextDescription(
                current: false,
                dockerEndpoint: "unix:///Users/test/.docker/run/docker.sock",
                name: "desktop-linux"
            ),
            DockerContextDescription(
                current: false,
                dockerEndpoint: "unix:///Users/test/.orbstack/run/docker.sock",
                name: "orbstack"
            ),
        ]

        XCTAssertThrowsError(
            try DockerContextManager.selectMigrationSource(
                from: contexts,
                previousContext: nil,
                homeDirectory: "/Users/test",
                socketExists: { _ in true }
            )
        )
    }
}
