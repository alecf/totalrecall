import AppKit

/// Groups Electron app processes (main/renderer/utility) by bundle.
/// Catches VS Code, Slack, Discord, etc. without custom logic per app.
public struct ElectronClassifier: ProcessClassifier {
    public let name = "Electron"

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        // Detect Electron apps by framework path or --type= arg
        var electronByApp: [String: [ProcessSnapshot]] = [:]
        var claimedPIDs: Set<pid_t> = []

        // First pass: find Electron helper processes and collect their .app bundle paths
        var electronAppPaths: Set<String> = []

        for process in processes {
            let execName = CommandLineParser.executableName(from: process.path)
            let isElectron = process.path.contains("Electron.framework") ||
                             process.path.contains("Electron Helper") ||
                             execName == "Electron" ||
                             CommandLineParser.electronProcessType(from: process.commandLineArgs) != nil

            guard isElectron else { continue }

            let appName = CommandLineParser.appNameFromPath(process.path) ?? process.name
            electronByApp[appName, default: []].append(process)
            claimedPIDs.insert(process.pid)

            // Track the .app bundle path so we can claim the main process too
            if let appPath = extractAppBundlePath(from: process.path) {
                electronAppPaths.insert(appPath)
            }
        }

        // Second pass: claim main processes whose .app path matches an Electron app.
        // This prevents the main process (e.g., Slack, TIDAL) from going to GenericClassifier.
        if !electronAppPaths.isEmpty {
            for process in processes where !claimedPIDs.contains(process.pid) {
                if let appPath = extractAppBundlePath(from: process.path),
                   electronAppPaths.contains(appPath) {
                    let appName = CommandLineParser.appNameFromPath(process.path) ?? process.name
                    electronByApp[appName, default: []].append(process)
                    claimedPIDs.insert(process.pid)
                }
            }
        }

        guard !electronByApp.isEmpty else { return .empty }

        // Third pass: claim child processes of Electron apps (bash shells, node, etc.)
        // This prevents orphaned bash/node processes from the integrated terminals.
        // Build a PID -> appName lookup for efficient parent resolution.
        var pidToApp: [pid_t: String] = [:]
        for (appName, procs) in electronByApp {
            for proc in procs {
                pidToApp[proc.pid] = appName
            }
        }

        var childChanged = true
        while childChanged {
            childChanged = false
            for process in processes where !claimedPIDs.contains(process.pid) {
                if let parentApp = pidToApp[process.parentPid] {
                    electronByApp[parentApp, default: []].append(process)
                    claimedPIDs.insert(process.pid)
                    pidToApp[process.pid] = parentApp
                    childChanged = true
                }
            }
        }

        let groups = electronByApp.map { (appName, procs) -> ProcessGroup in
            ProcessGroup(
                stableIdentifier: "electron:\(appName.lowercased())",
                name: appName,
                icon: iconForApp(from: procs),
                classifierName: name,
                explanation: "Electron app",
                processes: procs,
                subGroups: nil,
                deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: procs),
                nonResidentMemory: procs.reduce(0) { $0 + $1.nonResidentMemory }
            )
        }.sorted { $0.deduplicatedFootprint > $1.deduplicatedFootprint }

        return ClassificationResult(groups: groups, claimedPIDs: claimedPIDs)
    }

    /// Extract the .app bundle path: "/Applications/Slack.app/Contents/..." → "/Applications/Slack.app"
    private func extractAppBundlePath(from path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[path.startIndex..<range.lowerBound]) + ".app"
        }
        if path.hasSuffix(".app") {
            return path
        }
        return nil
    }

    private func iconForApp(from processes: [ProcessSnapshot]) -> NSImage? {
        // Best: find the main process and get icon via NSRunningApplication
        let mainProcess = processes.first {
            CommandLineParser.electronProcessType(from: $0.commandLineArgs) == nil &&
            !$0.path.contains("Helper") && !$0.path.contains("crashpad") &&
            !$0.path.contains("ShipIt") && !$0.path.contains("Squirrel")
        }
        if let main = mainProcess,
           let app = NSRunningApplication(processIdentifier: main.pid),
           let icon = app.icon {
            return icon
        }
        // Fallback: any process via NSRunningApplication
        for proc in processes {
            if let app = NSRunningApplication(processIdentifier: proc.pid), let icon = app.icon {
                return icon
            }
        }
        // Last resort: .app bundle path
        for proc in processes {
            if let icon = SystemProbe.iconFromPath(proc.path) {
                return icon
            }
        }
        return nil
    }
}
