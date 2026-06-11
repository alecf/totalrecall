import Foundation
import Testing
@testable import TotalRecallCore

@Suite("ProcessGroup Deduplicated Footprint")
struct ProcessGroupTests {
    private func snapshot(pid: Int32, footprint: UInt64, resident: UInt64, shared: UInt64) -> ProcessSnapshot {
        let now = Date()
        return ProcessSnapshot(
            pid: pid,
            name: "proc\(pid)",
            path: "",
            commandLineArgs: [],
            parentPid: 1,
            responsiblePid: pid,
            bundleIdentifier: nil,
            workingDirectory: nil,
            physFootprint: footprint,
            residentSize: resident,
            sharedMemory: shared,
            startTimeSec: 0,
            startTimeUsec: 0,
            firstSeen: now,
            lastSeen: now,
            exitedAt: nil,
            isPartialData: false
        )
    }

    @Test("Empty process list has zero footprint")
    func emptyListIsZero() {
        #expect(ProcessGroup.computeDeduplicatedFootprint(for: []) == 0)
    }

    @Test("A single process keeps its full footprint")
    func singleProcessKeepsFullFootprint() {
        let process = snapshot(pid: 1, footprint: 100, resident: 90, shared: 20)
        #expect(ProcessGroup.computeDeduplicatedFootprint(for: [process]) == 100)
    }

    @Test("The largest process keeps its full footprint, others subtract shared memory")
    func largestKeepsFullOthersSubtractShared() {
        let large = snapshot(pid: 1, footprint: 200, resident: 180, shared: 50)
        let small = snapshot(pid: 2, footprint: 100, resident: 90, shared: 30)

        // 200 (large, unchanged) + (100 - 30) (small, deduped)
        #expect(ProcessGroup.computeDeduplicatedFootprint(for: [large, small]) == 270)
    }

    @Test("A non-largest process whose shared memory exceeds its footprint keeps its full footprint")
    func sharedMemoryExceedingFootprintIsNotSubtracted() {
        let large = snapshot(pid: 1, footprint: 200, resident: 180, shared: 50)
        // sharedMemory > physFootprint — the dedup heuristic doesn't apply
        let odd = snapshot(pid: 2, footprint: 100, resident: 90, shared: 150)

        // 200 (large, unchanged) + 100 (odd, kept as-is since shared > footprint)
        #expect(ProcessGroup.computeDeduplicatedFootprint(for: [large, odd]) == 300)
    }

    @Test("Order of input processes does not affect the total")
    func inputOrderDoesNotAffectTotal() {
        let large = snapshot(pid: 1, footprint: 200, resident: 180, shared: 50)
        let small = snapshot(pid: 2, footprint: 100, resident: 90, shared: 30)

        let total1 = ProcessGroup.computeDeduplicatedFootprint(for: [large, small])
        let total2 = ProcessGroup.computeDeduplicatedFootprint(for: [small, large])
        #expect(total1 == total2)
    }
}
