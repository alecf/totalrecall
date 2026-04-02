import Foundation
import TotalRecallCore

// CLI diagnostic tool — runs the full classification pipeline and prints the result.
// Usage: swift run TotalRecallDiag

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

    let output = GroupDiagnostics.diagnose(
        groups: groups,
        systemMemory: result.systemMemory,
        totalProcesses: result.snapshots.count
    )
    print(output)

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

    // Detailed icon diagnostics for specific apps
    let debugApps = ["Firefox", "zoom.us", "Slack", "Cursor"]
    print("\nICON DIAGNOSTICS:")
    for group in groups where debugApps.contains(group.name) {
        print("  \(group.name) [\(group.classifierName)]:")
        print("    icon: \(group.icon != nil ? "YES" : "NIL")")
        print("    processes (\(group.processes.count)):")
        for proc in group.processes.prefix(5) {
            let hasBundle = proc.bundleIdentifier != nil
            print("      PID \(proc.pid) \(proc.name) bundleId=\(proc.bundleIdentifier ?? "nil") path=...\(proc.path.suffix(50))")
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
