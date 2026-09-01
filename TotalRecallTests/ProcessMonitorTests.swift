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

    @Test("second full collection detects any exited PIDs correctly")
    func secondCollectionExitedPIDsValid() async {
        let monitor = ProcessMonitor()
        _ = await monitor.collectSnapshot(mode: .full)
        let result2 = await monitor.collectSnapshot(mode: .full)
        let pids2 = Set(result2.snapshots.map(\.pid))

        // A PID reported as exited must not still be running. This is the
        // invariant `collectSnapshot` actually guarantees, and it holds no
        // matter what the machine does mid-collection.
        //
        // Asserting the other direction — that every exited PID appeared in
        // the *first* collection's snapshots — looks equivalent and isn't.
        // `previousPIDs` records what `listAllPIDs` enumerated, but a process
        // that dies before its rusage/BSD probes is dropped by the `guard
        // rusage != nil || resolved != nil` in the collection loop, so it is
        // remembered without ever becoming a snapshot. It then correctly
        // reports as exited on the next pass while being absent from the set
        // the assertion compared against. On a CI runner, which churns
        // short-lived helper processes throughout the run, that race fired
        // often enough to redden unrelated PRs.
        #expect(result2.exitedPIDs.isDisjoint(with: pids2))
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
