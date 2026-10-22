import Testing
@testable import TotalRecallCore

@Suite("Memory River Accounting")
struct RiverAccountingTests {
    static let gb: UInt64 = 1_073_741_824

    /// 32 GB: 12 GB app memory, 4 GB wired, 10 GB compressor pool, so 26 GB
    /// used and 6 GB available.
    func system(appMemory: UInt64 = 12 * gb, wired: UInt64 = 4 * gb, compressed: UInt64 = 10 * gb) -> SystemMemoryInfo {
        SystemMemoryInfo(
            totalPhysical: 32 * Self.gb,
            used: appMemory + wired + compressed,
            free: 0, active: 0, inactive: 0,
            wired: wired,
            compressed: compressed,
            memoryPressure: .normal, swapTotal: 0, swapUsed: 0,
            compressorStored: 0,
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
}
