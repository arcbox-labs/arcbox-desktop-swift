import Foundation

/// Pod phase states
enum PodPhase: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case running = "Running"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case unknown = "Unknown"

    var id: String { rawValue }

    var isRunning: Bool { self == .running }

}

/// Pod view model for UI display
struct PodViewModel: Identifiable, Hashable {
    let id: String
    let name: String
    let namespace: String
    let phase: PodPhase
    let containerCount: Int
    let readyCount: Int
    let restartCount: Int
    let createdAt: Date

    var isRunning: Bool { phase.isRunning }

    var readyDisplay: String {
        "\(readyCount)/\(containerCount)"
    }

    var createdAgo: String {
        relativeTime(from: createdAt)
    }
}
