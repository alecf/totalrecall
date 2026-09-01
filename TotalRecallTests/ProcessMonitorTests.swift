import Testing
import Foundation
@testable import TotalRecallCore

@Suite("ProcessMonitor")
struct ProcessMonitorTests {

    // MARK: - Initial State

    @Test("cacheSize starts at zero")
    func cacheSizeStartsAtZero() async {
        let monitor = ProcessMonitor()
        let count = await monitor.cacheSize
        #expect(count == 0)
    }

    @Test("getIcon returns nil for any PID before collection")
    func getIconNilBeforeCollection() async {
        let monitor = ProcessMonitor()
        let icon = await monitor.getIcon(for: ProcessInfo.processInfo.processIdentifier)
        _ = icon  // May be nil before any collection
    }

    // MARK: - menuBarOnly Mode

    @Test("menuBarOnly mode returns empty snapshots")
    func menuBarOnlyReturnsEmptySnapshots() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .menuBarOnly)
        #expect(result.snapshots.isEmpty)
    }

    @Test("menuBarOnly mode returns valid system memory")
    func menuBarOnlyReturnsSystemMemory() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .menuBarOnly)
        #expect(result.systemMemory.totalPhysical > 0)
    }

    @Test("menuBarOnly mode returns empty exited PIDs")
    func menuBarOnlyReturnsEmptyExitedPIDs() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .menuBarOnly)
        #expect(result.exitedPIDs.isEmpty)
    }

    @Test("cacheSize stays zero after menuBarOnly collection")
    func cacheSizeZeroAfterMenuBarOnlyCollection() async {
        let monitor = ProcessMonitor()
        _ = await monitor.collectSnapshot(mode: .menuBarOnly)
        let count = await monitor.cacheSize
        #expect(count == 0)
    }

    // MARK: - Full Mode

    @Test("full mode returns non-empty snapshots")
    func fullModeReturnsSnapshots() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .full)
        #expect(!result.snapshots.isEmpty)
    }

    @Test("full mode includes the current process")
    func fullModeIncludesCurrentProcess() async {
        let monitor = ProcessMonitor()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let result = await monitor.collectSnapshot(mode: .full)
        #expect(result.snapshots.contains { $0.pid == currentPID })
    }

    @Test("full mode returns valid system memory")
    func fullModeReturnsSystemMemory() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .full)
        #expect(result.systemMemory.totalPhysical > 0)
    }

    @Test("cacheSize grows after full collection")
    func cacheSizeGrowsAfterFullCollection() async {
        let monitor = ProcessMonitor()
        _ = await monitor.collectSnapshot(mode: .full)
        let count = await monitor.cacheSize
        #expect(count > 0)
    }

    @Test("full mode snapshots have non-empty names")
    func fullModeSnapshotsHaveNames() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .full)
        let allHaveNames = result.snapshots.allSatisfy { !$0.name.isEmpty }
        #expect(allHaveNames)
    }

    @Test("full mode snapshots have positive PIDs")
    func fullModeSnapshotsHavePositivePIDs() async {
        let monitor = ProcessMonitor()
        let result = await monitor.collectSnapshot(mode: .full)
        let allPositive = result.snapshots.allSatisfy { $0.pid >= 0 }
        #expect(allPositive)
    }

    // MARK: - Two Collections (Cache Hit Path)

    @Test("second full collection uses cached data for stable PIDs")
    func secondCollectionUsesCachedData() async {
        let monitor = ProcessMonitor()
        let result1 = await monitor.collectSnapshot(mode: .full)
        let result2 = await monitor.collectSnapshot(mode: .full)

        // Both collections should include the current process
        let currentPID = ProcessInfo.processInfo.processIdentifier
        #expect(result1.snapshots.contains { $0.pid == currentPID })
        #expect(result2.snapshots.contains { $0.pid == currentPID })
    }

    @Test("a process that exits between collections is reported as exited")
    func exitedProcessIsDetected() async throws {
        // This has to cause an exit rather than reason about the two result
        // sets, because every relation between them is true by construction:
        // `exitedPIDs` is `previousPIDs - currentPIDSet` and `snapshots` is
        // built by walking `currentPIDSet`, so the two are disjoint whether or
        // not exit detection works at all.
        //
        // The assertion this replaced compared `exitedPIDs` against the first
        // collection's *snapshots*, which is neither tautological nor true:
        // `previousPIDs` records what `listAllPIDs` enumerated, and a process
        // that dies before its rusage and BSD probes is dropped by the `guard
        // rusage != nil || resolved != nil` in the collection loop — remembered
        // without ever becoming a snapshot, then correctly reported as exited on
        // the next pass while absent from the set being compared against. A CI
        // runner churns short-lived helpers throughout a run, so that race hit
        // often enough to redden unrelated PRs.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        let childPID = child.processIdentifier

        let monitor = ProcessMonitor()
        let first = await monitor.collectSnapshot(mode: .full)
        #expect(first.snapshots.contains { $0.pid == childPID })

        // `waitUntilExit` returns only after the child is reaped, so it is gone
        // from `listAllPIDs` by the time the second collection enumerates.
        child.terminate()
        child.waitUntilExit()

        let second = await monitor.collectSnapshot(mode: .full)
        #expect(second.exitedPIDs.contains(childPID))
        #expect(!second.snapshots.contains { $0.pid == childPID })
    }

    @Test("getIcon for current process returns nil or image after collection")
    func getIconAfterCollection() async {
        let monitor = ProcessMonitor()
        _ = await monitor.collectSnapshot(mode: .full)
        let icon = await monitor.getIcon(for: ProcessInfo.processInfo.processIdentifier)
        _ = icon  // May be nil or an image
    }

    @Test("getIcon returns nil for unknown PID after collection")
    func getIconNilForUnknownPIDAfterCollection() async {
        let monitor = ProcessMonitor()
        _ = await monitor.collectSnapshot(mode: .full)
        let icon = await monitor.getIcon(for: 0)
        #expect(icon == nil)
    }
}
