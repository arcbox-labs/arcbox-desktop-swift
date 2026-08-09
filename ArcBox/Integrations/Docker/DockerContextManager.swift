import Foundation
import OSLog

nonisolated private enum DockerContextError: LocalizedError {
    case invalidConfiguration(String)
    case dockerCLIUnavailable
    case contextCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            "~/.docker/config.json is invalid: \(detail) Repair or move the file, then try again."
        case .dockerCLIUnavailable:
            "The Docker CLI was not found. Install it in a standard location, then try again."
        case .contextCreationFailed(let detail):
            "docker context create failed: \(detail)"
        }
    }
}

/// Manages Docker CLI context switching to point at the ArcBox daemon socket.
///
/// When enabled, sets the Docker context on app startup and restores the
/// previous context on shutdown by writing to `~/.docker/config.json`.
nonisolated enum DockerContextManager {
    private static let logger = Log.context
    private static let previousContextKey = "previousDockerContext"
    @MainActor private static var operationTask: Task<Void, Error>?

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

    /// Serializes every context change in request order, including Settings and app lifecycle calls.
    @MainActor
    static func update(useArcBox: Bool) -> Task<Void, Error> {
        let previousTask = operationTask
        let task = Task {
            if let previousTask {
                _ = await previousTask.result
            }
            if useArcBox {
                try await switchToArcBox()
            } else {
                try await restorePreviousContext()
            }
        }
        operationTask = task
        return task
    }

    /// Switch the Docker CLI context to use ArcBox's socket.
    /// Saves the previous context so it can be restored later.
    private static func switchToArcBox() async throws {
        try await Task.detached {
            let config = try readConfig()
            guard let dockerPath = DockerCLIResolver.findDockerCLI() else {
                throw DockerContextError.dockerCLIUnavailable
            }

            // Keep the context from before this ArcBox session, including Docker's
            // implicit "default" context when the key is absent.
            let hadSavedContext = UserDefaults.standard.string(forKey: previousContextKey) != nil
            if !hadSavedContext {
                UserDefaults.standard.set(
                    config["currentContext"] as? String ?? "default",
                    forKey: previousContextKey
                )
            }

            do {
                try createArcBoxContext(dockerPath: dockerPath)

                var updatedConfig = config
                updatedConfig["currentContext"] = arcboxContextName
                try writeConfig(updatedConfig)
            } catch {
                if !hadSavedContext {
                    UserDefaults.standard.removeObject(forKey: previousContextKey)
                }
                throw error
            }

            logger.info("Switched Docker context to \(arcboxContextName, privacy: .public)")
        }.value
    }

    /// Restore the Docker CLI context to what it was before ArcBox started.
    /// Always restores if a previous context was saved, regardless of the current toggle state,
    /// to avoid leaving the user's Docker CLI pointing at a dead socket.
    private static func restorePreviousContext() async throws {
        try await Task.detached {
            // Always restore if we previously saved a context — even if the toggle was turned off since.
            guard let previousContext = UserDefaults.standard.string(forKey: previousContextKey) else {
                // No saved context — nothing to restore.
                return
            }
            var config = try readConfig()
            config["currentContext"] = previousContext
            try writeConfig(config)
            UserDefaults.standard.removeObject(forKey: previousContextKey)
            logger.info("Restored previous Docker context")
        }.value
    }

    /// Creates the ArcBox context in Docker's context meta store.
    private static func createArcBoxContext(dockerPath: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dockerPath)
        proc.arguments = [
            "context", "create", arcboxContextName,
            "--docker", "host=\(arcboxSocketPath)",
            "--description", "ArcBox Desktop",
        ]
        proc.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        // Exit 0 = created, non-zero with "already exists" = OK, otherwise fail
        if proc.terminationStatus == 0 { return }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = (String(data: errData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if errMsg.contains("already exists") { return }
        throw DockerContextError.contextCreationFailed(
            errMsg.isEmpty ? "exit status \(proc.terminationStatus)" : errMsg
        )
    }

    // MARK: - Config File I/O

    /// Read and parse ~/.docker/config.json.
    /// Returns an empty dictionary if the file does not exist.
    private static func readConfig() throws -> [String: Any] {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DockerContextError.invalidConfiguration(error.localizedDescription)
        }
        guard let json = object as? [String: Any] else {
            throw DockerContextError.invalidConfiguration("expected a JSON object.")
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
