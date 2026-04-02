import AppKit

/// Shared diagnostic output for process groups — used by both the CLI tool and the app.
public enum GroupDiagnostics {
    public struct DiagnosticOutput: CustomStringConvertible {
        let groups: [ProcessGroup]
        let systemMemory: SystemMemoryInfo
        let totalProcesses: Int
        let ungroupedCount: Int

        public var description: String {
            var lines: [String] = []
            lines.append("=== Total Recall — Process Groups ===")
            lines.append("System: \(MemoryFormatter.format(bytes: systemMemory.used)) used / \(MemoryFormatter.format(bytes: systemMemory.totalPhysical)) total | Pressure: \(systemMemory.memoryPressure.rawValue) | Swap: \(MemoryFormatter.format(bytes: systemMemory.swapUsed))")
            lines.append("Processes: \(totalProcesses) total across \(groups.count) groups")
            lines.append("")

            for group in groups {
                let iconStatus = group.icon != nil ? "icon" : "NO ICON"
                let classifier = group.classifierName
                lines.append("[\(classifier)] \(group.name)  —  \(MemoryFormatter.format(bytes: group.deduplicatedFootprint))  (\(group.processCount) procs, \(iconStatus))")

                if let subGroups = group.subGroups, !subGroups.isEmpty {
                    for sub in subGroups {
                        lines.append("  ├─ \(sub.name)  —  \(MemoryFormatter.format(bytes: sub.deduplicatedFootprint))  (\(sub.processCount) procs)")
                        for proc in sub.processes.prefix(5) {
                            lines.append("  │  └─ \(procLine(proc))")
                        }
                        if sub.processes.count > 5 {
                            lines.append("  │  └─ ... +\(sub.processes.count - 5) more")
                        }
                    }
                }

                // Show top-level processes (not in sub-groups)
                let directProcs = group.processes
                for proc in directProcs.prefix(8) {
                    lines.append("  └─ \(procLine(proc))")
                }
                if directProcs.count > 8 {
                    lines.append("  └─ ... +\(directProcs.count - 8) more")
                }
                lines.append("")
            }

            return lines.joined(separator: "\n")
        }

        private func procLine(_ proc: ProcessSnapshot) -> String {
            let mem = MemoryFormatter.format(bytes: proc.physFootprint)
            let args = proc.commandLineArgs.prefix(3).joined(separator: " ")
            let truncArgs = args.count > 120 ? String(args.prefix(120)) + "..." : args
            return "PID \(proc.pid) \(proc.name) (\(mem)) — \(truncArgs)"
        }
    }

    public static func diagnose(groups: [ProcessGroup], systemMemory: SystemMemoryInfo, totalProcesses: Int) -> DiagnosticOutput {
        DiagnosticOutput(
            groups: groups,
            systemMemory: systemMemory,
            totalProcesses: totalProcesses,
            ungroupedCount: 0
        )
    }
}
