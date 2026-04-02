import Foundation

/// Result of a classifier's work: the groups it formed and the PIDs it consumed.
struct ClassificationResult: Sendable {
    let groups: [ProcessGroup]
    let claimedPIDs: Set<pid_t>

    static let empty = ClassificationResult(groups: [], claimedPIDs: [])
}

/// A strategy for identifying and grouping related processes.
/// Each classifier receives the full list of unclaimed processes and
/// returns the groups it can form from them.
protocol ProcessClassifier: Sendable {
    var name: String { get }

    /// Classify unclaimed processes into groups.
    /// The registry calls classifiers in order; each sees only processes
    /// not yet claimed by a higher-priority classifier.
    func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult
}
