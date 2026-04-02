import AppKit

enum Trend: String, Codable, Sendable {
    case up
    case stable
    case down
    case unknown  // First snapshot, no history yet
}

/// A logical group of processes representing an application or system function.
struct ProcessGroup: Identifiable, Sendable {
    /// Stable across snapshots even as processes join/leave.
    /// Constructed by the classifier (e.g., "chrome:Profile 1", "system:WindowServer").
    let stableIdentifier: String

    var id: String { stableIdentifier }

    let name: String
    let icon: NSImage?
    let classifierName: String
    let explanation: String?

    var processes: [ProcessSnapshot]
    var subGroups: [ProcessGroup]?

    /// Sum of physFootprint minus RSHRD heuristic deduplication.
    var deduplicatedFootprint: UInt64

    /// Sum of non-resident memory across all processes.
    var nonResidentMemory: UInt64

    /// Set by AppState after comparing with historical data — not computed by ProcessGroup.
    var trend: Trend = .unknown

    var totalFootprint: UInt64 {
        processes.reduce(0) { $0 + $1.physFootprint }
    }

    var processCount: Int {
        processes.count + (subGroups?.reduce(0) { $0 + $1.processCount } ?? 0)
    }

    /// Compute deduplicated footprint using the RSHRD subtraction heuristic.
    /// Count shared memory once (from the largest process), subtract RSHRD from the rest.
    static func computeDeduplicatedFootprint(for processes: [ProcessSnapshot]) -> UInt64 {
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
