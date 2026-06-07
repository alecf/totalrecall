import AppKit

/// Groups Claude Code processes (volta shims running "claude") and their children
/// (MCP servers, bash shells, node processes).
/// Each Claude Code session is a separate group (keyed by root PID) so that
/// the instance merge toggle can combine or separate them.
public struct ClaudeCodeClassifier: ProcessClassifier {
    public let name = "Claude Code"

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        // Step 1: Find interactive Claude Code root processes.
        var rootCandidates: [ProcessSnapshot] = []

        for process in processes {
            if isClaudeCodeProcess(process), isInteractiveClaudeInvocation(process) {
                rootCandidates.append(process)
            }
        }

        let claudeRoots = topLevelRoots(from: rootCandidates, allProcesses: processes)

        guard !claudeRoots.isEmpty else { return .empty }

        // Step 2: For each root, collect all descendants.
        let byParent = Dictionary(grouping: processes, by: \.parentPid)
        var allClaimedPIDs: Set<pid_t> = []
        var groups: [ProcessGroup] = []

        for root in claudeRoots {
            var instancePIDs: Set<pid_t> = [root.pid]
            collectDescendants(of: root.pid, from: byParent, into: &instancePIDs)
            instancePIDs.formUnion(relatedBridgePIDs(for: root, roots: claudeRoots, processes: processes, byParent: byParent))

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

    /// Keep nested Claude invocations under their top-level interactive session.
    private func topLevelRoots(from candidates: [ProcessSnapshot], allProcesses: [ProcessSnapshot]) -> [ProcessSnapshot] {
        let candidatePIDs = Set(candidates.map(\.pid))
        let byPID = Dictionary(allProcesses.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        return candidates.filter { candidate in
            var current = candidate
            var visited: Set<Int32> = [candidate.pid]

            for _ in 0..<10 {
                guard current.parentPid > 1, !visited.contains(current.parentPid) else { break }
                if candidatePIDs.contains(current.parentPid) {
                    return false
                }
                visited.insert(current.parentPid)

                guard let parent = byPID[current.parentPid] else { break }
                current = parent
            }

            return true
        }
    }

    /// Attach ACP/SDK bridge processes to the matching interactive session when
    /// ancestry is separate but the workspace is unambiguous.
    private func relatedBridgePIDs(
        for root: ProcessSnapshot,
        roots: [ProcessSnapshot],
        processes: [ProcessSnapshot],
        byParent: [Int32: [ProcessSnapshot]]
    ) -> Set<pid_t> {
        guard let cwd = root.workingDirectory, cwd != "/" else { return [] }
        let matchingRoots = roots.filter { $0.workingDirectory == cwd }
        guard matchingRoots.count == 1 else { return [] }

        var pids: Set<pid_t> = []
        for process in processes where process.workingDirectory == cwd && isClaudeBridgeProcess(process) {
            if pids.insert(process.pid).inserted {
                collectDescendants(of: process.pid, from: byParent, into: &pids)
            }
        }
        return pids
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

    /// Exclude SDK/ACP bridge invocations that use Claude as a stream-json subprocess.
    /// If they are descendants of an interactive root, descendant collection still
    /// keeps them inside that root session.
    private func isInteractiveClaudeInvocation(_ process: ProcessSnapshot) -> Bool {
        !process.commandLineArgs.contains("stream-json")
    }

    private func isClaudeBridgeProcess(_ process: ProcessSnapshot) -> Bool {
        if isClaudeCodeProcess(process), !isInteractiveClaudeInvocation(process) {
            return true
        }

        let lowerPath = process.path.lowercased()
        if lowerPath.contains("claude-agent") || lowerPath.contains("claude-agent-sdk") {
            return true
        }

        return process.commandLineArgs.contains { arg in
            let lower = arg.lowercased()
            return lower.contains("claude-agent") || lower.contains("claude-agent-sdk")
        }
    }

    /// Derive a label for a Claude Code instance from its working directory.
    private func instanceLabel(root: ProcessSnapshot) -> String {
        var parts: [String] = []

        // Working directory is the best identifier
        if let cwd = root.workingDirectory, cwd != "/" {
            let dirName = (cwd as NSString).lastPathComponent
            parts.append("in \(dirName)")
        }

        if root.commandLineArgs.contains("--resume") {
            parts.append("(resumed)")
        }

        if parts.isEmpty {
            return "Session (PID \(root.pid))"
        }
        return parts.joined(separator: " ")
    }

    private func claudeCodeIcon() -> NSImage? {
        NSImage(systemSymbolName: "terminal", accessibilityDescription: "Claude Code")
    }
}
