import Foundation

/// Merges per-instance `ProcessGroup`s into a single app-level group, or labels
/// them when the user chooses to view instances separately.
///
/// Classifiers key multi-instance apps as `"<app>:<pid>"` (e.g. "tool:27527").
/// `appKey(from:)` strips the trailing PID so all instances of the same app
/// can be found and either merged into sub-groups or individually labeled.
public enum InstanceMerger {
    /// Merge groups that share the same app identity into a single group.
    /// e.g., "tool:1234" + "tool:5678" → "tool" with per-instance sub-groups.
    public static func mergeInstances(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        var byAppKey: [String: [ProcessGroup]] = [:]

        for group in groups {
            let key = appKey(from: group.stableIdentifier)
            byAppKey[key, default: []].append(group)
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

    /// Add visible labels for PID-keyed app instances when the user chooses
    /// to view separate app instances rather than a merged group.
    public static func labelSeparateInstances(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        let byAppKey = Dictionary(grouping: groups, by: { appKey(from: $0.stableIdentifier) })
        let labeled = byAppKey.values.flatMap { instanceGroups in
            instanceGroups.enumerated().map { (index, instance) in
                let shouldNumber = instanceGroups.count > 1
                return renamedInstance(instance, index: index, shouldNumber: shouldNumber)
            }
        }
        return labeled.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }
    }

    /// Extract the app-level key from a stableIdentifier.
    /// "tool:27527" → "tool", "chrome:Default" → "chrome:Default", "generic:app:/Applications/Foo.app" → unchanged
    static func appKey(from id: String) -> String {
        // For classifiers that use "name:PID" format, strip the PID
        // But keep meaningful non-PID sub-keys.
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
    private static func mergeGroups(_ instances: [ProcessGroup]) -> ProcessGroup {
        let allProcesses = uniqueProcesses(in: instances)
        let allSubGroups: [ProcessGroup]

        // If instances already have sub-groups, flatten them.
        // Otherwise, each instance becomes a sub-group
        if instances.allSatisfy({ $0.subGroups == nil || $0.subGroups!.isEmpty }) {
            // Each instance becomes a named sub-group
            allSubGroups = instances.enumerated().map { (i, instance) in
                renamedInstance(instance, index: i, shouldNumber: instances.count > 1)
            }
        } else {
            // Flatten sub-groups from all instances
            allSubGroups = instances.flatMap { $0.subGroups ?? [$0] }
        }

        let first = instances[0]
        return ProcessGroup(
            stableIdentifier: appKey(from: first.stableIdentifier),
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

    private static func renamedInstance(_ instance: ProcessGroup, index: Int, shouldNumber: Bool) -> ProcessGroup {
        var displayName = shouldNumber ? "\(instance.name) #\(index + 1)" : instance.name
        if let context = instanceContext(for: instance) {
            displayName += " - \(context)"
        }

        return ProcessGroup(
            stableIdentifier: instance.stableIdentifier,
            name: displayName,
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

    private static func uniqueProcesses(in groups: [ProcessGroup]) -> [ProcessSnapshot] {
        var seen = Set<Int32>()
        var result: [ProcessSnapshot] = []

        for group in groups {
            for process in group.uniqueProcesses where seen.insert(process.pid).inserted {
                result.append(process)
            }
        }

        return result
    }

    private static func instanceContext(for group: ProcessGroup) -> String? {
        guard appKey(from: group.stableIdentifier) != group.stableIdentifier else { return nil }
        return group.explanation
    }
}
