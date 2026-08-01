import Foundation

// MARK: - Watch events

public enum WatchEventType: String, Codable, Sendable {
    case added = "ADDED"
    case modified = "MODIFIED"
    case deleted = "DELETED"
    /// Progress marker carrying only a `resourceVersion`; requested via `allowWatchBookmarks`.
    case bookmark = "BOOKMARK"
    case error = "ERROR"
}

/// One line of a watch stream. Decoded in two passes because `object` is a `Status` rather than
/// the watched resource on `ERROR` events.
struct WatchEventEnvelope: Decodable {
    let type: WatchEventType
}

struct WatchEvent<Object: Decodable>: Decodable {
    let type: WatchEventType
    let object: Object
}

/// A bookmark's object carries nothing but its resourceVersion.
struct BookmarkObject: Decodable {
    let metadata: ListMeta?
}

// MARK: - Resource streams

@available(macOS 15.0, *)
extension K8sClient {
    /// The live set of pods: an initial LIST, then WATCH deltas applied to it.
    ///
    /// Emits the full set on every change, so consumers stay a plain array. Re-lists
    /// transparently when the server expires the `resourceVersion`, and re-establishes the
    /// watch when the server closes it — both are routine and neither surfaces as an error.
    /// Transport failures terminate the stream; reconnection policy is the caller's.
    public func podStream() -> AsyncThrowingStream<[Pod], any Error> {
        resourceStream(path: "/api/v1/pods", of: PodList.self)
    }

    /// The live set of services. See ``podStream()``.
    public func serviceStream() -> AsyncThrowingStream<[K8sService], any Error> {
        resourceStream(path: "/api/v1/services", of: ServiceList.self)
    }

    private func resourceStream<List: K8sResourceList>(
        path: String,
        of listType: List.Type
    ) -> AsyncThrowingStream<[List.Item], any Error> {
        // Every element is a complete snapshot, so only the newest one is worth keeping. The
        // default unbounded buffer would grow with burst size × list size during a rollout and
        // march the UI through intermediate states it can no longer act on.
        AsyncThrowingStream<[List.Item], any Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        // (Re-)seed from a LIST, which also yields the resourceVersion to
                        // resume from. Reached again only when the server expires it.
                        let list: List = try await self.get(path)
                        var items = Dictionary(
                            list.items.map { (Self.key(for: $0), $0) },
                            uniquingKeysWith: { _, newer in newer })
                        continuation.yield(Self.ordered(items))

                        guard var resourceVersion = list.metadata?.resourceVersion else {
                            throw K8sError.invalidResponse
                        }

                        do {
                            while !Task.isCancelled {
                                (items, resourceVersion) = try await self.consumeWatch(
                                    path: path,
                                    resourceVersion: resourceVersion,
                                    items: items,
                                    yield: { continuation.yield($0) }
                                )
                                // The server closes idle watches; pause briefly so a server
                                // that closes immediately cannot spin this loop.
                                try await Task.sleep(for: .seconds(1))
                            }
                        } catch K8sError.watchExpired {
                            continue  // History is gone — fall back to a fresh LIST.
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stream one watch connection, returning the updated set and the resourceVersion to
    /// resume from once the server closes it.
    private func consumeWatch<Item: K8sResource>(
        path: String,
        resourceVersion: String,
        items: [String: Item],
        yield: ([Item]) -> Void
    ) async throws -> (items: [String: Item], resourceVersion: String) {
        let request = try makeRequest(
            path: path,
            query: [
                URLQueryItem(name: "watch", value: "1"),
                URLQueryItem(name: "resourceVersion", value: resourceVersion),
                URLQueryItem(name: "allowWatchBookmarks", value: "true"),
            ])

        let (bytes, response) = try await streamingSession.bytes(for: request)
        do {
            try validateResponse(response)
        } catch K8sError.httpError(410) {
            throw K8sError.watchExpired
        }

        var current = items
        var latest = resourceVersion

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
            let type = try JSONDecoder.kubernetes.decode(WatchEventEnvelope.self, from: data).type

            switch type {
            case .error:
                let status = try JSONDecoder.kubernetes
                    .decode(WatchEvent<K8sStatus>.self, from: data).object
                if status.code == 410 { throw K8sError.watchExpired }
                throw K8sError.watchFailed(reason: status.message ?? status.reason ?? "unknown")

            case .bookmark:
                let bookmark = try JSONDecoder.kubernetes
                    .decode(WatchEvent<BookmarkObject>.self, from: data).object
                if let version = bookmark.metadata?.resourceVersion { latest = version }

            case .added, .modified, .deleted:
                let object = try JSONDecoder.kubernetes
                    .decode(WatchEvent<Item>.self, from: data).object
                if let version = object.metadata?.resourceVersion { latest = version }
                if type == .deleted {
                    current.removeValue(forKey: Self.key(for: object))
                } else {
                    current[Self.key(for: object)] = object
                }
                yield(Self.ordered(current))
            }
        }

        return (current, latest)
    }

    /// `uid` is the stable identity; fall back to namespace/name for objects without one.
    static func key(for resource: some K8sResource) -> String {
        if let uid = resource.metadata?.uid { return uid }
        let namespace = resource.metadata?.namespace ?? "default"
        return "\(namespace)/\(resource.metadata?.name ?? "")"
    }

    /// Dictionary order is arbitrary and would reshuffle rows on every event. Sort by
    /// namespace then name, which is the order a LIST already comes back in.
    static func ordered<Item: K8sResource>(_ items: [String: Item]) -> [Item] {
        items.values.sorted {
            (($0.metadata?.namespace ?? ""), ($0.metadata?.name ?? ""))
                < (($1.metadata?.namespace ?? ""), ($1.metadata?.name ?? ""))
        }
    }
}
