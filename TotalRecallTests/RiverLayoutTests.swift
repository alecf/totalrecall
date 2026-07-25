import Testing
@testable import TotalRecallCore

@Suite("Memory River Layout")
struct RiverLayoutTests {
    // A realistic "busy machine" shape: a few large groups plus a long tail of
    // tiny ones, with a meaningful free region. This is the configuration that
    // regressed — see the regression test below.
    static let busyFootprints: [UInt64] = {
        let big: [UInt64] = [
            10_400_000_000, 7_200_000_000, 7_000_000_000, 4_400_000_000, 2_600_000_000,
        ]
        let tail = Array(repeating: UInt64(20_000_000), count: 83) // 83 ~20 MB groups
        return big + tail
    }()
    static let totalPhysical: UInt64 = 32_000_000_000
    static let freeBytes: UInt64 = 6_500_000_000

    func layout(width: Double) -> RiverLayout {
        RiverLayout.compute(
            footprints: Self.busyFootprints,
            freeBytes: Self.freeBytes,
            totalPhysical: Self.totalPhysical,
            totalWidth: width,
            minSegmentWidth: 3,
            gap: 1
        )
    }

    // MARK: - Regression: minimum widths must never overflow

    @Test("Many minimum-width groups still fit the bar")
    func manyMinimumWidthGroupsStillFitTheBar() {
        let result = layout(width: 600)
        #expect(result.processWidths.allSatisfy { $0 >= 0 })
        #expect(result.otherWidth >= 0)
        #expect(result.freeWidth >= 0)
    }

    @Test("Segments plus gaps never overflow the bar width")
    func neverOverflows() {
        for width in [320.0, 480.0, 600.0, 900.0] {
            let result = layout(width: width)
            let segmentCount = result.processWidths.count
                + (result.otherWidth > 0 ? 1 : 0)
                + (result.freeWidth > 0 ? 1 : 0)
            let gaps = Double(max(0, segmentCount - 1)) * 1
            let total = result.processWidths.reduce(0, +) + result.otherWidth + result.freeWidth + gaps
            #expect(total <= width + 0.5, "total \(total) exceeded width \(width)")
        }
    }

    @Test("Free segment keeps its proportional share of total RAM")
    func freeSegmentProportional() {
        let width = 600.0
        let result = RiverLayout.compute(
            footprints: [8_000_000_000, 4_000_000_000, 2_000_000_000],
            freeBytes: Self.freeBytes,
            totalPhysical: Self.totalPhysical,
            totalWidth: width,
            minSegmentWidth: 3,
            gap: 1
        )
        let segmentCount = result.processWidths.count + (result.otherWidth > 0 ? 1 : 0) + 1
        let gaps = Double(segmentCount - 1) * 1
        let content = width - gaps
        let expectedFreeFraction = Double(Self.freeBytes) / Double(Self.totalPhysical)
        let actualFreeFraction = result.freeWidth / content
        #expect(abs(actualFreeFraction - expectedFreeFraction) < 0.01)
    }

    @Test("Process segment width matches total RAM percentage")
    func processSegmentMatchesTotalRAMPercentage() {
        let result = RiverLayout.compute(
            footprints: [31, 10],
            freeBytes: 20,
            totalPhysical: 100,
            totalWidth: 403,
            minSegmentWidth: 0,
            gap: 1
        )
        let segmentCount = result.processWidths.count
            + (result.otherWidth > 0 ? 1 : 0)
            + (result.freeWidth > 0 ? 1 : 0)
        let content = 403.0 - Double(segmentCount - 1)
        #expect(abs((result.processWidths[0] / content) - 0.31) < 0.001)
    }

    @Test("Free shrinks before process percentages when reported totals overlap")
    func freeShrinksBeforeProcessPercentagesWhenOverlapping() {
        let result = RiverLayout.compute(
            footprints: [31, 60],
            freeBytes: 20,
            totalPhysical: 100,
            totalWidth: 303,
            minSegmentWidth: 0,
            gap: 1
        )
        let segmentCount = result.processWidths.count + (result.freeWidth > 0 ? 1 : 0)
        let content = 303.0 - Double(segmentCount - 1)
        #expect(abs((result.processWidths[0] / content) - 0.31) < 0.001)
        #expect(abs((result.freeWidth / content) - 0.09) < 0.001)
    }

    // MARK: - Edge cases

    @Test("No free segment when free bytes is zero")
    func noFreeWhenZero() {
        let result = RiverLayout.compute(
            footprints: [1_000, 2_000],
            freeBytes: 0,
            totalPhysical: 32_000_000_000,
            totalWidth: 600,
            minSegmentWidth: 3,
            gap: 1
        )
        #expect(result.freeWidth == 0)
    }

    @Test("Falls back to full-width process layout before system memory arrives")
    func fallbackWithoutTotalPhysical() {
        let result = RiverLayout.compute(
            footprints: [1_000, 3_000],
            freeBytes: 0,
            totalPhysical: 0,
            totalWidth: 600,
            minSegmentWidth: 3,
            gap: 1
        )
        #expect(result.freeWidth == 0)
        #expect(result.otherWidth == 0)
        #expect(result.processWidths.count == 2)
        // Larger footprint gets the wider segment.
        #expect(result.processWidths[1] > result.processWidths[0])
    }
}
