/// Lifecycle of an asynchronously loaded list.
enum LoadPhase: Equatable {
    case waiting
    case loading
    case loaded
    case failed(String)

    /// Starts a load and returns whether existing results should remain visible.
    mutating func beginLoading() -> Bool {
        let isRefresh = self == .loaded
        if !isRefresh {
            self = .loading
        }
        return isRefresh
    }

    /// Records a failure, returning a non-blocking refresh error when cached results exist.
    mutating func fail(_ message: String, retainingLoadedContent: Bool) -> String? {
        if retainingLoadedContent {
            self = .loaded
            return message
        }
        self = .failed(message)
        return nil
    }

    mutating func cancelLoading(
        for error: Error,
        retainingLoadedContent: Bool
    ) -> Bool {
        guard Task.isCancelled || error is CancellationError else { return false }
        self = retainingLoadedContent ? .loaded : .waiting
        return true
    }
}

/// Serializes list loads while retaining only the latest pending request.
@MainActor
final class SingleFlightLoadGate {
    typealias Operation = @MainActor () async -> Void

    private var isRunning = false
    private var pending: Operation?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(_ operation: @escaping Operation) async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            if isRunning {
                pending = operation
            } else {
                isRunning = true
                Task {
                    await self.drain(startingWith: operation)
                }
            }
        }
    }

    private func drain(startingWith first: @escaping Operation) async {
        var next: Operation? = first
        while let operation = next {
            await operation()
            next = pending
            pending = nil
        }
        isRunning = false

        let completedWaiters = waiters
        waiters.removeAll()
        for continuation in completedWaiters {
            continuation.resume()
        }
    }
}
