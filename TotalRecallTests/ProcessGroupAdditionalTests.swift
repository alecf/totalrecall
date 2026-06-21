import Testing
import Foundation
@testable import TotalRecallCore

@Suite("ProcessGroup - additional properties")
struct ProcessGroupAdditionalTests {
    private let mb: UInt64 = 1024 * 1024

    private func makeSnapshot(pid: Int32, footprint: UInt64, resident: UInt64, shared: UInt64 = 0) -> ProcessSnapshot {
        let now = Date()
        return ProcessSnapshot(
            pid: pid, name: "proc\(pid)", path: "/usr/bin/proc",
            commandLineArgs: [],
            parentPid: 1, responsiblePid: pid,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: footprint, residentSize: resident, sharedMemory: shared,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
    }

    private func makeGroup(
        processes: [ProcessSnapshot],
        subGroups: [ProcessGroup]? = nil,
        footprint: UInt64? = nil
    ) -> ProcessGroup {
        let fp = footprint ?? processes.reduce(0) { $0 + $1.physFootprint }
        let nonRes = processes.reduce(0) { $0 + $1.nonResidentMemory }
        return ProcessGroup(
            stableIdentifier: "test:group",
            name: "Test",
            icon: nil,
            classifierName: "Test",
            explanation: "test explanation",
            processes: processes,
            subGroups: subGroups,
            deduplicatedFootprint: fp,
            nonResidentMemory: nonRes
        )
    }

    // MARK: - rawNonResidentMemory

    @Test("rawNonResidentMemory equals totalFootprint minus residentMemory when positive")
    func rawNonResidentMemoryPositive() {
        let p = makeSnapshot(pid: 1, footprint: 100 * mb, resident: 80 * mb)
        let group = makeGroup(processes: [p])
        #expect(group.rawNonResidentMemory == 20 * mb)
    }

    @Test("rawNonResidentMemory is zero when resident exceeds footprint")
    func rawNonResidentMemoryZeroWhenResidentExceeds() {
        // Synthetic case where resident > footprint
        let p = makeSnapshot(pid: 1, footprint: 80 * mb, resident: 100 * mb)
        let group = makeGroup(processes: [p])
        #expect(group.rawNonResidentMemory == 0)
    }

    @Test("rawNonResidentMemory is zero for zero-memory process")
    func rawNonResidentMemoryZeroForZeroProcess() {
        let p = makeSnapshot(pid: 1, footprint: 0, resident: 0)
        let group = makeGroup(processes: [p])
        #expect(group.rawNonResidentMemory == 0)
    }

    // MARK: - processCount

    @Test("processCount equals direct process count when no subGroups")
    func processCountWithNoSubGroups() {
        let processes = [
            makeSnapshot(pid: 1, footprint: 10 * mb, resident: 8 * mb),
            makeSnapshot(pid: 2, footprint: 20 * mb, resident: 16 * mb),
            makeSnapshot(pid: 3, footprint: 30 * mb, resident: 24 * mb),
        ]
        let group = makeGroup(processes: processes)
        #expect(group.processCount == 3)
    }

    @Test("processCount includes processes in subGroups")
    func processCountIncludesSubGroupProcesses() {
        let mainProcess = makeSnapshot(pid: 1, footprint: 50 * mb, resident: 40 * mb)
        let sub1Process = makeSnapshot(pid: 2, footprint: 20 * mb, resident: 16 * mb)
        let sub2Process = makeSnapshot(pid: 3, footprint: 30 * mb, resident: 24 * mb)

        let sub1 = ProcessGroup(
            stableIdentifier: "test:sub1", name: "Sub1", icon: nil,
            classifierName: "Test", explanation: nil,
            processes: [sub1Process], subGroups: nil,
            deduplicatedFootprint: sub1Process.physFootprint,
            nonResidentMemory: sub1Process.nonResidentMemory
        )
        let sub2 = ProcessGroup(
            stableIdentifier: "test:sub2", name: "Sub2", icon: nil,
            classifierName: "Test", explanation: nil,
            processes: [sub2Process], subGroups: nil,
            deduplicatedFootprint: sub2Process.physFootprint,
            nonResidentMemory: sub2Process.nonResidentMemory
        )

        let group = makeGroup(processes: [mainProcess], subGroups: [sub1, sub2])
        // 1 direct + 1 in sub1 + 1 in sub2 = 3
        #expect(group.processCount == 3)
    }

    @Test("processCount is zero for empty group")
    func processCountZeroForEmpty() {
        let group = makeGroup(processes: [])
        #expect(group.processCount == 0)
    }

    // MARK: - trend and footprintHistory default values

    @Test("trend defaults to unknown on creation")
    func trendDefaultsToUnknown() {
        let p = makeSnapshot(pid: 1, footprint: 10 * mb, resident: 8 * mb)
        let group = makeGroup(processes: [p])
        #expect(group.trend == .unknown)
    }

    @Test("footprintHistory defaults to empty on creation")
    func footprintHistoryDefaultsToEmpty() {
        let p = makeSnapshot(pid: 1, footprint: 10 * mb, resident: 8 * mb)
        let group = makeGroup(processes: [p])
        #expect(group.footprintHistory.isEmpty)
    }

    @Test("trend can be set to all Trend values")
    func trendCanBeSetToAllValues() {
        let p = makeSnapshot(pid: 1, footprint: 10 * mb, resident: 8 * mb)
        var group = makeGroup(processes: [p])
        group.trend = .up
        #expect(group.trend == .up)
        group.trend = .down
        #expect(group.trend == .down)
        group.trend = .stable
        #expect(group.trend == .stable)
        group.trend = .unknown
        #expect(group.trend == .unknown)
    }

    @Test("footprintHistory can be set and read back")
    func footprintHistoryCanBeSetAndRead() {
        let p = makeSnapshot(pid: 1, footprint: 10 * mb, resident: 8 * mb)
        var group = makeGroup(processes: [p])
        let history: [UInt64] = [100, 200, 300, 250, 280]
        group.footprintHistory = history
        #expect(group.footprintHistory == history)
    }

    // MARK: - Trend Codable

    @Test("Trend enum raw values are stable strings")
    func trendRawValues() {
        #expect(Trend.up.rawValue == "up")
        #expect(Trend.down.rawValue == "down")
        #expect(Trend.stable.rawValue == "stable")
        #expect(Trend.unknown.rawValue == "unknown")
    }

    @Test("Trend can be encoded and decoded via JSON")
    func trendCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for trend in [Trend.up, .down, .stable, .unknown] {
            let data = try encoder.encode(trend)
            let decoded = try decoder.decode(Trend.self, from: data)
            #expect(decoded == trend)
        }
    }

    // MARK: - ClassificationResult

    @Test("ClassificationResult.empty has no groups and no claimedPIDs")
    func classificationResultEmpty() {
        let result = ClassificationResult.empty
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }
}
