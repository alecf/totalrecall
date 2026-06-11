import Testing
@testable import TotalRecallCore

@Suite("Memory Formatter")
struct FormattingTests {
    private let kb: UInt64 = 1024
    private let mb: UInt64 = 1024 * 1024
    private let gb: UInt64 = 1024 * 1024 * 1024

    // MARK: - format(bytes:)

    @Test("Formats bytes below 1 MB as KB")
    func formatsKB() {
        #expect(MemoryFormatter.format(bytes: 512 * kb) == "512 KB")
    }

    @Test("Formats zero bytes as 0 KB")
    func formatsZero() {
        #expect(MemoryFormatter.format(bytes: 0) == "0 KB")
    }

    @Test("Formats bytes below 1 GB as MB")
    func formatsMB() {
        #expect(MemoryFormatter.format(bytes: 512 * mb) == "512 MB")
    }

    @Test("Formats exactly 1 MB as MB, not 1024 KB")
    func formatsExactlyOneMB() {
        #expect(MemoryFormatter.format(bytes: mb) == "1 MB")
    }

    @Test("Formats bytes at or above 1 GB as GB with one decimal")
    func formatsGB() {
        #expect(MemoryFormatter.format(bytes: UInt64(2.5 * Double(gb))) == "2.5 GB")
    }

    @Test("Formats exactly 1 GB as GB, not 1024 MB")
    func formatsExactlyOneGB() {
        #expect(MemoryFormatter.format(bytes: gb) == "1.0 GB")
    }

    // MARK: - formatCompact(bytes:)

    @Test("Compact format below 1 GB shows MB")
    func compactFormatMB() {
        #expect(MemoryFormatter.formatCompact(bytes: 512 * mb) == "512 MB")
    }

    @Test("Compact format at or above 1 GB shows decimal GB without unit suffix")
    func compactFormatGB() {
        #expect(MemoryFormatter.formatCompact(bytes: UInt64(2.5 * Double(gb))) == "2.5")
    }

    // MARK: - formatUsedTotal(used:total:)

    @Test("Formats used/total as GB with mixed precision")
    func formatsUsedTotal() {
        let used = UInt64(12.4 * Double(gb))
        let total = 16 * gb
        #expect(MemoryFormatter.formatUsedTotal(used: used, total: total) == "12.4 / 16 GB")
    }

    @Test("Formats zero used/total")
    func formatsZeroUsedTotal() {
        #expect(MemoryFormatter.formatUsedTotal(used: 0, total: 0) == "0.0 / 0 GB")
    }
}
