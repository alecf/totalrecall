import Foundation
import AppKit

/// Background actor that polls process data using a tiered collection strategy.
/// Owns the PID cache and the ClassifierRegistry (all CPU work stays off @MainActor).
public actor ProcessMonitor {
    /// Cached per-PID data that doesn't change during a process's lifetime.
    public struct CachedProcessInfo: Sendable {
        let path: String
        let commandLineArgs: [String]
        let bsdInfo: SystemProbe.BSDInfo
        let bundleIdentifier: String?
        let workingDirectory: String?
        let icon: NSImage?
    }

    private var pidCache: [pid_t: CachedProcessInfo] = [:]
    private var previousPIDs: Set<pid_t> = []
    private var proportionalShares = ProportionalShareCache()

    /// CPU time per full refresh spent walking VM maps for proportional shares —
    /// 100 ms every 5 s is 2% of a core.
    static let proportionalShareBudget: TimeInterval = 0.1
    /// Budget until every process has been measured once, so the bar has real
    /// shares for the big groups within the first refresh or two.
    static let proportionalShareWarmupBudget: TimeInterval = 0.5
    /// Processes younger than this aren't walked: short-lived build steps
    /// would cost a walk each and exit before it mattered.
    static let proportionalShareCooloff: TimeInterval = 15

    public init() {}

    public enum RefreshMode: Sendable {
        case full           // All tiers — when inspection window is visible
        case menuBarOnly    // System-wide stats only — when window is hidden
    }

    // MARK: - Collection

    /// Perform a full data collection cycle.
    /// Returns raw snapshots + system memory + exited PIDs.
    public func collectSnapshot(mode: RefreshMode = .full) -> (snapshots: [ProcessSnapshot], systemMemory: SystemMemoryInfo, exitedPIDs: Set<pid_t>) {
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
            // For root-owned processes (e.g. `login`) rusage may fail; include them
            // with zero memory so the parent-child tree stays intact.
            let rusage = SystemProbe.getRusage(pid: pid)

            // Tier 2+3: Identity data (cached per PID)
            let cached = getCachedInfo(pid: pid)

            // Verify PID hasn't been recycled (check start time)
            // Resolve cached or fresh process info
            let resolved: CachedProcessInfo?
            if let cached = cached {
                if let freshBSD = SystemProbe.getBSDInfo(pid: pid),
                   freshBSD.startTimeSec == cached.bsdInfo.startTimeSec &&
                   freshBSD.startTimeUsec == cached.bsdInfo.startTimeUsec {
                    resolved = cached
                } else {
                    pidCache.removeValue(forKey: pid)
                    resolved = queryAndCache(pid: pid)
                }
            } else {
                resolved = queryAndCache(pid: pid)
            }

            // Skip processes where we couldn't get any info at all (truly gone)
            guard rusage != nil || resolved != nil else { continue }

            let sharedMemory = SystemProbe.getTaskInfo(pid: pid)?.residentSize ?? 0

            let snapshot = ProcessSnapshot(
                pid: pid,
                name: resolved?.bsdInfo.name ?? "unknown",
                path: resolved?.path ?? "",
                commandLineArgs: resolved?.commandLineArgs ?? [],
                parentPid: resolved?.bsdInfo.parentPid ?? 1,
                responsiblePid: resolved?.bsdInfo.responsiblePid ?? 1,
                bundleIdentifier: resolved?.bundleIdentifier,
                workingDirectory: resolved?.workingDirectory,
                physFootprint: rusage?.physFootprint ?? 0,
                residentSize: rusage?.residentSize ?? 0,
                sharedMemory: sharedMemory,
                startTimeSec: resolved?.bsdInfo.startTimeSec ?? 0,
                startTimeUsec: resolved?.bsdInfo.startTimeUsec ?? 0,
                firstSeen: now,
                lastSeen: now,
                exitedAt: nil,
                isPartialData: resolved == nil
            )
            snapshots.append(snapshot)
        }

        previousPIDs = currentPIDSet
        snapshots = applyProportionalShares(to: snapshots, now: now)
        return (snapshots: snapshots, systemMemory: systemMemory, exitedPIDs: exitedPIDs)
    }

    // MARK: - Proportional Shares

    /// Walk a budgeted slice of processes, then fill in every snapshot's
    /// `proportionalResidentSize` from the cache.
    private func applyProportionalShares(to snapshots: [ProcessSnapshot], now: Date) -> [ProcessSnapshot] {
        let candidates = snapshots.map {
            ProportionalShareCache.Candidate(pid: $0.pid, startTime: Self.startDate($0), residentSize: $0.residentSize)
        }
        proportionalShares.retain(candidates)

        let byPID = Dictionary(candidates.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let order = proportionalShares.walkOrder(candidates, now: now, cooloff: Self.proportionalShareCooloff)
        let budget = proportionalShares.isWarm ? Self.proportionalShareBudget : Self.proportionalShareWarmupBudget
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(Int(budget * 1000))
        for pid in order {
            guard clock.now < deadline, let candidate = byPID[pid] else { break }
            proportionalShares.record(
                pid: pid,
                startTime: candidate.startTime,
                walk: SystemProbe.walkResidentPages(pid: pid),
                residentSize: candidate.residentSize,
                now: now
            )
        }

        let shares = proportionalShares.shares()
        return snapshots.map { snapshot in
            var updated = snapshot
            updated.proportionalResidentSize = shares.proportionalResident(
                pid: snapshot.pid,
                startTime: Self.startDate(snapshot),
                residentSize: snapshot.residentSize
            )
            return updated
        }
    }

    private static func startDate(_ snapshot: ProcessSnapshot) -> Date {
        Date(timeIntervalSince1970: Double(snapshot.startTimeSec) + Double(snapshot.startTimeUsec) / 1_000_000)
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
        let workingDir = SystemProbe.getWorkingDirectory(pid: pid)
        let icon = SystemProbe.getAppIcon(pid: pid)

        let cached = CachedProcessInfo(
            path: path,
            commandLineArgs: args,
            bsdInfo: bsdInfo,
            bundleIdentifier: bundleId,
            workingDirectory: workingDir,
            icon: icon
        )
        pidCache[pid] = cached
        return cached
    }

    /// Get cached icon for a PID (used by UI layer).
    public func getIcon(for pid: pid_t) -> NSImage? {
        pidCache[pid]?.icon
    }

    /// Number of cached entries (for diagnostics).
    public var cacheSize: Int { pidCache.count }
}
