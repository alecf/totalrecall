import Foundation
import Testing
@testable import TotalRecallCore

@Suite("Proportional Share Cache")
struct ProportionalShareCacheTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    func candidate(_ pid: Int32, age: TimeInterval) -> ProportionalShareCache.Candidate {
        .init(pid: pid, startTime: Self.now.addingTimeInterval(-age))
    }

    func walk(private bytes: UInt64, shared: [UInt32: UInt64] = [:]) -> ProportionalShareCache.Walk {
        .init(privateBytes: bytes, sharedBytes: shared)
    }

    /// A cache past warm-up, so fresh processes order newest first.
    func warmCache() -> ProportionalShareCache {
        var cache = ProportionalShareCache()
        _ = cache.walkOrder([], now: Self.now, cooloff: 15)
        return cache
    }

    // MARK: - Scheduling

    @Test("Processes inside the cooloff are never walked")
    func cooloffSkipsYoungProcesses() {
        var cache = ProportionalShareCache()
        let order = cache.walkOrder([candidate(1, age: 5), candidate(2, age: 20)], now: Self.now, cooloff: 15)
        #expect(order == [2])
    }

    @Test("Before warm-up, never-measured processes come largest first")
    func warmupLargestFirst() {
        var cache = ProportionalShareCache()
        let order = cache.walkOrder(
            [.init(pid: 1, startTime: Self.now.addingTimeInterval(-300), residentSize: 50),
             .init(pid: 2, startTime: Self.now.addingTimeInterval(-20), residentSize: 900),
             .init(pid: 3, startTime: Self.now.addingTimeInterval(-60), residentSize: 400)],
            now: Self.now, cooloff: 15
        )
        #expect(order == [2, 3, 1])
        #expect(!cache.isWarm)
    }

    @Test("Before warm-up, never-measured processes all come before any re-walk")
    func warmupSkipsRewalks() {
        var cache = ProportionalShareCache()
        cache.record(pid: 10, startTime: candidate(10, age: 900).startTime, walk: walk(private: 1),
                     residentSize: 2, now: Self.now.addingTimeInterval(-5))
        let order = cache.walkOrder(
            [candidate(10, age: 900), candidate(1, age: 60), candidate(2, age: 30)],
            now: Self.now, cooloff: 15
        )
        #expect(order.last == 10)
    }

    @Test("Once warm, never-measured processes come newest first")
    func freshNewestFirst() {
        var cache = warmCache()
        #expect(cache.isWarm)
        let order = cache.walkOrder(
            [candidate(1, age: 300), candidate(2, age: 20), candidate(3, age: 60)],
            now: Self.now, cooloff: 15
        )
        #expect(order == [2, 3, 1])
    }

    @Test("Fresh and stale processes interleave, so neither starves")
    func interleavesFreshAndStale() {
        var cache = warmCache()
        cache.record(pid: 10, startTime: candidate(10, age: 900).startTime, walk: walk(private: 1),
                     residentSize: 2, now: Self.now.addingTimeInterval(-100))
        cache.record(pid: 11, startTime: candidate(11, age: 900).startTime, walk: walk(private: 1),
                     residentSize: 2, now: Self.now.addingTimeInterval(-50))
        let order = cache.walkOrder(
            [candidate(10, age: 900), candidate(11, age: 900),
             candidate(1, age: 20), candidate(2, age: 30), candidate(3, age: 40)],
            now: Self.now, cooloff: 15
        )
        // A burst of new processes still lets the stalest old ones through.
        #expect(order == [1, 10, 2, 11, 3])
    }

    // MARK: - Proportional shares

    @Test("A shared object's pages split evenly across the processes mapping it")
    func sharedPagesSplitAcrossMappers() {
        var cache = ProportionalShareCache()
        // Both map object 7 (400 bytes); each has 100 private.
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 100, shared: [7: 400]), residentSize: 500, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(private: 100, shared: [7: 400]), residentSize: 500, now: Self.now)
        let shares = cache.shares()
        #expect(shares.proportionalResident(pid: 1, startTime: Self.now, residentSize: 500) == 300)
    }

    @Test("Proportional sizes add up to each page counted once")
    func pssSumsToPhysicalTotal() {
        var cache = ProportionalShareCache()
        // Physical pages: 100 + 200 private, object 7 = 400, object 8 = 90.
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 100, shared: [7: 400, 8: 90]), residentSize: 590, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(private: 200, shared: [7: 400]), residentSize: 600, now: Self.now)
        cache.record(pid: 3, startTime: Self.now, walk: walk(private: 0, shared: [8: 90]), residentSize: 90, now: Self.now)
        let shares = cache.shares()
        let total = shares.proportionalResident(pid: 1, startTime: Self.now, residentSize: 590)
            + shares.proportionalResident(pid: 2, startTime: Self.now, residentSize: 600)
            + shares.proportionalResident(pid: 3, startTime: Self.now, residentSize: 90)
        #expect(total == 100 + 200 + 400 + 90)
    }

    @Test("When a mapper exits, its share of an object returns to the others")
    func exitedMapperReleasesShare() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 0, shared: [7: 400]), residentSize: 400, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(private: 0, shared: [7: 400]), residentSize: 400, now: Self.now)
        cache.retain([.init(pid: 1, startTime: Self.now)])
        #expect(cache.shares().proportionalResident(pid: 1, startTime: Self.now, residentSize: 400) == 400)
    }

    @Test("Re-walking a process doesn't double-count its mappings")
    func rewalkReplacesMappings() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 0, shared: [7: 400]), residentSize: 400, now: Self.now)
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 0, shared: [7: 400]), residentSize: 400, now: Self.now)
        #expect(cache.shares().proportionalResident(pid: 1, startTime: Self.now, residentSize: 400) == 400)
    }

    @Test("A share applies to the current resident size")
    func shareAppliesToCurrentResident() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 25), residentSize: 100, now: Self.now)
        #expect(cache.shares().proportionalResident(pid: 1, startTime: Self.now, residentSize: 400) == 100)
    }

    @Test("Unmeasured and unreadable processes use the resident-weighted default")
    func defaultShare() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(private: 10), residentSize: 100, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(private: 290), residentSize: 300, now: Self.now)
        cache.record(pid: 3, startTime: Self.now, walk: nil, residentSize: 100, now: Self.now)
        let shares = cache.shares()
        #expect(abs(shares.defaultShare - 0.75) < 1e-9)
        #expect(shares.proportionalResident(pid: 3, startTime: Self.now, residentSize: 200) == 150)
        #expect(shares.proportionalResident(pid: 99, startTime: Self.now, residentSize: 40) == 30)
    }

    @Test("With nothing measured, resident counts as proportional")
    func emptyDefaultIsOne() {
        #expect(ProportionalShareCache().shares().defaultShare == 1)
    }

    // MARK: - Proportional compressed

    func walk(compressed bytes: UInt64, shared: [UInt32: UInt64] = [:]) -> ProportionalShareCache.Walk {
        .init(privateBytes: 0, sharedBytes: [:], privateCompressedBytes: bytes, sharedCompressedBytes: shared)
    }

    @Test("Compressed pages of a shared object split across the processes mapping it")
    func compressedSplitsAcrossMappers() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(compressed: 100, shared: [7: 400]),
                     residentSize: 0, compressedSize: 500, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(compressed: 0, shared: [7: 400]),
                     residentSize: 0, compressedSize: 400, now: Self.now)
        let shares = cache.shares()
        #expect(shares.proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 500) == 300)
        #expect(shares.proportionalCompressed(pid: 2, startTime: Self.now, compressedSize: 400) == 200)
    }

    @Test("Resident and compressed mapper counts are kept apart")
    func compressedMappersIndependent() {
        var cache = ProportionalShareCache()
        // Process 2 maps object 7's resident pages but none of its compressed ones.
        cache.record(pid: 1, startTime: Self.now,
                     walk: .init(privateBytes: 0, sharedBytes: [7: 100], sharedCompressedBytes: [7: 400]),
                     residentSize: 100, compressedSize: 400, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(private: 0, shared: [7: 100]),
                     residentSize: 100, compressedSize: 0, now: Self.now)
        let shares = cache.shares()
        #expect(shares.proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 400) == 400)
        #expect(shares.proportionalResident(pid: 1, startTime: Self.now, residentSize: 100) == 50)
    }

    @Test("Between walks, the compressed figure moves by the kernel count's change")
    func compressedTracksKernelDelta() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(compressed: 600),
                     residentSize: 0, compressedSize: 1000, now: Self.now)
        let shares = cache.shares()
        #expect(shares.proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 1300) == 900)
        // A large drop floors at zero rather than wrapping.
        #expect(shares.proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 0) == 0)
    }

    @Test("A small kernel count at the walk doesn't multiply a large shared share")
    func compressedDeltaIsAdditive() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(compressed: 0, shared: [7: 1000]),
                     residentSize: 0, compressedSize: 10, now: Self.now)
        #expect(cache.shares().proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 20) == 1010)
    }

    @Test("No proportional compressed figure without a walk or a kernel count")
    func compressedNeedsWalkAndCount() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(compressed: 100), residentSize: 0,
                     compressedSize: nil, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: nil, residentSize: 0, compressedSize: 100, now: Self.now)
        cache.record(pid: 3, startTime: Self.now, walk: walk(compressed: 100), residentSize: 0,
                     compressedSize: 100, now: Self.now)
        let shares = cache.shares()
        #expect(shares.proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 100) == nil)
        #expect(shares.proportionalCompressed(pid: 2, startTime: Self.now, compressedSize: 100) == nil)
        #expect(shares.proportionalCompressed(pid: 3, startTime: Self.now, compressedSize: nil) == nil)
        #expect(shares.proportionalCompressed(pid: 99, startTime: Self.now, compressedSize: 100) == nil)
        // A recycled PID doesn't inherit the old process's walk.
        #expect(shares.proportionalCompressed(pid: 3, startTime: Self.now.addingTimeInterval(1), compressedSize: 100) == nil)
    }

    @Test("When a mapper exits, its compressed share returns to the others")
    func exitedMapperReleasesCompressedShare() {
        var cache = ProportionalShareCache()
        cache.record(pid: 1, startTime: Self.now, walk: walk(compressed: 0, shared: [7: 400]),
                     residentSize: 0, compressedSize: 400, now: Self.now)
        cache.record(pid: 2, startTime: Self.now, walk: walk(compressed: 0, shared: [7: 400]),
                     residentSize: 0, compressedSize: 400, now: Self.now)
        cache.retain([.init(pid: 1, startTime: Self.now)])
        #expect(cache.shares().proportionalCompressed(pid: 1, startTime: Self.now, compressedSize: 400) == 400)
    }

    @Test("A recycled PID is treated as never measured")
    func recycledPIDIsFresh() {
        var cache = ProportionalShareCache()
        cache.record(pid: 7, startTime: candidate(7, age: 900).startTime, walk: walk(private: 1),
                     residentSize: 2, now: Self.now)
        let recycled = candidate(7, age: 30)
        cache.retain([recycled])
        #expect(cache.entries.isEmpty)
    }
}
