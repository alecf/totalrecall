import Foundation

/// Runs classifiers in order, passing unclaimed processes to each.
/// Owns the classifier chain and computes RSHRD deduplication.
struct ClassifierRegistry: Sendable {
    /// Classifiers in priority order. Each sees only unclaimed processes.
    let classifiers: [any ProcessClassifier]

    /// Default registry with all MVP classifiers in priority order.
    static let `default` = ClassifierRegistry(classifiers: [
        ChromeClassifier(),
        ElectronClassifier(),
        SystemServicesClassifier(),
        GenericClassifier(),  // Always last — catches everything remaining
    ])

    /// Classify all process snapshots into groups.
    func classify(snapshots: [ProcessSnapshot]) -> [ProcessGroup] {
        var remainingProcesses = snapshots
        var allGroups: [ProcessGroup] = []

        for classifier in classifiers {
            guard !remainingProcesses.isEmpty else { break }

            let result = classifier.classify(remainingProcesses)

            // Remove claimed PIDs from remaining
            if !result.claimedPIDs.isEmpty {
                remainingProcesses.removeAll { result.claimedPIDs.contains($0.pid) }
            }

            allGroups.append(contentsOf: result.groups)
        }

        // Assert subGroups depth <= 2 (prevent accidental infinite recursion)
        for group in allGroups {
            assertSubGroupDepth(group, currentDepth: 0, maxDepth: 2)
        }

        // Sort by memory (largest first)
        return allGroups.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }
    }

    private func assertSubGroupDepth(_ group: ProcessGroup, currentDepth: Int, maxDepth: Int) {
        assert(currentDepth <= maxDepth,
               "ProcessGroup '\(group.name)' exceeds max subGroup depth of \(maxDepth)")
        if let subGroups = group.subGroups {
            for sub in subGroups {
                assertSubGroupDepth(sub, currentDepth: currentDepth + 1, maxDepth: maxDepth)
            }
        }
    }
}
