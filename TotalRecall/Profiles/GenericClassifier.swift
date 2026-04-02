import AppKit

/// Catch-all classifier: groups remaining processes by responsible PID and bundle ID.
/// Always runs last in the registry.
struct GenericClassifier: ProcessClassifier {
    let name = "Generic"

    func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        guard !processes.isEmpty else { return .empty }

        // Group by: bundle ID if available, otherwise responsible PID, otherwise executable name
        var groups: [String: [ProcessSnapshot]] = [:]

        for process in processes {
            let key: String
            if let bundleId = process.bundleIdentifier {
                key = "bundle:\(bundleId)"
            } else if process.responsiblePid > 1 && process.responsiblePid != process.pid {
                key = "rpid:\(process.responsiblePid)"
            } else {
                let execName = CommandLineParser.executableName(from: process.path)
                key = "exec:\(execName.isEmpty ? process.name : execName)"
            }
            groups[key, default: []].append(process)
        }

        let claimedPIDs = Set(processes.map(\.pid))

        let processGroups = groups.map { (key, procs) -> ProcessGroup in
            let groupName = deriveGroupName(key: key, processes: procs)
            let icon = deriveIcon(processes: procs)
            let stableId = "generic:\(key)"

            return ProcessGroup(
                stableIdentifier: stableId,
                name: groupName,
                icon: icon,
                classifierName: name,
                explanation: nil,
                processes: procs,
                subGroups: nil,
                deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: procs),
                nonResidentMemory: procs.reduce(0) { $0 + $1.nonResidentMemory }
            )
        }.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }

        return ClassificationResult(groups: processGroups, claimedPIDs: claimedPIDs)
    }

    private func deriveGroupName(key: String, processes: [ProcessSnapshot]) -> String {
        if key.hasPrefix("bundle:") {
            // Try to get the app name from the path
            if let appName = processes.first.flatMap({ CommandLineParser.appNameFromPath($0.path) }) {
                return appName
            }
            // Fall back to bundle ID last component
            let bundleId = String(key.dropFirst("bundle:".count))
            return bundleId.components(separatedBy: ".").last ?? bundleId
        }

        if key.hasPrefix("rpid:") {
            // Try to name it by the responsible process's name
            if let first = processes.first {
                let execName = CommandLineParser.executableName(from: first.path)
                if !execName.isEmpty { return execName }
            }
            return "Process Group"
        }

        if key.hasPrefix("exec:") {
            return String(key.dropFirst("exec:".count))
        }

        return processes.first?.name ?? "Unknown"
    }

    private func deriveIcon(processes: [ProcessSnapshot]) -> NSImage? {
        for process in processes {
            if let bundleId = process.bundleIdentifier,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }
            if !process.path.isEmpty {
                let icon = NSWorkspace.shared.icon(forFile: process.path)
                return icon
            }
        }
        return nil
    }
}
