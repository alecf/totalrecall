import Testing
@testable import TotalRecallCore

@Suite("Memory River Accounting")
struct RiverAccountingTests {
    static let gb: UInt64 = 1_073_741_824

    /// 32 GB: 12 GB app memory, 4 GB wired, 10 GB compressor pool, so 26 GB
    /// used and 6 GB available.
    func system(appMemory: UInt64 = 12 * gb, wired: UInt64 = 4 * gb, compressed: UInt64 = 10 * gb,
                stored: UInt64 = 0) -> SystemMemoryInfo {
        SystemMemoryInfo(
            totalPhysical: 32 * Self.gb,
            used: appMemory + wired + compressed,
            free: 0, active: 0, inactive: 0,
            wired: wired,
            compressed: compressed,
            memoryPressure: .normal, swapTotal: 0, swapUsed: 0,
            compressorStored: stored,
            cachedFiles: 0
        )
    }

    @Test("System segments are the measured kernel, compressor, and available sizes")
    func systemSegmentsAreMeasured() {
        let result = RiverAccounting.compute(groupResident: 12 * Self.gb, system: system())
        #expect(result.kernel == 4 * Self.gb)
        #expect(result.compressor == 10 * Self.gb)
        #expect(result.available == 6 * Self.gb)
    }

    @Test("Groups that overshoot app memory are scaled down to fit it")
    func overshootScalesGroups() {
        // Shared pages counted once per group: 18 GB of resident for 12 GB.
        let result = RiverAccounting.compute(groupResident: 18 * Self.gb, system: system())
        #expect(abs(result.groupScale - 12.0 / 18.0) < 1e-9)
        #expect(result.other == 0)
        #expect(result.scaled(18 * Self.gb) <= 12 * Self.gb)
    }

    @Test("Groups that fall short leave the shortfall as Other")
    func shortfallIsOther() {
        let result = RiverAccounting.compute(groupResident: 9 * Self.gb, system: system())
        #expect(result.groupScale == 1)
        #expect(result.other == 3 * Self.gb)
    }

    @Test("Scaled groups plus system segments add up to total RAM")
    func partitionsTotal() {
        for resident in [6 * Self.gb, 12 * Self.gb, 30 * Self.gb] {
            let result = RiverAccounting.compute(groupResident: resident, system: system())
            let sum = result.scaled(resident) + result.systemSegments.reduce(0, +)
            // Within a byte or so of rounding.
            #expect(32 * Self.gb - sum < 16, "resident \(resident)")
        }
    }

    @Test("Without page counts the groups stand at their own size")
    func noPageCounts() {
        let empty = RiverAccounting.compute(groupResident: 5 * Self.gb, system: .empty)
        #expect(empty.groupScale == 1)
        #expect(empty.systemSegments.allSatisfy { $0 == 0 })
    }

    // MARK: - Estimated pool share

    @Test("Sharing the pool out removes the Compressor segment and charges groups by compressed memory")
    func poolSharedByCompressed() {
        // 10 GB pool over 40 GB compressed: 0.25 bytes of RAM per compressed byte.
        let result = RiverAccounting.compute(
            groupResident: 12 * Self.gb, groupNonResident: 40 * Self.gb,
            estimatePoolShare: true, system: system()
        )
        #expect(result.compressor == 0)
        #expect(result.poolShare(8 * Self.gb) == 2 * Self.gb)
        #expect(result.bandBytes(resident: 3 * Self.gb, nonResident: 8 * Self.gb) == 5 * Self.gb)
        #expect(result.other == 0)
        #expect(result.groupScale == 1)
    }

    @Test("With the pool shared out, groups and system segments still add up to total RAM")
    func sharedPoolPartitionsTotal() {
        // Two groups: 8 GB + 4 GB resident, 30 GB + 10 GB compressed.
        for resident in [(6 * Self.gb, 2 * Self.gb), (8 * Self.gb, 4 * Self.gb), (20 * Self.gb, 10 * Self.gb)] {
            let result = RiverAccounting.compute(
                groupResident: resident.0 + resident.1, groupNonResident: 40 * Self.gb,
                estimatePoolShare: true, system: system()
            )
            let groups = result.scaled(result.bandBytes(resident: resident.0, nonResident: 30 * Self.gb))
                + result.scaled(result.bandBytes(resident: resident.1, nonResident: 10 * Self.gb))
            let sum = groups + result.systemSegments.reduce(0, +)
            // Within a byte or so of rounding, and never over.
            #expect(sum <= 32 * Self.gb && 32 * Self.gb - sum < 16, "resident \(resident)")
        }
    }

    @Test("With nothing compressed, the pool stays its own segment")
    func nothingCompressedKeepsSegment() {
        let result = RiverAccounting.compute(
            groupResident: 12 * Self.gb, groupNonResident: 0, estimatePoolShare: true, system: system()
        )
        #expect(result.compressor == 10 * Self.gb)
        #expect(result.poolShare(5 * Self.gb) == 0)
    }

    @Test("With the estimate off, groups are charged nothing for the pool")
    func estimateOffChargesNothing() {
        let result = RiverAccounting.compute(
            groupResident: 12 * Self.gb, groupNonResident: 40 * Self.gb, system: system()
        )
        #expect(result.compressor == 10 * Self.gb)
        #expect(result.bandBytes(resident: 3 * Self.gb, nonResident: 8 * Self.gb) == 3 * Self.gb)
    }

    @Test("With the pool shared out, stubs hold only the estimated swapped part, uncompressed")
    func stubsHoldEstimatedSwap() {
        // The pool holds 16 GB of the groups' 40 GB compressed: 60% is in swap.
        let result = RiverAccounting.compute(
            groupResident: 12 * Self.gb, groupNonResident: 40 * Self.gb,
            estimatePoolShare: true, system: system(stored: 16 * Self.gb)
        )
        #expect(abs(result.swappedFraction - 0.6) < 1e-9)
        #expect(result.stubBytes(10 * Self.gb) == 6 * Self.gb)
    }

    @Test("A pool holding more than the groups' compressed memory leaves nothing in swap")
    func storedAboveSumClampsSwap() {
        let result = RiverAccounting.compute(
            groupResident: 12 * Self.gb, groupNonResident: 8 * Self.gb,
            estimatePoolShare: true, system: system(stored: 20 * Self.gb)
        )
        #expect(result.stubBytes(8 * Self.gb) == 0)
    }

    @Test("With the pool as its own segment, stubs hold all compressed memory")
    func stubsWholeWhenNotShared() {
        let result = RiverAccounting.compute(
            groupResident: 12 * Self.gb, groupNonResident: 40 * Self.gb, system: system(stored: 16 * Self.gb)
        )
        #expect(!result.sharesPool)
        #expect(result.stubBytes(10 * Self.gb) == 10 * Self.gb)
    }
}
