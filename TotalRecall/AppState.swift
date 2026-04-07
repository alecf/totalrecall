import TotalRecallCore
import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    // MARK: - Published State

    var groups: [ProcessGroup] = []
    var systemMemory: SystemMemoryInfo = .empty
    var retainedExited: [ProcessSnapshot] = []
    var selectedGroupID: String?
    var isInspectionWindowVisible = false

    /// When true, multiple instances of the same app (e.g., 3 Claude Code sessions)
    /// are merged into one group. When false, each instance is shown separately.
    var mergeInstances = true

    /// When true, sort by resident memory (actually in RAM). When false, sort by total footprint.
    var sortByResident = false

    /// When true, show subprocesses as a parent-child tree. When false, flat list sorted by size.
    var showTreeView = false

    // MARK: - Configuration

    var refreshInterval: Duration = .seconds(5)
    var backgroundRefreshInterval: Duration = .seconds(60)
    private let retentionDuration: TimeInterval = 60  // Keep exited processes for 60s

    // MARK: - Internal

    private let monitor = ProcessMonitor()
    private let registry = ClassifierRegistry.default
    private var pollingTask: Task<Void, Never>?
    private var trendHistory: [String: [UInt64]] = [:]  // stableIdentifier → last 6 footprints
    private let trendWindowSize = 6

    // MARK: - Computed Properties

    /// Groups sorted by the current sort preference.
    var sortedGroups: [ProcessGroup] {
        groups.sorted { sortValue($0) > sortValue($1) }
    }

    /// Sort key for a group based on current sort mode.
    func sortValue(_ group: ProcessGroup) -> UInt64 {
        if sortByResident {
            let allProcs = collectAllProcesses(from: group)
            return allProcs.reduce(0) { $0 + $1.residentSize }
        } else {
            return group.deduplicatedFootprint
        }
    }

    /// Sort key for a process based on current sort mode.
    func processSortValue(_ process: ProcessSnapshot) -> UInt64 {
        sortByResident ? process.residentSize : process.physFootprint
    }

    private func collectAllProcesses(from group: ProcessGroup) -> [ProcessSnapshot] {
        var all = group.processes
        if let subs = group.subGroups {
            for sub in subs { all.append(contentsOf: collectAllProcesses(from: sub)) }
        }
        return all
    }

    var topConsumer: ProcessGroup? {
        groups.first  // Already sorted by memory
    }

    var menuBarLabel: String {
        MemoryFormatter.formatUsedTotal(used: systemMemory.used, total: systemMemory.totalPhysical)
    }

    // MARK: - Lifecycle

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                let interval = self.isInspectionWindowVisible
                    ? self.refreshInterval
                    : self.backgroundRefreshInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Trigger an immediate full refresh (e.g., when the window opens).
    func refreshNow() {
        Task { await refresh() }
    }

    // MARK: - Refresh

    private func refresh() async {
        let mode: ProcessMonitor.RefreshMode = isInspectionWindowVisible ? .full : .menuBarOnly

        let result = await monitor.collectSnapshot(mode: mode)
        systemMemory = result.systemMemory

        guard mode == .full else { return }

        // Classify processes into groups (runs inside the actor)
        var classified = registry.classify(snapshots: result.snapshots)

        // Optionally merge instances of the same app
        if mergeInstances {
            classified = mergeInstanceGroups(classified)
        }

        // Compute trends
        for i in classified.indices {
            let history = trendHistory[classified[i].stableIdentifier, default: []]
            classified[i].trend = computeTrend(currentFootprint: classified[i].deduplicatedFootprint, history: history)

            var updated = history
            updated.append(classified[i].deduplicatedFootprint)
            if updated.count > trendWindowSize {
                updated.removeFirst(updated.count - trendWindowSize)
            }
            trendHistory[classified[i].stableIdentifier] = updated
        }

        groups = classified

        // Handle exited process retention
        handleExitedProcesses(exitedPIDs: result.exitedPIDs)

        // Clean stale trend history for groups that no longer exist
        let currentIdentifiers = Set(classified.map(\.stableIdentifier))
        trendHistory = trendHistory.filter { currentIdentifiers.contains($0.key) }
    }

    // MARK: - Instance Merging

    /// Merge groups that share the same app identity into a single group.
    /// e.g., "Claude Code (PID 1234)" + "Claude Code (PID 5678)" → "Claude Code" with sub-groups.
    private func mergeInstanceGroups(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        // Extract the "app key" — the part of stableIdentifier before any instance-specific suffix.
        // e.g., "claude:27527" → "claude", "chrome" → "chrome", "app:/Applications/Firefox.app" → "app:/Applications/Firefox.app"
        var byAppKey: [String: [ProcessGroup]] = [:]

        for group in groups {
            let appKey = Self.appKeyFromIdentifier(group.stableIdentifier)
            byAppKey[appKey, default: []].append(group)
        }

        var merged: [ProcessGroup] = []
        for (_, instanceGroups) in byAppKey {
            if instanceGroups.count == 1 {
                merged.append(instanceGroups[0])
            } else {
                merged.append(mergeGroups(instanceGroups))
            }
        }

        return merged.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }
    }

    /// Extract the app-level key from a stableIdentifier.
    /// "claude:27527" → "claude", "chrome:Default" → "chrome", "generic:app:/Applications/Foo.app" → "generic:app:/Applications/Foo.app"
    private static func appKeyFromIdentifier(_ id: String) -> String {
        // For classifiers that use "name:PID" format (ClaudeCode, CLI tools), strip the PID
        // But keep meaningful sub-keys like "chrome:Default" (profile name, not a PID)
        let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return id }

        let prefix = parts[0]
        let suffix = parts[1]

        // If the suffix is purely numeric, it's a PID — strip it for merging
        if suffix.allSatisfy(\.isNumber) {
            return prefix
        }

        return id
    }

    /// Merge multiple instance groups into one, converting instances to sub-groups.
    private func mergeGroups(_ instances: [ProcessGroup]) -> ProcessGroup {
        let allProcesses = instances.flatMap(\.processes)
        let allSubGroups: [ProcessGroup]

        // If instances already have sub-groups (Chrome profiles), flatten them
        // Otherwise, each instance becomes a sub-group
        if instances.allSatisfy({ $0.subGroups == nil || $0.subGroups!.isEmpty }) {
            // Each instance becomes a named sub-group
            allSubGroups = instances.enumerated().map { (i, instance) in
                var sub = instance
                // Give each instance a distinguishing name
                if instances.count > 1 {
                    sub = ProcessGroup(
                        stableIdentifier: instance.stableIdentifier,
                        name: "\(instance.name) #\(i + 1)",
                        icon: instance.icon,
                        classifierName: instance.classifierName,
                        explanation: instance.explanation,
                        processes: instance.processes,
                        subGroups: instance.subGroups,
                        deduplicatedFootprint: instance.deduplicatedFootprint,
                        nonResidentMemory: instance.nonResidentMemory,
                        trend: instance.trend
                    )
                }
                return sub
            }
        } else {
            // Flatten sub-groups from all instances
            allSubGroups = instances.flatMap { $0.subGroups ?? [$0] }
        }

        let first = instances[0]
        return ProcessGroup(
            stableIdentifier: Self.appKeyFromIdentifier(first.stableIdentifier),
            name: first.name,
            icon: first.icon,
            classifierName: first.classifierName,
            explanation: first.explanation,
            processes: [],  // All processes are in sub-groups
            subGroups: allSubGroups,
            deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: allProcesses),
            nonResidentMemory: allProcesses.reduce(0) { $0 + $1.nonResidentMemory }
        )
    }

    // MARK: - Trends

    private func computeTrend(currentFootprint: UInt64, history: [UInt64]) -> Trend {
        guard history.count >= 2 else { return .unknown }

        let recent = history.suffix(trendWindowSize)
        guard let oldest = recent.first else { return .unknown }
        guard oldest > 0 else { return .unknown }

        let changeRatio = Double(currentFootprint) / Double(oldest) - 1.0

        if changeRatio > 0.05 { return .up }
        if changeRatio < -0.05 { return .down }
        return .stable
    }

    // MARK: - Exited Process Retention

    private func handleExitedProcesses(exitedPIDs: Set<pid_t>) {
        let now = Date()

        // Add newly exited processes to retention
        // (In a full implementation, we'd look up the last snapshot for each exited PID)

        // Evict retained processes older than retentionDuration
        retainedExited.removeAll { snapshot in
            guard let exitedAt = snapshot.exitedAt else { return false }
            return now.timeIntervalSince(exitedAt) > retentionDuration
        }
    }

    // MARK: - Window Visibility

    func setWindowVisible(_ visible: Bool) {
        let wasHidden = !isInspectionWindowVisible
        isInspectionWindowVisible = visible

        if visible && wasHidden {
            // Window just opened — trigger immediate full refresh
            refreshNow()
        }
    }
}
