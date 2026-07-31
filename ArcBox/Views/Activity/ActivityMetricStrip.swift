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
            SparklineTile(
                title: "CPU",
                points: cpuHistory,
                tint: MetricTint.cpu,
                domain: 0...100,
                liveValue: StatsFormat.percent(stats.cpuPercent),
                liveCaption: "\(stats.onlineCPUs) cores · load \(StatsFormat.load(stats.loadaverage1))",
                format: StatsFormat.percent
            )

            SparklineTile(
                title: "Memory",
                points: memoryHistory,
                tint: MetricTint.memory,
                domain: 0...100,
                liveValue: StatsFormat.percent(stats.memoryUsedPercent),
                liveCaption:
                    "\(StatsFormat.bytes(stats.memoryUsedBytes)) of \(StatsFormat.bytes(stats.memoryTotalBytes))",
                format: StatsFormat.percent
            )

            SparklineTile(
                title: "Network",
                points: networkHistory,
                tint: MetricTint.network,
                domain: nil,
                liveValue: StatsFormat.rate(
                    stats.networkReceiveBytesPerSecond + stats.networkTransmitBytesPerSecond),
                liveCaption:
                    "↓ \(StatsFormat.rate(stats.networkReceiveBytesPerSecond))  ↑ \(StatsFormat.rate(stats.networkTransmitBytesPerSecond))",
                format: StatsFormat.rate
            )

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

// MARK: - Tiles

/// A metric with history. Selecting a point on the sparkline rewinds the
/// headline to that sample and says how long ago it was, which is the whole
/// reason to keep a minute of history on screen rather than just the latest
/// number. `chartXSelection` decides what counts as selecting — the platform's
/// convention, not ours.
private struct SparklineTile: View {
    let title: LocalizedStringKey
    let points: [ActivityViewModel.MetricPoint]
    let tint: Color
    /// Fixed y range, or `nil` to autoscale (used for byte rates).
    let domain: ClosedRange<Double>?
    let liveValue: String
    let liveCaption: String
    let format: (Double) -> String

    @State private var scrubbedIndex: Int?

    var body: some View {
        MetricTile(
            title: title,
            value: scrubbed.map { format($0.value) } ?? liveValue,
            caption: scrubbed.map(elapsedCaption) ?? liveCaption,
            // Tinting only while scrubbing marks the headline as a reading from
            // the past rather than the live value.
            valueColor: scrubbed == nil ? AppColors.text : tint
        ) {
            Sparkline(points: points, tint: tint, domain: domain, scrubbedIndex: $scrubbedIndex)
        }
    }

    private var scrubbed: ActivityViewModel.MetricPoint? {
        scrubbedIndex.flatMap { index in points.first { $0.index == index } }
    }

    /// Guest-clock distance from the newest sample. Reported from the timestamps
    /// rather than the sample count, so a stalled or throttled stream doesn't
    /// quietly misreport the age.
    private func elapsedCaption(_ point: ActivityViewModel.MetricPoint) -> String {
        guard let latest = points.last, latest.monotonicMs > point.monotonicMs else {
            return "latest sample"
        }
        let seconds = Int((latest.monotonicMs - point.monotonicMs) / 1000)
        return seconds < 1 ? "latest sample" : "\(seconds)s ago"
    }
}

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

/// A filled line over the rolling history, scrubbable with the pointer. The
/// tile's headline carries the value in text, so the chart itself stays out of
/// the accessibility tree rather than announcing sixty unlabelled samples.
private struct Sparkline: View {
    let points: [ActivityViewModel.MetricPoint]
    let tint: Color
    /// Fixed y range, or `nil` to autoscale (used for byte rates).
    let domain: ClosedRange<Double>?
    @Binding var scrubbedIndex: Int?

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
            // The marker follows the pointer while scrubbing and returns to the
            // newest sample when it leaves, so there is always exactly one.
            if let marked = marked {
                RuleMark(x: .value("Sample", marked.index))
                    .foregroundStyle(tint.opacity(scrubbedIndex == nil ? 0 : 0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Sample", marked.index), y: .value("Value", marked.value))
                    .foregroundStyle(tint)
                    .symbolSize(scrubbedIndex == nil ? 16 : 40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain ?? autoDomain)
        .chartLegend(.hidden)
        .chartXSelection(value: $scrubbedIndex)
        .liveValueAnimation(points.last?.index)
        .accessibilityHidden(true)
    }

    private var marked: ActivityViewModel.MetricPoint? {
        guard let scrubbedIndex else { return points.last }
        return points.first { $0.index == scrubbedIndex } ?? points.last
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
