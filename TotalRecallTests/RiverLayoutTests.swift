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

    // MARK: - Regression: free segment must never be clipped

    @Test("Free segment stays visible with many process groups")
    func freeSegmentVisibleWithManyGroups() {
        let result = layout(width: 600)
        #expect(result.freeWidth > 0)
    }

    @Test("Segments plus gaps never overflow the bar width")
    func neverOverflows() {
        for width in [320.0, 480.0, 600.0, 900.0] {
            let result = layout(width: width)
            let segmentCount = result.processWidths.count + (result.freeWidth > 0 ? 1 : 0)
            let gaps = Double(max(0, segmentCount - 1)) * 1
            let total = result.processWidths.reduce(0, +) + result.freeWidth + gaps
            #expect(total <= width + 0.5, "total \(total) exceeded width \(width)")
        }
    }

    @Test("Free segment keeps its proportional share of total RAM")
    func freeSegmentProportional() {
        let width = 600.0
        let result = layout(width: width)
        let segmentCount = result.processWidths.count + 1
        let gaps = Double(segmentCount - 1) * 1
        let content = width - gaps
        let expectedFreeFraction = Double(Self.freeBytes) / Double(Self.totalPhysical)
        let actualFreeFraction = result.freeWidth / content
        #expect(abs(actualFreeFraction - expectedFreeFraction) < 0.01)
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
        #expect(result.processWidths.count == 2)
        // Larger footprint gets the wider segment.
        #expect(result.processWidths[1] > result.processWidths[0])
    }
}
