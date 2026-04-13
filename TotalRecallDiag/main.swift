import Foundation
import TotalRecallCore

// CLI diagnostic tool — runs the full classification pipeline and prints the result.
// Usage: swift run TotalRecallDiag [--tree]

let args = CommandLine.arguments
let treeMode = args.contains("--tree")

@MainActor
func run() async {
    let monitor = ProcessMonitor()
    let registry = ClassifierRegistry.default

    print("Collecting process data...")
    let result = await monitor.collectSnapshot(mode: .full)
    print("Collected \(result.snapshots.count) processes.\n")

    // Debug: check for specific missing PIDs
    let debugPIDs: [pid_t] = [5110, 7379, 7563, 1371]  // Firefox main, crashhelper, gpu-helper, zoom.us
    for debugPID in debugPIDs {
        let found = result.snapshots.first { $0.pid == debugPID }
        if let snap = found {
            print("  DEBUG PID \(debugPID): found as '\(snap.name)' path=...\(snap.path.suffix(40)) bundleId=\(snap.bundleIdentifier ?? "nil")")
        } else {
            print("  DEBUG PID \(debugPID): MISSING from snapshots")
        }
    }

    let groups = registry.classify(snapshots: result.snapshots)

    // Debug: which group owns each debug PID?
    for debugPID in [5110, 7379, 7563, 1371] as [pid_t] {
        var found = false
        for group in groups {
            if group.processes.contains(where: { $0.pid == debugPID }) {
                print("  DEBUG PID \(debugPID): in group '\(group.name)' [\(group.classifierName)]")
                found = true
                break
            }
            if let subs = group.subGroups {
                for sub in subs {
                    if sub.processes.contains(where: { $0.pid == debugPID }) {
                        print("  DEBUG PID \(debugPID): in sub-group '\(sub.name)' of '\(group.name)' [\(group.classifierName)]")
                        found = true
                        break
                    }
                }
            }
            if found { break }
        }
        if !found { print("  DEBUG PID \(debugPID): NOT IN ANY GROUP") }
    }

    if treeMode {
        printTreeView(groups: groups, systemMemory: result.systemMemory, totalProcesses: result.snapshots.count)
    } else {
        let output = GroupDiagnostics.diagnose(
            groups: groups,
            systemMemory: result.systemMemory,
            totalProcesses: result.snapshots.count
        )
        print(output)
    }

    // Summary analysis
    print("=== Analysis ===")
    print("")

    // Check for duplicate top-level app names
    var nameCount: [String: Int] = [:]
    for group in groups {
        nameCount[group.name, default: 0] += 1
    }
    let duplicates = nameCount.filter { $0.value > 1 }
    if !duplicates.isEmpty {
        print("DUPLICATES at top level:")
        for (name, count) in duplicates.sorted(by: { $0.key < $1.key }) {
            print("  - '\(name)' appears \(count) times")
        }
    } else {
        print("No duplicate app names at top level.")
    }

    // Detailed icon diagnostics
    print("\nICON DIAGNOSTICS:")
    for group in groups where ["Firefox", "zoom.us", "Slack", "Claude Code", "System Services"].contains(group.name) {
        let iconReps = group.icon?.representations.map { "\(type(of: $0))" }.joined(separator: ", ") ?? "nil"
        let iconSize = group.icon?.size ?? .zero
        let isTemplate = group.icon?.isTemplate ?? false
        print("  \(group.name) [\(group.classifierName)]:")
        print("    icon: size=\(iconSize), template=\(isTemplate), reps=\(iconReps)")
        // Show processes sorted by PID (main process first)
        let sorted = group.processes.sorted { $0.pid < $1.pid }
        for proc in sorted.prefix(3) {
            print("    PID \(proc.pid) \(proc.name) bundleId=\(proc.bundleIdentifier ?? "nil")")
        }
    }

    // Check for missing icons
    let noIcon = groups.filter { $0.icon == nil }
    if !noIcon.isEmpty {
        print("\nMISSING ICONS (\(noIcon.count)):")
        for group in noIcon {
            print("  - \(group.name) [\(group.classifierName)]")
        }
    } else {
        print("\nAll groups have icons.")
    }

    // Check for opaque names (version strings, single words that are runtimes)
    let opaqueNames = groups.filter { isOpaqueName($0.name) }
    if !opaqueNames.isEmpty {
        print("\nOPAQUE NAMES (need better identification):")
        for group in opaqueNames {
            let firstProc = group.processes.first
            let args = firstProc?.commandLineArgs.prefix(3).joined(separator: " ") ?? "?"
            print("  - '\(group.name)' [\(group.classifierName)] — args: \(args)")
        }
    } else {
        print("\nNo opaque process names.")
    }

    // Check for potential system processes not in System group
    let possibleSystem = groups.filter {
        $0.classifierName != "System" &&
        $0.processes.allSatisfy { proc in
            proc.path.hasPrefix("/System/") ||
            proc.path.hasPrefix("/usr/") ||
            proc.path.hasPrefix("/Library/Apple/") ||
            proc.name.hasSuffix("d") && !proc.name.contains(" ")
        }
    }
    if !possibleSystem.isEmpty {
        print("\nPOTENTIAL SYSTEM PROCESSES not in System group:")
        for group in possibleSystem {
            let paths = group.processes.prefix(2).map { $0.path }.joined(separator: ", ")
            print("  - '\(group.name)' (\(group.processCount) procs) — \(paths)")
        }
    }

    print("\nTotal: \(groups.count) groups, \(result.snapshots.count) processes")
}

func printTreeView(groups: [ProcessGroup], systemMemory: SystemMemoryInfo, totalProcesses: Int) {
    let formatter = MemoryFormatter.self
    print("=== Total Recall — Process Tree ===")
    print("System: \(formatter.format(bytes: systemMemory.used)) used / \(formatter.format(bytes: systemMemory.totalPhysical)) total | Pressure: \(systemMemory.memoryPressure.rawValue)")
    print("Processes: \(totalProcesses) total across \(groups.count) groups\n")

    let sorted = groups.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }
    for group in sorted {
        let iconLabel = group.icon != nil ? "icon" : "no-icon"
        let allProcs = collectAllProcesses(from: group)
        print("[\(group.classifierName)] \(group.name)  —  \(formatter.format(bytes: group.deduplicatedFootprint))  (\(allProcs.count) procs, \(iconLabel))")

        // Build parent-child tree
        let pids = Set(allProcs.map(\.pid))
        let childrenByParent = Dictionary(grouping: allProcs, by: \.parentPid)

        // Roots: processes whose parent is not in this group
        let roots = allProcs.filter { !pids.contains($0.parentPid) }
            .sorted { $0.pid < $1.pid }

        for (i, root) in roots.enumerated() {
            let isLast = (i == roots.count - 1) && childrenByParent.values.allSatisfy({ _ in true })
            printTreeNode(root, childrenByParent: childrenByParent, prefix: "  ", isLast: i == roots.count - 1)
        }

        // Orphans (cycle detection)
        let rendered = collectTreePIDs(roots: roots, childrenByParent: childrenByParent)
        let orphans = allProcs.filter { !rendered.contains($0.pid) }
        for orphan in orphans {
            print("  ⚠ PID \(orphan.pid) \(orphan.name) (orphan, parent=\(orphan.parentPid)) — \(formatter.format(bytes: orphan.physFootprint))")
        }
        print()
    }
}

func printTreeNode(_ process: ProcessSnapshot, childrenByParent: [Int32: [ProcessSnapshot]], prefix: String, isLast: Bool) {
    let connector = isLast ? "└─" : "├─"
    let mem = MemoryFormatter.format(bytes: process.physFootprint)
    print("\(prefix)\(connector) PID \(process.pid) \(process.name) (\(mem)) [parent=\(process.parentPid)] — \(process.path.suffix(60))")

    let children = (childrenByParent[process.pid] ?? []).sorted { $0.pid < $1.pid }
    let childPrefix = prefix + (isLast ? "   " : "│  ")
    for (i, child) in children.enumerated() {
        printTreeNode(child, childrenByParent: childrenByParent, prefix: childPrefix, isLast: i == children.count - 1)
    }
}

func collectAllProcesses(from group: ProcessGroup) -> [ProcessSnapshot] {
    var all = group.processes
    if let subs = group.subGroups {
        for sub in subs {
            all.append(contentsOf: collectAllProcesses(from: sub))
        }
    }
    return all
}

func collectTreePIDs(roots: [ProcessSnapshot], childrenByParent: [Int32: [ProcessSnapshot]]) -> Set<Int32> {
    var result = Set<Int32>()
    var queue = roots.map(\.pid)
    while !queue.isEmpty {
        let pid = queue.removeFirst()
        result.insert(pid)
        if let children = childrenByParent[pid] {
            queue.append(contentsOf: children.map(\.pid))
        }
    }
    return result
}

func isOpaqueName(_ name: String) -> Bool {
    // Version strings like "2.1.87"
    let versionPattern = name.allSatisfy { $0.isNumber || $0 == "." }
    if versionPattern && name.contains(".") { return true }

    // Very short single-word names that look like executables
    if name.count <= 3 && name.allSatisfy(\.isLetter) { return true }

    // "node (something)" is okay, bare "node" is opaque
    if ["node", "python3", "python", "ruby", "bun", "npx"].contains(name) { return true }

    return false
}

await run()
