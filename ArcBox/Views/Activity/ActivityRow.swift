import ArcBoxClient
import Foundation

/// One line in the activity table: a container, or a Compose project's total.
///
/// The join happens here rather than in the daemon. The stats stream carries
/// cgroup counters keyed by container ID — all the guest can measure — while
/// the project a container belongs to is a Docker label the app already holds
/// from the Engine API. Combining them client-side keeps the daemon's stats
/// path to what it can actually observe.
nonisolated struct ActivityRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A single container, carrying its full ID for actions and joins.
        case container(id: String)
        /// A Compose project's total.
        case project
    }

    let id: String
    let title: String
    let kind: Kind
    let cpuPercent: Double
    let memoryCurrentBytes: UInt64
    /// 0 means unlimited. A project reports 0 unless every member is limited —
    /// summing around an unlimited member would invent a ceiling.
    let memoryLimitBytes: UInt64
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    let networkReceiveBytesPerSecond: Double
    let networkTransmitBytesPerSecond: Double
    let pids: UInt32

    /// Combined throughput, so the paired read/write columns sort on the figure
    /// the column actually shows.
    var diskBytesPerSecond: Double { diskReadBytesPerSecond + diskWriteBytesPerSecond }
    var networkBytesPerSecond: Double {
        networkReceiveBytesPerSecond + networkTransmitBytesPerSecond
    }

    var containerID: String? {
        guard case .container(let id) = kind else { return nil }
        return id
    }

    var isProject: Bool { kind == .project }
}

nonisolated extension ActivityRow {
    init(_ container: ContainerResourceStats) {
        self.init(
            id: container.id,
            title: container.displayName,
            kind: .container(id: container.id),
            cpuPercent: container.cpuPercent,
            memoryCurrentBytes: container.memoryCurrentBytes,
            memoryLimitBytes: container.memoryLimitBytes,
            diskReadBytesPerSecond: container.diskReadBytesPerSecond,
            diskWriteBytesPerSecond: container.diskWriteBytesPerSecond,
            networkReceiveBytesPerSecond: container.networkReceiveBytesPerSecond,
            networkTransmitBytesPerSecond: container.networkTransmitBytesPerSecond,
            pids: container.pids
        )
    }

    /// A project's total.
    ///
    /// The ID is namespaced with a character a container ID cannot contain —
    /// those are hex — so a project and a container can never collide in the
    /// table's selection or in its saved disclosure state.
    static func project(named project: String, totalling members: [ActivityRow]) -> ActivityRow {
        let limits = members.map(\.memoryLimitBytes)
        return ActivityRow(
            id: "project:\(project)",
            title: project,
            kind: .project,
            cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
            memoryCurrentBytes: members.reduce(0) { $0 + $1.memoryCurrentBytes },
            memoryLimitBytes: limits.contains(0) ? 0 : limits.reduce(0, +),
            diskReadBytesPerSecond: members.reduce(0) { $0 + $1.diskReadBytesPerSecond },
            diskWriteBytesPerSecond: members.reduce(0) { $0 + $1.diskWriteBytesPerSecond },
            networkReceiveBytesPerSecond: members.reduce(0) { $0 + $1.networkReceiveBytesPerSecond },
            networkTransmitBytesPerSecond: members.reduce(0) {
                $0 + $1.networkTransmitBytesPerSecond
            },
            pids: members.reduce(0) { $0 + $1.pids }
        )
    }
}

/// What Docker contributes to a stats row that the guest's cgroup counters
/// cannot: the project it groups under, and the image the search field matches.
///
/// Narrower than the container view model it comes from, so the table depends
/// on the two facts it uses rather than on the Containers feature.
nonisolated struct ActivityContainerFacts: Equatable, Sendable {
    let project: String?
    let image: String
}

/// A top-level row and, when it totals a project, the containers beneath it.
nonisolated struct ActivityRowGroup: Identifiable, Equatable, Sendable {
    let summary: ActivityRow
    /// Empty for a standalone container, which renders as a plain row.
    let children: [ActivityRow]

    var id: String { summary.id }
}

nonisolated enum ActivityRowGrouping {
    /// Groups rows by Compose project, matching what the Containers list does:
    /// a project for every container that declares one, standalone rows for the
    /// rest.
    ///
    /// A container absent from `projects` — started with a plain `docker run`,
    /// or not yet reported by the Engine — stays at the top level rather than
    /// landing in a catch-all bucket that would imply a relationship it has no
    /// evidence for.
    static func groups(
        for rows: [ActivityRow],
        projects: [String: String],
        sortedBy comparators: [KeyPathComparator<ActivityRow>]
    ) -> [ActivityRowGroup] {
        var members: [String: [ActivityRow]] = [:]
        var standalone: [ActivityRow] = []
        for row in rows {
            guard let id = row.containerID, let project = projects[id] else {
                standalone.append(row)
                continue
            }
            members[project, default: []].append(row)
        }

        let projects = members.map { project, members in
            ActivityRowGroup(
                summary: .project(named: project, totalling: members),
                children: members.sorted(using: comparators)
            )
        }
        let loose = standalone.map { ActivityRowGroup(summary: $0, children: []) }
        return (projects + loose).sorted {
            precedes($0.summary, $1.summary, using: comparators)
        }
    }

    /// Applies a table's comparators in order, as `sorted(using:)` would to the
    /// rows themselves — the summaries are what order the groups, and they are
    /// not a flat array the table can sort on its own.
    private static func precedes(
        _ lhs: ActivityRow,
        _ rhs: ActivityRow,
        using comparators: [KeyPathComparator<ActivityRow>]
    ) -> Bool {
        for comparator in comparators {
            switch comparator.compare(lhs, rhs) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: continue
            }
        }
        return false
    }
}
