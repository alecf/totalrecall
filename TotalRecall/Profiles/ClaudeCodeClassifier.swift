import AppKit

/// Groups Claude Code processes (volta shims running "claude") and their children
/// (MCP servers, bash shells, node processes).
/// Each Claude Code session is a separate group (keyed by root PID) so that
/// the instance merge toggle can combine or separate them.
public struct ClaudeCodeClassifier: ProcessClassifier {
    public let name = "Claude Code"

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        // Step 1: Find Claude Code root processes.
        var claudeRoots: [ProcessSnapshot] = []

        for process in processes {
            if isClaudeCodeProcess(process) {
                claudeRoots.append(process)
            }
        }

        guard !claudeRoots.isEmpty else { return .empty }

        // Step 2: For each root, collect all descendants.
        let byParent = Dictionary(grouping: processes, by: \.parentPid)
        var allClaimedPIDs: Set<pid_t> = []
        var groups: [ProcessGroup] = []

        for root in claudeRoots {
            var instancePIDs: Set<pid_t> = [root.pid]
            collectDescendants(of: root.pid, from: byParent, into: &instancePIDs)

            // Also claim via responsiblePid
            for process in processes where !instancePIDs.contains(process.pid) {
                if process.responsiblePid == root.pid {
                    instancePIDs.insert(process.pid)
                }
            }

            let instanceProcesses = processes.filter { instancePIDs.contains($0.pid) }
            allClaimedPIDs.formUnion(instancePIDs)

            // Derive a label for this instance from the args
            let label = instanceLabel(root: root)

            groups.append(ProcessGroup(
                stableIdentifier: "claude:\(root.pid)",
                name: "Claude Code",
                icon: claudeCodeIcon(),
                classifierName: name,
                explanation: label,
                processes: instanceProcesses,
                subGroups: nil,
                deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: instanceProcesses),
                nonResidentMemory: instanceProcesses.reduce(0) { $0 + $1.nonResidentMemory }
            ))
        }

        return ClassificationResult(
            groups: groups.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint },
            claimedPIDs: allClaimedPIDs
        )
    }

    /// Recursively collect all descendant PIDs.
    private func collectDescendants(of pid: pid_t, from byParent: [Int32: [ProcessSnapshot]], into pids: inout Set<pid_t>) {
        guard let children = byParent[pid] else { return }
        for child in children {
            if pids.insert(child.pid).inserted {
                collectDescendants(of: child.pid, from: byParent, into: &pids)
            }
        }
    }

    /// Detect a Claude Code process: a volta shim (or direct binary) running "claude".
    /// Uses shared volta resolution from CommandLineParser.
    private func isClaudeCodeProcess(_ process: ProcessSnapshot) -> Bool {
        let args = process.commandLineArgs

        // Check if args[0] is "claude" or ends with "/claude"
        if !args.isEmpty {
            let arg0 = args[0]
            if arg0 == "claude" || arg0.hasSuffix("/claude") {
                return true
            }
        }

        // Check if this is a volta shim (version-named process) running claude
        if CommandLineParser.isVersionString(process.name) {
            if let resolved = CommandLineParser.resolveVoltaShim(
                processName: process.name, path: process.path, args: args
            ), resolved == "claude" {
                return true
            }
            // Also check args directly
            for arg in args {
                if arg == "claude" || arg == "claude --resume" || arg.hasSuffix("/claude") {
                    return true
                }
            }
        }

        // Check executable path
        if process.path.hasSuffix("/claude") {
            return true
        }

        return false
    }

    /// Derive a label for a Claude Code instance (e.g., the workspace or --resume flag).
    private func instanceLabel(root: ProcessSnapshot) -> String {
        let args = root.commandLineArgs
        if args.contains("--resume") {
            return "Resumed session"
        }
        // Could extract --project flag or cwd in the future
        return "CLI session (PID \(root.pid))"
    }

    private func claudeCodeIcon() -> NSImage? {
        NSImage(systemSymbolName: "terminal", accessibilityDescription: "Claude Code")
    }
}
