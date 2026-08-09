import Foundation
import OSLog

nonisolated struct DockerMigrationSource: Equatable, Sendable {
    enum Kind: String, Sendable {
        case dockerDesktop = "docker-desktop"
        case orbStack = "orbstack"

        var displayName: String {
            switch self {
            case .dockerDesktop: "Docker Desktop"
            case .orbStack: "OrbStack"
            }
        }
    }

    let kind: Kind
    let contextName: String
    let socketPath: String
}

nonisolated struct DockerContextDescription: Decodable, Equatable, Sendable {
    let current: Bool
    let dockerEndpoint: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case current = "Current"
        case dockerEndpoint = "DockerEndpoint"
        case name = "Name"
    }
}

nonisolated private struct DockerContextInspectionError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

/// Manages Docker CLI context switching to point at the ArcBox daemon socket.
///
/// When enabled, sets the Docker context on app startup and restores the
/// previous context on shutdown by writing to `~/.docker/config.json`.
nonisolated enum DockerContextManager {
    private static let logger = Log.context
    private static let previousContextKey = "previousDockerContext"

    private static var configPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.docker/config.json"
    }

    private static var arcboxSocketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDir = profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        return "unix://\(home)/\(dataDir)/run/docker.sock"
    }

    private static var arcboxContextName: String {
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        return profile?.caseInsensitiveCompare("development") == .orderedSame ? "arcbox-dev" : "arcbox"
    }

    /// Finds a Docker Desktop or OrbStack candidate without relying on the
    /// current context, which ArcBox may already have switched to itself.
    static func detectMigrationSource() async throws -> DockerMigrationSource? {
        let task = Task.detached(priority: .utility) { () throws -> DockerMigrationSource? in
            let contexts = try readDockerContexts()
            let previousContext = UserDefaults.standard.string(forKey: previousContextKey)
            return try selectMigrationSource(
                from: contexts,
                previousContext: previousContext,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
                socketExists: FileManager.default.fileExists(atPath:)
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func decodeDockerContexts(_ data: Data) throws -> [DockerContextDescription] {
        try data.split(separator: UInt8(ascii: "\n")).map { line in
            try JSONDecoder().decode(DockerContextDescription.self, from: Data(line))
        }
    }

    static func selectMigrationSource(
        from contexts: [DockerContextDescription],
        previousContext: String?,
        homeDirectory: String,
        socketExists: (String) -> Bool
    ) throws -> DockerMigrationSource? {
        let candidates = contexts.compactMap { context -> DockerMigrationSource? in
            guard
                let source = migrationSource(from: context, homeDirectory: homeDirectory),
                socketExists(source.socketPath)
            else {
                return nil
            }
            return source
        }

        if let current = contexts.first(where: \.current),
            let source = candidates.first(where: { $0.contextName == current.name })
        {
            return source
        }
        if let previousContext,
            let source = candidates.first(where: { $0.contextName == previousContext })
        {
            return source
        }

        let unique = Dictionary(
            candidates.map { ("\($0.kind.rawValue):\($0.socketPath)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard unique.count <= 1 else {
            throw DockerContextInspectionError(
                "Both Docker Desktop and OrbStack are available. "
                    + "Make the environment you want to migrate the current Docker context."
            )
        }
        return unique.values.first
    }

    private static func migrationSource(
        from context: DockerContextDescription,
        homeDirectory: String
    ) -> DockerMigrationSource? {
        guard context.dockerEndpoint.hasPrefix("unix://") else { return nil }

        var socketPath = String(context.dockerEndpoint.dropFirst("unix://".count))
        if socketPath.hasPrefix("~/") {
            socketPath = "\(homeDirectory)/\(socketPath.dropFirst(2))"
        }
        socketPath = URL(fileURLWithPath: socketPath).standardizedFileURL.path

        let knownPaths = migrationSocketPaths(homeDirectory: homeDirectory)

        let kind: DockerMigrationSource.Kind
        switch socketPath {
        case knownPaths.dockerDesktop:
            kind = .dockerDesktop
        case knownPaths.orbStack:
            kind = .orbStack
        default:
            return nil
        }

        return DockerMigrationSource(
            kind: kind,
            contextName: context.name,
            socketPath: socketPath
        )
    }

    private static func readDockerContexts() throws -> [DockerContextDescription] {
        guard let dockerCLI = DockerCLIResolver.findDockerCLI() else {
            let paths = migrationSocketPaths(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            )
            if [paths.dockerDesktop, paths.orbStack].contains(
                where: FileManager.default.fileExists(atPath:)
            ) {
                throw DockerContextInspectionError(
                    "A supported Docker environment is running, but the Docker CLI was not found."
                )
            }
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dockerCLI)
        process.arguments = ["context", "ls", "--format", "{{json .}}"]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            logger.warning(
                "Unable to inspect Docker contexts: \(error.localizedDescription, privacy: .private)"
            )
            throw error
        }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, !Task.isCancelled, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let timedOut = process.isRunning && !Task.isCancelled
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try Task.checkCancellation()
        if timedOut {
            throw DockerContextInspectionError("Docker context inspection timed out.")
        }
        guard process.terminationStatus == 0 else {
            let message =
                String(
                    data: error.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
            logger.warning("Docker context inspection failed: \(message, privacy: .private)")
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DockerContextInspectionError(
                detail.isEmpty ? "Docker context inspection failed." : detail
            )
        }

        return try decodeDockerContexts(output.fileHandleForReading.readDataToEndOfFile())
    }

    private static func migrationSocketPaths(
        homeDirectory: String
    ) -> (
        dockerDesktop: String, orbStack: String
    ) {
        let home = URL(fileURLWithPath: homeDirectory)
        return (
            home.appendingPathComponent(".docker/run/docker.sock").standardizedFileURL.path,
            home.appendingPathComponent(".orbstack/run/docker.sock").standardizedFileURL.path
        )
    }

    /// Switch the Docker CLI context to use ArcBox's socket.
    /// Saves the previous context so it can be restored later.
    static func switchToArcBox() {
        guard UserDefaults.standard.bool(forKey: "switchDockerContextAutomatically") else { return }

        Task.detached {
            do {
                guard let config = try readConfig() else {
                    logger.error("Failed to parse ~/.docker/config.json, skipping context switch to avoid data loss")
                    return
                }

                // Always save the current context so we can restore it on quit,
                // even if it's already ArcBox's context (user may have set it intentionally).
                if let previousContext = config["currentContext"] as? String {
                    UserDefaults.standard.set(previousContext, forKey: previousContextKey)
                }

                // Ensure the ArcBox context exists in Docker's context store.
                guard createArcBoxContext() else {
                    logger.error("Skipping context switch — failed to create ArcBox context")
                    return
                }

                // Set the current context
                var updatedConfig = config
                updatedConfig["currentContext"] = arcboxContextName
                try writeConfig(updatedConfig)

                logger.info("Switched Docker context to \(arcboxContextName, privacy: .public)")
            } catch {
                logger.error("Failed to switch Docker context: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Restore the Docker CLI context to what it was before ArcBox started.
    /// Always restores if a previous context was saved, regardless of the current toggle state,
    /// to avoid leaving the user's Docker CLI pointing at a dead socket.
    static func restorePreviousContext() {
        do {
            guard var config = try readConfig() else {
                logger.error("Failed to parse ~/.docker/config.json, skipping context restore to avoid data loss")
                return
            }

            // Always restore if we previously saved a context — even if the toggle was turned off since.
            guard let previousContext = UserDefaults.standard.string(forKey: previousContextKey) else {
                // No saved context — nothing to restore.
                return
            }
            config["currentContext"] = previousContext
            try writeConfig(config)
            UserDefaults.standard.removeObject(forKey: previousContextKey)
            logger.info("Restored previous Docker context")
        } catch {
            logger.error("Failed to restore Docker context: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates the ArcBox context in Docker's context meta store.
    /// Returns true if the context exists (created or already present), false on failure.
    @discardableResult
    private static func createArcBoxContext() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "docker", "context", "create", arcboxContextName,
            "--docker", "host=\(arcboxSocketPath)",
            "--description", "ArcBox Desktop",
        ]
        proc.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            logger.error("Failed to launch docker context create: \(error.localizedDescription, privacy: .public)")
            return false
        }
        // Exit 0 = created, non-zero with "already exists" = OK, otherwise fail
        if proc.terminationStatus == 0 { return true }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8) ?? ""
        if errMsg.contains("already exists") { return true }
        logger.error("docker context create failed (status \(proc.terminationStatus)): \(errMsg, privacy: .public)")
        return false
    }

    // MARK: - Config File I/O

    /// Read and parse ~/.docker/config.json.
    /// Returns nil if the file exists but cannot be parsed as a JSON object (to prevent clobbering).
    /// Returns an empty dictionary if the file does not exist.
    private static func readConfig() throws -> [String: Any]? {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func writeConfig(_ config: [String: Any]) throws {
        let url = URL(fileURLWithPath: configPath)
        // Ensure ~/.docker directory exists
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
