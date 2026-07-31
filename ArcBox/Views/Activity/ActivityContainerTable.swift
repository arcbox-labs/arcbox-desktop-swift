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
    @State private var columnLayout = TableColumnCustomization<ContainerResourceStats>()
    /// `TableColumnCustomization` is `Codable` but not `RawRepresentable`, so it
    /// rides in `AppStorage` as its own encoding rather than through a
    /// retroactive conformance on a type we do not own.
    @AppStorage("activity.containerColumns") private var storedColumnLayout = Data()

    var body: some View {
        Table(
            containers.sorted(using: sortOrder),
            selection: $selection,
            sortOrder: $sortOrder,
            columnCustomization: $columnLayout
        ) {
            TableColumn("Container", value: \.displayName) { container in
                Text(container.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(container.id)
            }
            .width(min: 140, ideal: 260)
            .customizationID("container")
            // Hiding the column that says which row is which leaves a table of
            // anonymous numbers.
            .disabledCustomizationBehavior(.visibility)

            TableColumn("CPU", value: \.cpuPercent) { container in
                reading(StatsFormat.percent(container.cpuPercent))
            }
            .width(min: 56, ideal: 68)
            .customizationID("cpu")

            TableColumn("Memory", value: \.memoryCurrentBytes) { container in
                reading(memoryReading(container))
            }
            .width(min: 96, ideal: 150)
            .customizationID("memory")

            TableColumn("Disk R/W", value: \.diskBytesPerSecond) { container in
                reading(
                    "\(StatsFormat.rate(container.diskReadBytesPerSecond)) / \(StatsFormat.rate(container.diskWriteBytesPerSecond))"
                )
            }
            .width(min: 120, ideal: 170)
            .customizationID("disk")

            TableColumn("Net ↓/↑", value: \.networkBytesPerSecond) { container in
                reading(
                    "\(StatsFormat.rate(container.networkReceiveBytesPerSecond)) / \(StatsFormat.rate(container.networkTransmitBytesPerSecond))"
                )
            }
            .width(min: 120, ideal: 170)
            .customizationID("network")

            TableColumn("PIDs", value: \.pids) { container in
                reading(container.pids.formatted())
            }
            .width(min: 44, ideal: 56)
            .customizationID("pids")
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds()
        .task { restoreColumnLayout() }
        .onChange(of: columnLayout) { _, layout in
            storedColumnLayout = (try? JSONEncoder().encode(layout)) ?? Data()
        }
    }

    /// A layout saved by a build with different columns decodes into something
    /// that no longer matches them; dropping it loses a preference, which beats
    /// restoring a table missing half its columns.
    private func restoreColumnLayout() {
        guard !storedColumnLayout.isEmpty,
            let restored = try? JSONDecoder().decode(
                TableColumnCustomization<ContainerResourceStats>.self, from: storedColumnLayout)
        else { return }
        columnLayout = restored
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
