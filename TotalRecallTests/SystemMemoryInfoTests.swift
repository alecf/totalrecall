import Testing
@testable import TotalRecallCore

@Suite("SystemMemoryInfo")
struct SystemMemoryInfoTests {
    private let gb: UInt64 = 1024 * 1024 * 1024
    private let mb: UInt64 = 1024 * 1024

    @Test("available is everything not used, regardless of inactive pages")
    func availableIsTotalMinusUsed() {
        let info = SystemMemoryInfo(
            totalPhysical: 16 * gb,
            used: 10 * gb,
            free: 2 * gb,
            active: 6 * gb,
            inactive: 1 * gb,
            wired: 3 * gb,
            compressed: 512 * mb,
            memoryPressure: .normal,
            swapTotal: 0,
            swapUsed: 0,
            compressorStored: 0,
            cachedFiles: 0
        )
        // Not free + inactive (3 GB): inactive app memory is still in use.
        #expect(info.available == 6 * gb)
    }

    @Test("available is zero when everything is used")
    func availableZeroWhenFullyUsed() {
        let info = SystemMemoryInfo(
            totalPhysical: 16 * gb,
            used: 16 * gb,
            free: 0,
            active: 16 * gb,
            inactive: 0,
            wired: 0,
            compressed: 0,
            memoryPressure: .critical,
            swapTotal: 0,
            swapUsed: 0,
            compressorStored: 0,
            cachedFiles: 0
        )
        #expect(info.available == 0)
    }

    @Test("available and used partition physical RAM")
    func availableAndUsedPartitionRAM() {
        let info = SystemMemoryInfo(
            totalPhysical: 32 * gb,
            used: 24 * gb,
            free: 4 * gb,
            active: 12 * gb,
            inactive: 6 * gb,
            wired: 6 * gb,
            compressed: 2 * gb,
            memoryPressure: .warning,
            swapTotal: 8 * gb,
            swapUsed: 1 * gb,
            compressorStored: 0,
            cachedFiles: 0
        )
        #expect(info.available == 8 * gb)
        #expect(info.available + info.used == info.totalPhysical)
    }

    @Test("empty static property has all fields zero and normal pressure")
    func emptyHasAllFieldsZero() {
        let empty = SystemMemoryInfo.empty
        #expect(empty.totalPhysical == 0)
        #expect(empty.used == 0)
        #expect(empty.free == 0)
        #expect(empty.active == 0)
        #expect(empty.inactive == 0)
        #expect(empty.wired == 0)
        #expect(empty.compressed == 0)
        #expect(empty.swapTotal == 0)
        #expect(empty.swapUsed == 0)
        #expect(empty.memoryPressure == .normal)
    }

    @Test("empty available is zero")
    func emptyAvailableIsZero() {
        #expect(SystemMemoryInfo.empty.available == 0)
    }

    @Test("MemoryPressure raw values are stable strings")
    func memoryPressureRawValues() {
        #expect(MemoryPressure.normal.rawValue == "normal")
        #expect(MemoryPressure.warning.rawValue == "warning")
        #expect(MemoryPressure.critical.rawValue == "critical")
    }

    @Test("used is app memory less purgeable, plus wired and the compressor pool")
    func usedFollowsActivityMonitor() {
        let used = SystemMemoryInfo.usedBytes(
            internal: 12 * gb, purgeable: 1 * gb, wired: 4 * gb, compressed: 10 * gb,
            totalPhysical: 32 * gb
        )
        #expect(used == 25 * gb)
    }

    @Test("used never exceeds physical RAM")
    func usedClampsToTotal() {
        let used = SystemMemoryInfo.usedBytes(
            internal: 30 * gb, purgeable: 0, wired: 4 * gb, compressed: 10 * gb,
            totalPhysical: 32 * gb
        )
        #expect(used == 32 * gb)
    }

    @Test("purgeable larger than internal counts no app memory")
    func purgeableBeyondInternal() {
        let used = SystemMemoryInfo.usedBytes(
            internal: 1 * gb, purgeable: 2 * gb, wired: 4 * gb, compressed: 0,
            totalPhysical: 32 * gb
        )
        #expect(used == 4 * gb)
    }

    @Test("cached files are file-backed plus purgeable pages")
    func cachedFiles() {
        #expect(SystemMemoryInfo.cachedFileBytes(external: 6 * gb, purgeable: 1 * gb) == 7 * gb)
    }

    @Test("available is zero without page counts, not all of RAM")
    func availableZeroWithoutPageCounts() {
        let info = SystemMemoryInfo(
            totalPhysical: 32 * gb, used: 0, free: 0, active: 0, inactive: 0,
            wired: 0, compressed: 0, memoryPressure: .normal, swapTotal: 0, swapUsed: 0,
            compressorStored: 0, cachedFiles: 0
        )
        #expect(info.available == 0)
    }
}
