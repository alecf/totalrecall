import Foundation
import Testing
@testable import TotalRecallCore

@Suite("Private Share Cache")
struct PrivateShareCacheTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    func candidate(_ pid: Int32, age: TimeInterval) -> PrivateShareCache.Candidate {
        .init(pid: pid, startTime: Self.now.addingTimeInterval(-age))
    }

    // MARK: - Scheduling

    @Test("Processes inside the cooloff are never walked")
    func cooloffSkipsYoungProcesses() {
        var cache = PrivateShareCache()
        let order = cache.walkOrder([candidate(1, age: 5), candidate(2, age: 20)], now: Self.now, cooloff: 15)
        #expect(order == [2])
    }

    @Test("Before warm-up, never-measured processes come largest first")
    func warmupLargestFirst() {
        var cache = PrivateShareCache()
        let order = cache.walkOrder(
            [.init(pid: 1, startTime: Self.now.addingTimeInterval(-300), residentSize: 50),
             .init(pid: 2, startTime: Self.now.addingTimeInterval(-20), residentSize: 900),
             .init(pid: 3, startTime: Self.now.addingTimeInterval(-60), residentSize: 400)],
            now: Self.now, cooloff: 15
        )
        #expect(order == [2, 3, 1])
        #expect(!cache.isWarm)
    }

    @Test("Once warm, never-measured processes come newest first")
    func freshNewestFirst() {
        var cache = PrivateShareCache()
        _ = cache.walkOrder([], now: Self.now, cooloff: 15)
        #expect(cache.isWarm)
        let order = cache.walkOrder(
            [candidate(1, age: 300), candidate(2, age: 20), candidate(3, age: 60)],
            now: Self.now, cooloff: 15
        )
        #expect(order == [2, 3, 1])
    }

    @Test("Fresh and stale processes interleave, so neither starves")
    func interleavesFreshAndStale() {
        var cache = PrivateShareCache()
        _ = cache.walkOrder([], now: Self.now, cooloff: 15)
        // 10 and 11 measured, 10 longer ago.
        cache.record(pid: 10, startTime: candidate(10, age: 900).startTime,
                     privateBytes: 1, residentSize: 2, now: Self.now.addingTimeInterval(-100))
        cache.record(pid: 11, startTime: candidate(11, age: 900).startTime,
                     privateBytes: 1, residentSize: 2, now: Self.now.addingTimeInterval(-50))
        let order = cache.walkOrder(
            [candidate(10, age: 900), candidate(11, age: 900),
             candidate(1, age: 20), candidate(2, age: 30), candidate(3, age: 40)],
            now: Self.now, cooloff: 15
        )
        // A burst of new processes still lets the stalest old ones through.
        #expect(order == [1, 10, 2, 11, 3])
    }

    @Test("A recycled PID is treated as never measured")
    func recycledPIDIsFresh() {
        var cache = PrivateShareCache()
        cache.record(pid: 7, startTime: candidate(7, age: 900).startTime, privateBytes: 1, residentSize: 2, now: Self.now)
        let recycled = candidate(7, age: 30)
        #expect(cache.privateResident(pid: 7, startTime: recycled.startTime, residentSize: 100, defaultShare: 0.9) == 90)
        cache.retain([recycled])
        #expect(cache.entries.isEmpty)
    }

    // MARK: - Shares

    @Test("A measured share applies to the current resident size")
    func measuredShareApplies() {
        var cache = PrivateShareCache()
        let start = candidate(1, age: 900).startTime
        cache.record(pid: 1, startTime: start, privateBytes: 25, residentSize: 100, now: Self.now)
        #expect(cache.privateResident(pid: 1, startTime: start, residentSize: 400, defaultShare: 1) == 100)
    }

    @Test("A share is taken against the process's resident size")
    func shareUsesResidentSize() {
        var cache = PrivateShareCache()
        cache.record(pid: 1, startTime: Self.now, privateBytes: 30, residentSize: 120, now: Self.now)
        #expect(cache.entries[1]?.share == 0.25)
    }

    @Test("The default share is resident-weighted across successful walks")
    func defaultShareIsWeighted() {
        var cache = PrivateShareCache()
        cache.record(pid: 1, startTime: Self.now, privateBytes: 10, residentSize: 100, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, privateBytes: 290, residentSize: 300, now: Self.now)
        cache.record(pid: 3, startTime: Self.now, privateBytes: nil, residentSize: 100, now: Self.now)
        #expect(abs(cache.defaultShare - 0.75) < 1e-9)
    }

    @Test("A process whose walk failed uses the default share")
    func failedWalkUsesDefault() {
        var cache = PrivateShareCache()
        cache.record(pid: 3, startTime: Self.now, privateBytes: nil, residentSize: 100, now: Self.now)
        #expect(cache.privateResident(pid: 3, startTime: Self.now, residentSize: 200, defaultShare: 0.5) == 100)
    }

    @Test("With nothing measured, resident counts as private")
    func emptyDefaultIsOne() {
        #expect(PrivateShareCache().defaultShare == 1)
    }

    @Test("Exited processes are dropped")
    func retainDropsExited() {
        var cache = PrivateShareCache()
        cache.record(pid: 1, startTime: Self.now, privateBytes: 1, residentSize: 2, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, privateBytes: 1, residentSize: 2, now: Self.now)
        cache.retain([.init(pid: 2, startTime: Self.now)])
        #expect(Set(cache.entries.keys) == [2])
    }
}
