import XCTest

@testable import ArcBox

/// Guards the one thing `formattedBytes` exists to override.
///
/// `ByteCountFormatStyle` spells zero out as "Zero kB" unless told not to, and
/// zero is where an idle container's counters sit — so the default turns most
/// of a live table into words. These pin the override; the non-zero cases are
/// here to show it changes nothing else.
final class ByteFormattingTests: XCTestCase {

    func testZeroFormatsAsANumeralNotAWord() {
        XCTAssertFalse(
            formattedBytes(0).lowercased().contains("zero"),
            "Foundation spells zero out by default; formattedBytes has to suppress that")
        XCTAssertTrue(formattedBytes(0).contains("0"))
    }

    func testZeroIsANumeralInEveryCountStyle() {
        for style in [ByteCountFormatStyle.Style.file, .memory, .binary, .decimal] {
            XCTAssertFalse(
                formattedBytes(0, style: style).lowercased().contains("zero"),
                "style \(style) still spells zero out")
        }
    }

    /// The stats table's zero cells: an idle container reports no disk and no
    /// network traffic, and both render through the rate formatter.
    func testIdleRatesReadAsZero() {
        XCTAssertFalse(StatsFormat.rate(0).lowercased().contains("zero"))
        XCTAssertFalse(StatsFormat.bytes(0).lowercased().contains("zero"))
        XCTAssertTrue(StatsFormat.rate(0).hasSuffix("/s"))
    }

    func testNonZeroCountsAreUnaffectedBySuppressingTheWord() {
        XCTAssertEqual(formattedBytes(1, style: .memory), Int64(1).formatted(.byteCount(style: .memory)))
        XCTAssertEqual(
            formattedBytes(1_048_576, style: .memory),
            Int64(1_048_576).formatted(.byteCount(style: .memory)))
    }
}
