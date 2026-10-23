import Foundation
import Testing
@testable import TotalRecallCore

@Suite("Compressed Memory")
struct CompressedMemoryTests {
    static let mb: UInt64 = 1024 * 1024
    static let now = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(
        pid: Int32, footprint: UInt64, resident: UInt64,
        compressed: UInt64? = nil, swapinRate: Double? = nil
    ) -> ProcessSnapshot {
        var snapshot = ProcessSnapshot(
            pid: pid, name: "proc", path: "", commandLineArgs: [], parentPid: 1, responsiblePid: pid,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: footprint, residentSize: resident, sharedMemory: 0,
            startTimeSec: 0, startTimeUsec: 0, firstSeen: Self.now, lastSeen: Self.now,
            exitedAt: nil, isPartialData: false
        )
        snapshot.compressedSize = compressed
        snapshot.swapinRate = swapinRate
        return snapshot
    }

    private func group(_ processes: [ProcessSnapshot]) -> ProcessGroup {
        ProcessGroup(
            stableIdentifier: "g", name: "App", icon: nil, classifierName: "Generic",
            explanation: nil, processes: processes, subGroups: nil,
            deduplicatedFootprint: 0, nonResidentMemory: 0
        )
    }

    // MARK: - Non-resident memory

    @Test("The kernel's compressed count wins over footprint minus resident")
    func kernelCountWins() {
        // A VM: guest RAM is a shared mapping that pads resident, so the
        // fallback reads half the real figure.
        let vm = snapshot(pid: 1, footprint: 12_000 * Self.mb, resident: 7_000 * Self.mb, compressed: 10_000 * Self.mb)
        #expect(vm.nonResidentMemory == 10_000 * Self.mb)
    }

    @Test("Without the kernel's count, non-resident falls back to footprint minus resident")
    func fallsBack() {
        #expect(snapshot(pid: 1, footprint: 300 * Self.mb, resident: 100 * Self.mb).nonResidentMemory == 200 * Self.mb)
        #expect(snapshot(pid: 1, footprint: 100 * Self.mb, resident: 300 * Self.mb).nonResidentMemory == 0)
    }

    @Test("A group sums each process's figure, mixing exact and fallback")
    func groupSumsPerProcess() {
        let g = group([
            snapshot(pid: 1, footprint: 500 * Self.mb, resident: 400 * Self.mb, compressed: 250 * Self.mb),
            // Resident above footprint must not cancel the other process's memory.
            snapshot(pid: 2, footprint: 100 * Self.mb, resident: 300 * Self.mb),
        ])
        #expect(g.rawNonResidentMemory == 250 * Self.mb)
        #expect(!g.isNonResidentExact)
    }

    @Test("A group is exact only when every process has the kernel's count")
    func exactWhenAllKnown() {
        let g = group([
            snapshot(pid: 1, footprint: 1, resident: 1, compressed: 0),
            snapshot(pid: 2, footprint: 1, resident: 1, compressed: 5),
        ])
        #expect(g.isNonResidentExact)
    }

    // MARK: - Swap-in rate

    @Test("A group's swap-in rate sums the processes that report one")
    func groupSwapinRate() {
        let g = group([
            snapshot(pid: 1, footprint: 1, resident: 1, swapinRate: 2_000_000),
            snapshot(pid: 2, footprint: 1, resident: 1, swapinRate: 500_000),
            snapshot(pid: 3, footprint: 1, resident: 1),
        ])
        #expect(g.swapinRate == 2_500_000)
        #expect(group([snapshot(pid: 1, footprint: 1, resident: 1)]).swapinRate == nil)
    }

    @Test("Swap activity below the floor isn't shown")
    func swapActivityFloor() {
        let quiet = group([snapshot(pid: 1, footprint: 1, resident: 1, swapinRate: Theme.swapActivityFloor / 2)])
        let busy = group([snapshot(pid: 1, footprint: 1, resident: 1, swapinRate: Theme.swapActivityFloor * 4)])
        #expect(Theme.visibleSwapinRate(quiet) == nil)
        #expect(Theme.visibleSwapinRate(busy) == Theme.swapActivityFloor * 4)
    }
}

@Suite("Swap Activity Tracker")
struct SwapActivityTrackerTests {
    static let start = Date(timeIntervalSince1970: 500_000)
    static let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("The first sighting has no rate")
    func firstSightingIsNil() {
        var tracker = SwapActivityTracker()
        #expect(tracker.rate(pid: 1, startTime: Self.start, swapins: 4096, now: Self.now) == nil)
    }

    @Test("The rate is the counter's change over the time between refreshes")
    func rateOverInterval() {
        var tracker = SwapActivityTracker()
        _ = tracker.rate(pid: 1, startTime: Self.start, swapins: 1_000, now: Self.now)
        let rate = tracker.rate(pid: 1, startTime: Self.start, swapins: 11_000, now: Self.now.addingTimeInterval(5))
        #expect(rate == 2_000)
    }

    @Test("A recycled PID starts over instead of differencing another process's counter")
    func recycledPID() {
        var tracker = SwapActivityTracker()
        _ = tracker.rate(pid: 1, startTime: Self.start, swapins: 1_000_000, now: Self.now)
        let rate = tracker.rate(pid: 1, startTime: Self.start.addingTimeInterval(60), swapins: 10,
                                now: Self.now.addingTimeInterval(5))
        #expect(rate == nil)
    }

    @Test("Exited processes are forgotten")
    func retainDropsExited() {
        var tracker = SwapActivityTracker()
        _ = tracker.rate(pid: 1, startTime: Self.start, swapins: 1, now: Self.now)
        _ = tracker.rate(pid: 2, startTime: Self.start, swapins: 1, now: Self.now)
        tracker.retain(pids: [2])
        #expect(Set(tracker.samples.keys) == [2])
    }
}
