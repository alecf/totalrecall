import Foundation
import AppKit

/// Background actor that polls process data using a tiered collection strategy.
/// Owns the PID cache and the ClassifierRegistry (all CPU work stays off @MainActor).
actor ProcessMonitor {
    /// Cached per-PID data that doesn't change during a process's lifetime.
    struct CachedProcessInfo: Sendable {
        let path: String
        let commandLineArgs: [String]
        let bsdInfo: SystemProbe.BSDInfo
        let bundleIdentifier: String?
        let icon: NSImage?
    }

    private var pidCache: [pid_t: CachedProcessInfo] = [:]
    private var previousPIDs: Set<pid_t> = []

    enum RefreshMode {
        case full           // All tiers — when inspection window is visible
        case menuBarOnly    // System-wide stats only — when window is hidden
    }

    // MARK: - Collection

    /// Perform a full data collection cycle.
    /// Returns raw snapshots + system memory + exited PIDs.
    func collectSnapshot(mode: RefreshMode = .full) -> (snapshots: [ProcessSnapshot], systemMemory: SystemMemoryInfo, exitedPIDs: Set<pid_t>) {
        let systemMemory = SystemProbe.getSystemMemory()

        guard mode == .full else {
            return (snapshots: [], systemMemory: systemMemory, exitedPIDs: [])
        }

        let now = Date()

        // Tier 0: Enumerate all PIDs
        let pids = SystemProbe.listAllPIDs()
        let currentPIDSet = Set(pids)

        // Detect exited processes
        let exitedPIDs = previousPIDs.subtracting(currentPIDSet)

        // Evict cache entries for exited PIDs
        for pid in exitedPIDs {
            pidCache.removeValue(forKey: pid)
        }

        // Tier 1 + 2 + 3: Collect per-process data
        var snapshots: [ProcessSnapshot] = []
        snapshots.reserveCapacity(pids.count)

        for pid in pids {
            // Tier 1: Memory (always fresh — cheap at ~3μs/pid)
            guard let rusage = SystemProbe.getRusage(pid: pid) else {
                continue  // Process died between listAllPIDs and getRusage
            }

            // Tier 2+3: Identity data (cached per PID)
            let cached = getCachedInfo(pid: pid)

            // Verify PID hasn't been recycled (check start time)
            let isPartial: Bool
            let name: String
            let path: String
            let args: [String]
            let parentPid: Int32
            let responsiblePid: Int32
            let bundleId: String?
            let startSec: UInt64
            let startUsec: UInt64

            if let cached = cached {
                // Verify start time matches to detect PID reuse
                if let freshBSD = SystemProbe.getBSDInfo(pid: pid),
                   freshBSD.startTimeSec == cached.bsdInfo.startTimeSec &&
                   freshBSD.startTimeUsec == cached.bsdInfo.startTimeUsec {
                    name = cached.bsdInfo.name
                    path = cached.path
                    args = cached.commandLineArgs
                    parentPid = cached.bsdInfo.parentPid
                    responsiblePid = cached.bsdInfo.responsiblePid
                    bundleId = cached.bundleIdentifier
                    startSec = cached.bsdInfo.startTimeSec
                    startUsec = cached.bsdInfo.startTimeUsec
                    isPartial = false
                } else {
                    // PID was recycled — evict and re-query
                    pidCache.removeValue(forKey: pid)
                    let fresh = queryAndCache(pid: pid)
                    name = fresh?.bsdInfo.name ?? "unknown"
                    path = fresh?.path ?? ""
                    args = fresh?.commandLineArgs ?? []
                    parentPid = fresh?.bsdInfo.parentPid ?? 1
                    responsiblePid = fresh?.bsdInfo.responsiblePid ?? 1
                    bundleId = fresh?.bundleIdentifier
                    startSec = fresh?.bsdInfo.startTimeSec ?? 0
                    startUsec = fresh?.bsdInfo.startTimeUsec ?? 0
                    isPartial = fresh == nil
                }
            } else {
                // New PID — query all tiers and cache
                let fresh = queryAndCache(pid: pid)
                name = fresh?.bsdInfo.name ?? "unknown"
                path = fresh?.path ?? ""
                args = fresh?.commandLineArgs ?? []
                parentPid = fresh?.bsdInfo.parentPid ?? 1
                responsiblePid = fresh?.bsdInfo.responsiblePid ?? 1
                bundleId = fresh?.bundleIdentifier
                startSec = fresh?.bsdInfo.startTimeSec ?? 0
                startUsec = fresh?.bsdInfo.startTimeUsec ?? 0
                isPartial = fresh == nil
            }

            // Get shared memory from task info (best-effort)
            let sharedMemory = SystemProbe.getTaskInfo(pid: pid)?.residentSize ?? 0

            let snapshot = ProcessSnapshot(
                pid: pid,
                name: name,
                path: path,
                commandLineArgs: args,
                parentPid: parentPid,
                responsiblePid: responsiblePid,
                bundleIdentifier: bundleId,
                physFootprint: rusage.physFootprint,
                residentSize: rusage.residentSize,
                sharedMemory: sharedMemory,
                startTimeSec: startSec,
                startTimeUsec: startUsec,
                firstSeen: now,
                lastSeen: now,
                exitedAt: nil,
                isPartialData: isPartial
            )
            snapshots.append(snapshot)
        }

        previousPIDs = currentPIDSet
        return (snapshots: snapshots, systemMemory: systemMemory, exitedPIDs: exitedPIDs)
    }

    // MARK: - Cache Management

    private func getCachedInfo(pid: pid_t) -> CachedProcessInfo? {
        pidCache[pid]
    }

    @discardableResult
    private func queryAndCache(pid: pid_t) -> CachedProcessInfo? {
        guard let bsdInfo = SystemProbe.getBSDInfo(pid: pid) else { return nil }

        let path = SystemProbe.getProcessPath(pid: pid) ?? ""
        let args = SystemProbe.getCommandLineArgs(pid: pid) ?? []
        let bundleId = SystemProbe.getBundleIdentifier(pid: pid)
        let icon = SystemProbe.getAppIcon(pid: pid)

        let cached = CachedProcessInfo(
            path: path,
            commandLineArgs: args,
            bsdInfo: bsdInfo,
            bundleIdentifier: bundleId,
            icon: icon
        )
        pidCache[pid] = cached
        return cached
    }

    /// Get cached icon for a PID (used by UI layer).
    func getIcon(for pid: pid_t) -> NSImage? {
        pidCache[pid]?.icon
    }

    /// Number of cached entries (for diagnostics).
    var cacheSize: Int { pidCache.count }
}
