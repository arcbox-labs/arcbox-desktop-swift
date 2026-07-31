import ArcBoxClient
import SwiftUI

/// Per-container resource usage.
///
/// A native `Table` so columns sort, resize and reorder the way every other Mac
/// table does, and so a row stays selected while the numbers update underneath
/// it. Sorting defaults to the busiest container first, as in Activity Monitor.
struct ActivityContainerTable: View {
    let containers: [ContainerResourceStats]

    @State private var sortOrder = [
        KeyPathComparator(\ContainerResourceStats.cpuPercent, order: .reverse)
    ]
    @State private var selection: ContainerResourceStats.ID?

    var body: some View {
        Table(containers.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Container", value: \.displayName) { container in
                Text(container.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(container.id)
            }
            .width(min: 140, ideal: 260)

            TableColumn("CPU", value: \.cpuPercent) { container in
                reading(StatsFormat.percent(container.cpuPercent))
            }
            .width(min: 56, ideal: 68)

            TableColumn("Memory", value: \.memoryCurrentBytes) { container in
                reading(memoryReading(container))
            }
            .width(min: 96, ideal: 150)

            TableColumn("Disk R/W", value: \.diskBytesPerSecond) { container in
                reading(
                    "\(StatsFormat.rate(container.diskReadBytesPerSecond)) / \(StatsFormat.rate(container.diskWriteBytesPerSecond))"
                )
            }
            .width(min: 120, ideal: 170)

            TableColumn("Net ↓/↑", value: \.networkBytesPerSecond) { container in
                reading(
                    "\(StatsFormat.rate(container.networkReceiveBytesPerSecond)) / \(StatsFormat.rate(container.networkTransmitBytesPerSecond))"
                )
            }
            .width(min: 120, ideal: 170)

            TableColumn("PIDs", value: \.pids) { container in
                reading(container.pids.formatted())
            }
            .width(min: 44, ideal: 56)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds()
    }

    /// Numbers read down the column, so they are trailing-aligned and share a
    /// digit width.
    private func reading(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func memoryReading(_ container: ContainerResourceStats) -> String {
        guard container.memoryLimitBytes > 0 else {
            return StatsFormat.bytes(container.memoryCurrentBytes)
        }
        return "\(StatsFormat.bytes(container.memoryCurrentBytes)) / \(StatsFormat.bytes(container.memoryLimitBytes))"
    }
}

extension ContainerResourceStats {
    /// Combined throughput, so the paired read/write columns can sort on the
    /// figure the column actually shows.
    var diskBytesPerSecond: Double { diskReadBytesPerSecond + diskWriteBytesPerSecond }
    var networkBytesPerSecond: Double { networkReceiveBytesPerSecond + networkTransmitBytesPerSecond }
}
