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
        let classified = registry.classify(snapshots: result.snapshots)

        // Compute trends
        for var group in classified {
            let history = trendHistory[group.stableIdentifier, default: []]
            group.trend = computeTrend(currentFootprint: group.deduplicatedFootprint, history: history)

            // Update history ring buffer
            var updated = history
            updated.append(group.deduplicatedFootprint)
            if updated.count > trendWindowSize {
                updated.removeFirst(updated.count - trendWindowSize)
            }
            trendHistory[group.stableIdentifier] = updated
        }

        groups = classified

        // Handle exited process retention
        handleExitedProcesses(exitedPIDs: result.exitedPIDs)

        // Clean stale trend history for groups that no longer exist
        let currentIdentifiers = Set(classified.map(\.stableIdentifier))
        trendHistory = trendHistory.filter { currentIdentifiers.contains($0.key) }
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
