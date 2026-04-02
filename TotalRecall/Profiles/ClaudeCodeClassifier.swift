import AppKit

/// Groups Claude Code processes (volta shims running "claude") and their children
/// (MCP servers, bash shells, node processes) into a single group.
public struct ClaudeCodeClassifier: ProcessClassifier {
    public let name = "Claude Code"

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        // Step 1: Find Claude Code root processes.
        // These are volta shims (version-named like "2.1.89") where args contain "claude".
        var claudeRootPIDs: Set<pid_t> = []

        for process in processes {
            if isClaudeCodeProcess(process) {
                claudeRootPIDs.insert(process.pid)
            }
        }

        guard !claudeRootPIDs.isEmpty else { return .empty }

        // Step 2: Collect all descendant processes of Claude Code roots.
        // This catches MCP servers, bash/sh shells, node processes, npx, volta-shim, etc.
        var claimedPIDs: Set<pid_t> = claudeRootPIDs
        var changed = true

        while changed {
            changed = false
            for process in processes where !claimedPIDs.contains(process.pid) {
                if process.parentPid > 1 && claimedPIDs.contains(process.parentPid) {
                    claimedPIDs.insert(process.pid)
                    changed = true
                }
            }
        }

        // Also walk up from processes to find Claude Code parents outside the initial snapshot.
        // Check responsiblePid as well — macOS sets this for child processes.
        for process in processes where !claimedPIDs.contains(process.pid) {
            if claudeRootPIDs.contains(process.responsiblePid) {
                claimedPIDs.insert(process.pid)
            }
        }

        let claimedProcesses = processes.filter { claimedPIDs.contains($0.pid) }

        let group = ProcessGroup(
            stableIdentifier: "claude-code",
            name: "Claude Code",
            icon: claudeCodeIcon(),
            classifierName: name,
            explanation: "Claude Code CLI sessions and their child processes (MCP servers, shells, etc.)",
            processes: claimedProcesses,
            subGroups: nil,
            deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: claimedProcesses),
            nonResidentMemory: claimedProcesses.reduce(0) { $0 + $1.nonResidentMemory }
        )

        return ClassificationResult(groups: [group], claimedPIDs: claimedPIDs)
    }

    /// Detect a Claude Code process: a volta shim (or direct binary) running "claude".
    private func isClaudeCodeProcess(_ process: ProcessSnapshot) -> Bool {
        let args = process.commandLineArgs

        // Check if args[0] (the executable name as invoked) is "claude" or ends with "/claude"
        if !args.isEmpty {
            let arg0 = args[0]
            if arg0 == "claude" || arg0.hasSuffix("/claude") {
                return true
            }
        }

        // Check if the process name looks like a version (e.g., "2.1.89") and args contain "claude"
        let name = process.name
        if looksLikeVersion(name) {
            for arg in args {
                if arg == "claude" || arg.hasPrefix("claude ") || arg == "claude --resume" {
                    return true
                }
            }
        }

        // Check if the executable path ends in /claude
        if process.path.hasSuffix("/claude") {
            return true
        }

        return false
    }

    /// Check if a string looks like a semver version (e.g., "2.1.89").
    private func looksLikeVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    private func claudeCodeIcon() -> NSImage? {
        // Try to find the Claude icon from the app bundle or use a terminal symbol
        NSImage(systemSymbolName: "terminal", accessibilityDescription: "Claude Code")
    }
}
