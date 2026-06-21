import Testing
@testable import TotalRecallCore

@Suite("SystemMemoryInfo")
struct SystemMemoryInfoTests {
    private let gb: UInt64 = 1024 * 1024 * 1024
    private let mb: UInt64 = 1024 * 1024

    @Test("available is free plus inactive memory")
    func availableIsFreeAndInactive() {
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
            swapUsed: 0
        )
        #expect(info.available == 3 * gb)
    }

    @Test("available is zero when free and inactive are both zero")
    func availableZeroWhenFreeAndInactiveAreZero() {
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
            swapUsed: 0
        )
        #expect(info.available == 0)
    }

    @Test("available accounts for only free and inactive, not wired or compressed")
    func availableIgnoresWiredAndCompressed() {
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
            swapUsed: 1 * gb
        )
        #expect(info.available == 10 * gb)
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
}
