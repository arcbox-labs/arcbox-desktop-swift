import ArcBoxClient
import Charts
import SwiftUI

/// The machine-wide metric bar that floats over the container table.
///
/// One glass surface holds every tile. Liquid Glass is a single functional
/// layer: a pane per tile would stack glass on glass, and the tiles are one
/// bar, not four floating controls.
struct ActivityMetricStrip: View {
    let stats: MachineResourceStats
    let cpuHistory: [ActivityViewModel.MetricPoint]
    let memoryHistory: [ActivityViewModel.MetricPoint]
    let networkHistory: [ActivityViewModel.MetricPoint]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 20)],
            alignment: .leading,
            spacing: 14
        ) {
            MetricTile(
                title: "CPU",
                value: StatsFormat.percent(stats.cpuPercent),
                caption: "\(stats.onlineCPUs) cores · load \(StatsFormat.load(stats.loadaverage1))"
            ) {
                Sparkline(points: cpuHistory, tint: MetricTint.cpu, domain: 0...100)
            }

            MetricTile(
                title: "Memory",
                value: StatsFormat.percent(stats.memoryUsedPercent),
                caption: "\(StatsFormat.bytes(stats.memoryUsedBytes)) of \(StatsFormat.bytes(stats.memoryTotalBytes))"
            ) {
                Sparkline(points: memoryHistory, tint: MetricTint.memory, domain: 0...100)
            }

            MetricTile(
                title: "Network",
                value: StatsFormat.rate(
                    stats.networkReceiveBytesPerSecond + stats.networkTransmitBytesPerSecond),
                caption:
                    "↓ \(StatsFormat.rate(stats.networkReceiveBytesPerSecond))  ↑ \(StatsFormat.rate(stats.networkTransmitBytesPerSecond))"
            ) {
                Sparkline(points: networkHistory, tint: MetricTint.network, domain: nil)
            }

            PressureTile(stats: stats)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface()
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

/// Sparkline hues. System colors, so they track the appearance and the
/// increase-contrast setting; deliberately not the accent color, which means
/// "interactive" everywhere else in the app, and deliberately three distinct
/// hues so no two trends read as the same series.
private enum MetricTint {
    static let cpu = Color.green
    static let memory = Color.blue
    static let network = Color.purple
}

// MARK: - Tile

/// Label, headline number, a figure (sparkline or gauge) and a caption, at the
/// one shape every tile in the strip shares.
private struct MetricTile<Figure: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: LocalizedStringKey
    let value: String
    let caption: String
    var valueColor: Color = AppColors.text
    @ViewBuilder var figure: Figure

    var body: some View {
        // Label and caption share one tint and separate by weight and size.
        // Reaching for `.tertiary` instead would stack a faint grey on a
        // translucent surface with content moving behind it, which is where
        // legibility goes first.
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .foregroundStyle(valueColor)
                .liveValueAnimation(value)
            figure
                .frame(height: 30)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Motion

extension View {
    /// Settles a value that the stream, not the user, changed.
    ///
    /// Critically damped, because nothing here was thrown: overshoot belongs to
    /// motion a gesture handed momentum to. Dropped outright under Reduce
    /// Motion — SwiftUI adapts its own transitions for that setting, but not
    /// animations you write.
    fileprivate func liveValueAnimation<V: Equatable>(_ value: V) -> some View {
        modifier(LiveValueAnimation(value: value))
    }
}

private struct LiveValueAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
    }
}

// MARK: - Figures

/// A filled line over the rolling history. Purely a trend cue — the tile's
/// number carries the value, so it stays out of the accessibility tree.
private struct Sparkline: View {
    let points: [ActivityViewModel.MetricPoint]
    let tint: Color
    /// Fixed y range, or `nil` to autoscale (used for byte rates).
    let domain: ClosedRange<Double>?

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Sample", point.index), y: .value("Value", point.value))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Sample", point.index), y: .value("Value", point.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let latest = points.last {
                PointMark(x: .value("Sample", latest.index), y: .value("Value", latest.value))
                    .foregroundStyle(tint)
                    .symbolSize(16)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain ?? autoDomain)
        .chartLegend(.hidden)
        .liveValueAnimation(points.last?.index)
        .accessibilityHidden(true)
    }

    /// Headroom above the observed peak so a flat-zero series still renders.
    private var autoDomain: ClosedRange<Double> {
        let peak = points.map(\.value).max() ?? 1
        return 0...max(peak * 1.2, 1)
    }
}

/// PSI memory pressure. Green under light pressure, amber past 10%, red past
/// 40% — the daemon's own thresholds.
private struct PressureTile: View {
    let stats: MachineResourceStats

    var body: some View {
        MetricTile(
            title: "Memory Pressure",
            value: stats.hasMemoryPressure ? StatsFormat.percent(stats.memoryPressurePercent) : "n/a",
            caption: stats.hasMemoryPressure ? "PSI full avg10" : "PSI unavailable (no CONFIG_PSI)",
            valueColor: tint
        ) {
            Gauge(value: level, in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.linearCapacity)
            .tint(tint)
            .opacity(stats.hasMemoryPressure ? 1 : 0.35)
            .liveValueAnimation(level)
        }
    }

    private var level: Double {
        stats.hasMemoryPressure ? min(stats.memoryPressurePercent, 100) : 0
    }

    private var tint: Color {
        guard stats.hasMemoryPressure else { return AppColors.textMuted }
        switch stats.memoryPressurePercent {
        case ..<10: return AppColors.running
        case ..<40: return AppColors.warning
        default: return AppColors.error
        }
    }
}
