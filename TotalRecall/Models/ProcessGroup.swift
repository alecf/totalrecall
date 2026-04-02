import AppKit

public enum Trend: String, Codable, Sendable {
    case up
    case stable
    case down
    case unknown  // First snapshot, no history yet
}

/// A logical group of processes representing an application or system function.
public struct ProcessGroup: Identifiable, Sendable {
    /// Stable across snapshots even as processes join/leave.
    /// Constructed by the classifier (e.g., "chrome:Profile 1", "system:WindowServer").
    public let stableIdentifier: String

    public var id: String { stableIdentifier }

    public let name: String
    public let icon: NSImage?
    public let classifierName: String
    public let explanation: String?

    public var processes: [ProcessSnapshot]
    public var subGroups: [ProcessGroup]?

    /// Sum of physFootprint minus RSHRD heuristic deduplication.
    public var deduplicatedFootprint: UInt64

    /// Sum of non-resident memory across all processes.
    public var nonResidentMemory: UInt64

    /// Set by AppState after comparing with historical data — not computed by ProcessGroup.
    public var trend: Trend = .unknown

    public init(stableIdentifier: String, name: String, icon: NSImage?, classifierName: String,
                explanation: String?, processes: [ProcessSnapshot], subGroups: [ProcessGroup]?,
                deduplicatedFootprint: UInt64, nonResidentMemory: UInt64, trend: Trend = .unknown) {
        self.stableIdentifier = stableIdentifier
        self.name = name
        self.icon = icon
        self.classifierName = classifierName
        self.explanation = explanation
        self.processes = processes
        self.subGroups = subGroups
        self.deduplicatedFootprint = deduplicatedFootprint
        self.nonResidentMemory = nonResidentMemory
        self.trend = trend
    }

    public var totalFootprint: UInt64 {
        processes.reduce(0) { $0 + $1.physFootprint }
    }

    public var processCount: Int {
        processes.count + (subGroups?.reduce(0) { $0 + $1.processCount } ?? 0)
    }

    /// Compute deduplicated footprint using the RSHRD subtraction heuristic.
    /// Count shared memory once (from the largest process), subtract RSHRD from the rest.
    public static func computeDeduplicatedFootprint(for processes: [ProcessSnapshot]) -> UInt64 {
        guard !processes.isEmpty else { return 0 }

        let sorted = processes.sorted { $0.physFootprint > $1.physFootprint }
        var total = sorted[0].physFootprint  // Largest keeps its full footprint

        for process in sorted.dropFirst() {
            let deduped = process.physFootprint > process.sharedMemory
                ? process.physFootprint - process.sharedMemory
                : process.physFootprint
            total += deduped
        }

        return total
    }
}
