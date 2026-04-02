import AppKit

/// Groups Electron app processes (main/renderer/utility) by bundle.
/// Catches VS Code, Slack, Discord, etc. without custom logic per app.
struct ElectronClassifier: ProcessClassifier {
    let name = "Electron"

    func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        // Detect Electron apps by framework path or --type= arg
        var electronByApp: [String: [ProcessSnapshot]] = [:]
        var claimedPIDs: Set<pid_t> = []

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
        }

        guard !electronByApp.isEmpty else { return .empty }

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

    private func iconForApp(from processes: [ProcessSnapshot]) -> NSImage? {
        // Find the main process (no --type= arg) for the icon
        if let mainProc = processes.first(where: {
            CommandLineParser.electronProcessType(from: $0.commandLineArgs) == nil
        }) {
            return NSWorkspace.shared.icon(forFile: mainProc.path)
        }
        return processes.first.flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
