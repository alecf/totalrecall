import Foundation

/// Result of a classifier's work: the groups it formed and the PIDs it consumed.
public struct ClassificationResult: Sendable {
    public let groups: [ProcessGroup]
    public let claimedPIDs: Set<pid_t>

    public static let empty = ClassificationResult(groups: [], claimedPIDs: [])
}

/// A strategy for identifying and grouping related processes.
/// Each classifier receives the full list of unclaimed processes and
/// returns the groups it can form from them.
public protocol ProcessClassifier: Sendable {
    var name: String { get }
    func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult
}
