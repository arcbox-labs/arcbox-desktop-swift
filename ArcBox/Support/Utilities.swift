import Foundation

/// Parse an ISO 8601 date string with automatic fallback from fractional seconds
/// to plain `.withInternetDateTime`. Returns `.distantPast` when the input is nil
/// or unparseable.
func parseISO8601Date(_ string: String?) -> Date {
    guard let string else { return .distantPast }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = formatter.date(from: string) {
        return parsed
    }
    // Retry without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string) ?? .distantPast
}

/// Formats a byte count, always as a numeral.
///
/// `ByteCountFormatStyle` — and `ByteCountFormatter` before it — spell zero out
/// by default: "Zero kB". That reads as a word dropped into a column of
/// numbers, breaks the digit alignment those columns depend on, and is the one
/// value a live counter sits at most of the time. Every byte figure in the app
/// goes through here so the default cannot creep back in one call site at a
/// time.
/// `nonisolated` because this is pure formatting and its callers are not all on
/// the main actor — file-size columns resolve off it.
nonisolated func formattedBytes(_ count: Int64, style: ByteCountFormatStyle.Style = .file) -> String {
    count.formatted(.byteCount(style: style, spellsOutZero: false))
}

/// Shared utility for relative time display
func relativeTime(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    let days = Int(interval / 86400)
    let hours = Int(interval / 3600)
    let minutes = Int(interval / 60)

    if days >= 30 {
        let months = days / 30
        return "\(months) month\(months > 1 ? "s" : "") ago"
    } else if days >= 7 {
        let weeks = days / 7
        return "\(weeks) week\(weeks > 1 ? "s" : "") ago"
    } else if days > 0 {
        return "\(days) day\(days > 1 ? "s" : "") ago"
    } else if hours > 0 {
        return "\(hours) hour\(hours > 1 ? "s" : "") ago"
    } else if minutes > 0 {
        return "\(minutes) minute\(minutes > 1 ? "s" : "") ago"
    }
    return "just now"
}
