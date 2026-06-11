import TotalRecallCore
import SwiftUI
import AppKit
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

    /// When true, multiple instances of the same app
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

    /// Groups sorted by the metric used by the memory river.
    /// The river represents resident memory, so its visual order should not
    /// drift when the table is sorted by total footprint.
    var memoryRiverGroups: [ProcessGroup] {
        groups.sorted {
            if $0.residentMemory == $1.residentMemory {
                return $0.deduplicatedFootprint > $1.deduplicatedFootprint
            }
            return $0.residentMemory > $1.residentMemory
        }
    }

    /// Sort key for a group based on current sort mode.
    func sortValue(_ group: ProcessGroup) -> UInt64 {
        if sortByResident {
            return group.residentMemory
        } else {
            return group.deduplicatedFootprint
        }
    }

    /// Sort key for a process based on current sort mode.
    func processSortValue(_ process: ProcessSnapshot) -> UInt64 {
        sortByResident ? process.residentSize : process.physFootprint
    }

    var topConsumer: ProcessGroup? {
        groups.first  // Already sorted by memory
    }

    var menuBarLabel: String {
        MemoryFormatter.formatUsedTotal(used: systemMemory.used, total: systemMemory.totalPhysical)
    }

    // MARK: - Lifecycle

    init() {
        // Start scanning at app launch so the menu bar shows real values
        // immediately — not after the inspection window is first opened.
        // The two-tier refresh strategy keeps cost low while the window
        // is hidden: full classification every 5s when visible, system
        // memory totals only every 60s when hidden.
        startPolling()

        // Persist window-open state on app termination so the next launch
        // can decide whether to reopen the inspection window. Persisting
        // only at terminate (rather than on every visibility change)
        // avoids a willClose-on-quit cascade clearing the flag right
        // before we read it.
        //
        // Skip in screenshot mode — its brief auto-opened window
        // shouldn't influence the next normal launch.
        if !ScreenshotMode.isActive {
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    WindowPersistence.wasOpenOnQuit = self.isInspectionWindowVisible
                }
            }
        }
    }

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
            classified = InstanceMerger.mergeInstances(classified)
        } else {
            classified = InstanceMerger.labelSeparateInstances(classified)
        }

        // Compute trends
        for i in classified.indices {
            let history = trendHistory[classified[i].stableIdentifier, default: []]
            classified[i].trend = TrendCalculator.computeTrend(
                currentFootprint: classified[i].deduplicatedFootprint,
                history: history,
                windowSize: trendWindowSize
            )

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
