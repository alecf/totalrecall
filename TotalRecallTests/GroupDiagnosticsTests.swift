import Foundation
import Testing
@testable import TotalRecallCore

@Suite("Group Diagnostics")
struct GroupDiagnosticsTests {
    private func snapshot(pid: Int32, name: String = "proc", args: [String] = [], footprint: UInt64 = 10 * 1024 * 1024) -> ProcessSnapshot {
        let now = Date()
        return ProcessSnapshot(
            pid: pid,
            name: name,
            path: "",
            commandLineArgs: args,
            parentPid: 1,
            responsiblePid: pid,
            bundleIdentifier: nil,
            workingDirectory: nil,
            physFootprint: footprint,
            residentSize: footprint,
            sharedMemory: 0,
            startTimeSec: 0,
            startTimeUsec: 0,
            firstSeen: now,
            lastSeen: now,
            exitedAt: nil,
            isPartialData: false
        )
    }

    @Test("Header reports process and group counts")
    func headerReportsCounts() {
        let group = ProcessGroup(
            stableIdentifier: "g1", name: "App", icon: nil, classifierName: "Generic",
            explanation: nil, processes: [snapshot(pid: 1)], subGroups: nil,
            deduplicatedFootprint: 10 * 1024 * 1024, nonResidentMemory: 0
        )
        let output = GroupDiagnostics.diagnose(groups: [group], systemMemory: .empty, totalProcesses: 1)

        #expect(output.description.contains("Processes: 1 total across 1 groups"))
        #expect(output.description.contains("[Generic] App"))
        #expect(output.description.contains("(1 procs, NO ICON)"))
    }

    @Test("Lists more than 8 direct processes with a remainder count")
    func truncatesDirectProcessesAfterEight() {
        let processes = (1...10).map { snapshot(pid: Int32($0), name: "proc\($0)") }
        let group = ProcessGroup(
            stableIdentifier: "g1", name: "App", icon: nil, classifierName: "Generic",
            explanation: nil, processes: processes, subGroups: nil,
            deduplicatedFootprint: 100 * 1024 * 1024, nonResidentMemory: 0
        )
        let output = GroupDiagnostics.diagnose(groups: [group], systemMemory: .empty, totalProcesses: 10)

        #expect(output.description.contains("... +2 more"))
        #expect(output.description.contains("PID 1 proc1"))
        #expect(!output.description.contains("PID 9 proc9"))
    }

    @Test("Lists sub-groups and truncates after 5 sub-group processes")
    func truncatesSubGroupProcessesAfterFive() {
        let subProcesses = (1...6).map { snapshot(pid: Int32($0), name: "sub\($0)") }
        let subGroup = ProcessGroup(
            stableIdentifier: "g1:sub", name: "Sub", icon: nil, classifierName: "Generic",
            explanation: nil, processes: subProcesses, subGroups: nil,
            deduplicatedFootprint: 60 * 1024 * 1024, nonResidentMemory: 0
        )
        let group = ProcessGroup(
            stableIdentifier: "g1", name: "App", icon: nil, classifierName: "Generic",
            explanation: nil, processes: [], subGroups: [subGroup],
            deduplicatedFootprint: 60 * 1024 * 1024, nonResidentMemory: 0
        )
        let output = GroupDiagnostics.diagnose(groups: [group], systemMemory: .empty, totalProcesses: 6)

        #expect(output.description.contains("├─ Sub"))
        #expect(output.description.contains("... +1 more"))
        #expect(output.description.contains("PID 1 sub1"))
        #expect(!output.description.contains("PID 6 sub6"))
    }

    @Test("Truncates command-line args longer than 120 characters")
    func truncatesLongArgs() {
        let longArg = String(repeating: "x", count: 200)
        let process = snapshot(pid: 1, name: "proc", args: [longArg])
        let group = ProcessGroup(
            stableIdentifier: "g1", name: "App", icon: nil, classifierName: "Generic",
            explanation: nil, processes: [process], subGroups: nil,
            deduplicatedFootprint: 10 * 1024 * 1024, nonResidentMemory: 0
        )
        let output = GroupDiagnostics.diagnose(groups: [group], systemMemory: .empty, totalProcesses: 1)

        #expect(output.description.contains(String(repeating: "x", count: 120) + "..."))
        #expect(!output.description.contains(String(repeating: "x", count: 121)))
    }
}
