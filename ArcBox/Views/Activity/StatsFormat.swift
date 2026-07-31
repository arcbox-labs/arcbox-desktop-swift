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
}
