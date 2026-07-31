import Foundation

/// Formatting for resource values.
///
/// Byte sizes use the memory count style so they match Finder and Activity
/// Monitor; everything goes through `FormatStyle` so digits, separators and
/// percent signs follow the user's locale.
enum StatsFormat {
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    static func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let clamped = Int64(max(0, bytesPerSecond).rounded())
        return clamped.formatted(.byteCount(style: .memory)) + "/s"
    }

    /// Load average, at the two decimals `uptime` reports.
    static func load(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// Uptime at the two coarsest units that apply — "5d 3h", "3h 12m", "8m".
    ///
    /// Deliberately no seconds: this sits in the window subtitle, and a figure
    /// that rewrites itself every second is chrome that never stops moving.
    static func uptime(_ duration: Duration) -> String {
        duration.formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }
}
