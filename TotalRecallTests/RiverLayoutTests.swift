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

/// Depths for the Memory River's lower band, where each segment's stub hangs
/// below the midline in proportion to how much of the group is compressed or
/// swapped out.
@Suite("Memory River Depths")
struct RiverDepthTests {
    static let bandHeight = 32.0
    /// Deliberately deeper than the band: a stub may hang half again as far as
    /// the band is tall before it clips, so the common "more swapped than
    /// resident" case renders in full.
    static let depthCap = 48.0
    static let quantum = 12.0
    static let deadband = 4.0
    static let floor: UInt64 = 100_000_000

    func depths(
        residents: [UInt64],
        nonResidents: [UInt64],
        currentStep: Double = 0
    ) -> RiverDepths {
        RiverLayout.computeDepths(
            residents: residents,
            nonResidents: nonResidents,
            bandHeight: Self.bandHeight,
            depthCap: Self.depthCap,
            hiddenFloor: Self.floor,
            currentStep: currentStep,
            quantum: Self.quantum,
            shrinkDeadband: Self.deadband
        )
    }

    // MARK: - The area claim

    @Test("Stub depth is the band height times non-resident over resident")
    func depthIsRatioOfBandHeight() {
        let result = depths(
            residents: [8_000_000_000, 2_000_000_000],
            nonResidents: [2_000_000_000, 1_000_000_000]
        )
        #expect(abs(result.depths[0] - 8.0) < 0.001)   // 32 * 2/8
        #expect(abs(result.depths[1] - 16.0) < 0.001)  // 32 * 1/2
    }

    /// The point of the encoding: bytes per pixel-squared is one global
    /// constant, so a wide flat stub and a narrow deep one of equal area hold
    /// equal memory. Pairs widths from `compute` with depths from
    /// `computeDepths` because that product is the actual claim.
    @Test("Stub area per non-resident byte is equal across segments")
    func stubAreaPerByteIsConstant() {
        let residents: [UInt64] = [8_000_000_000, 2_000_000_000]
        let nonResidents: [UInt64] = [2_000_000_000, 1_000_000_000]
        let widths = RiverLayout.compute(
            footprints: residents,
            freeBytes: 4_000_000_000,
            totalPhysical: 32_000_000_000,
            totalWidth: 600,
            minSegmentWidth: 3,
            gap: 1
        ).processWidths
        let result = depths(residents: residents, nonResidents: nonResidents)

        let areaPerByte = zip(zip(widths, result.depths), nonResidents).map {
            pair, nonResident in
            (pair.0 * pair.1) / Double(nonResident)
        }
        #expect(abs(areaPerByte[0] - areaPerByte[1]) < 0.0001 * areaPerByte[0])
    }

    // MARK: - Clamping

    @Test("Stubs clamp to the depth cap, not the band height")
    func stubsClampToTheDepthCap() {
        let result = depths(
            residents: [40_000_000],
            nonResidents: [600_000_000]  // 15x its resident size
        )
        #expect(result.depths[0] == Self.depthCap)
        #expect(result.clipped[0])
    }

    /// The reason the cap is decoupled from the band: an app with more swapped
    /// than resident is common, and clipping every one of them made the fade
    /// the default rather than the exception.
    @Test("A group with more swapped than resident renders in full")
    func moreSwappedThanResidentIsNotClipped() {
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [1_000_000_000]  // ratio 1.0
        )
        #expect(abs(result.depths[0] - 32.0) < 0.001)
        #expect(!result.clipped[0])
    }

    @Test("A stub exactly at the depth cap is not reported as clipped")
    func exactlyAtCapIsNotClipped() {
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [1_500_000_000]  // ratio 1.5 → 32 * 1.5 = 48
        )
        #expect(abs(result.depths[0] - Self.depthCap) < 0.001)
        #expect(!result.clipped[0])
    }

    @Test("A stub just past the depth cap is reported as clipped")
    func justPastCapIsClipped() {
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [1_600_000_000]  // ratio 1.6 → 51.2, over the cap
        )
        #expect(result.depths[0] == Self.depthCap)
        #expect(result.clipped[0])
    }

    // MARK: - The hidden floor

    @Test("Non-resident memory below the floor produces no stub")
    func belowFloorProducesNoStub() {
        let result = depths(
            residents: [40_000_000],
            nonResidents: [99_000_000]
        )
        #expect(result.depths[0] == 0)
        #expect(!result.clipped[0])
    }

    // MARK: - Quantized container height

    @Test("Reserved height rounds the deepest stub up to the next quantum")
    func reservedRoundsUp() {
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [300_000_000]  // depth 9.6, rounds to 12
        )
        #expect(result.reserved == Self.bandHeight + 12)
    }

    @Test("Reserved height is just the band when nothing is swapped")
    func reservedIsBandWhenNoStubs() {
        let result = depths(residents: [1_000_000_000], nonResidents: [0])
        #expect(result.reserved == Self.bandHeight)
    }

    // MARK: - Hysteresis

    @Test("Container grows immediately when a stub outgrows the current step")
    func growsImmediately() {
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [900_000_000],  // depth 28.8
            currentStep: 24
        )
        #expect(result.reserved == Self.bandHeight + 36)
    }

    @Test("Container holds its step while the deepest stub stays near the boundary")
    func holdsStepWithinDeadband() {
        // Step 36 spans (24, 36]. A stub at 22.5 is below the boundary but not
        // clear of the deadband, so the height must not move.
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [703_125_000],  // depth 22.5
            currentStep: 36
        )
        #expect(result.reserved == Self.bandHeight + 36)
    }

    @Test("Container shrinks once the deepest stub clears the deadband")
    func shrinksBeyondDeadband() {
        // Step 36 spans (24, 36]; shrinking requires falling below 24 - 4 = 20.
        let result = depths(
            residents: [1_000_000_000],
            nonResidents: [593_750_000],  // depth 19.0
            currentStep: 36
        )
        #expect(result.reserved == Self.bandHeight + 24)
    }

    // MARK: - Edge cases

    @Test("A group with no resident memory yields a finite depth")
    func zeroResidentDoesNotDivideByZero() {
        let result = depths(residents: [0], nonResidents: [500_000_000])
        #expect(result.depths[0] == Self.depthCap)
        #expect(result.clipped[0])
        #expect(result.reserved.isFinite)
    }

    @Test("No groups yields an empty band")
    func emptyInput() {
        let result = depths(residents: [], nonResidents: [])
        #expect(result.depths.isEmpty)
        #expect(result.clipped.isEmpty)
        #expect(result.reserved == Self.bandHeight)
    }
}
