import AppKit

/// Groups Google Chrome processes by profile, identifying renderer/GPU/utility/extension types.
struct ChromeClassifier: ProcessClassifier {
    let name = "Chrome"

    func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        // Claim all processes whose path contains "Google Chrome"
        let chromeProcesses = processes.filter {
            $0.path.contains("Google Chrome") || $0.bundleIdentifier == "com.google.Chrome"
        }

        guard !chromeProcesses.isEmpty else { return .empty }

        let claimedPIDs = Set(chromeProcesses.map(\.pid))

        // Group by profile directory
        var profileGroups: [String: [ProcessSnapshot]] = [:]
        var unprofiledProcesses: [ProcessSnapshot] = []

        for process in chromeProcesses {
            if let profileDir = CommandLineParser.chromeProfileDirectory(from: process.commandLineArgs) {
                profileGroups[profileDir, default: []].append(process)
            } else {
                // Main browser process, GPU process, etc. — not profile-specific
                unprofiledProcesses.append(process)
            }
        }

        // Build sub-groups per profile
        var subGroups: [ProcessGroup] = []
        for (profileDir, procs) in profileGroups.sorted(by: { $0.key < $1.key }) {
            let profileName = humanReadableProfileName(profileDir)
            let labeled = procs.map { labelChromeProcess($0) }
            _ = labeled // labels used in future UI; for now just group

            subGroups.append(ProcessGroup(
                stableIdentifier: "chrome:\(profileDir)",
                name: profileName,
                icon: nil,
                classifierName: name,
                explanation: nil,
                processes: procs,
                subGroups: nil,
                deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: procs),
                nonResidentMemory: procs.reduce(0) { $0 + $1.nonResidentMemory }
            ))
        }

        // All Chrome processes in one top-level group
        let allProcs = chromeProcesses
        let group = ProcessGroup(
            stableIdentifier: "chrome",
            name: "Google Chrome",
            icon: iconForChrome(from: chromeProcesses),
            classifierName: name,
            explanation: nil,
            processes: unprofiledProcesses,
            subGroups: subGroups.isEmpty ? nil : subGroups,
            deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: allProcs),
            nonResidentMemory: allProcs.reduce(0) { $0 + $1.nonResidentMemory }
        )

        return ClassificationResult(groups: [group], claimedPIDs: claimedPIDs)
    }

    private func humanReadableProfileName(_ dir: String) -> String {
        switch dir {
        case "Default": return "Default Profile"
        case _ where dir.hasPrefix("Profile "): return dir
        default: return dir
        }
    }

    private func labelChromeProcess(_ process: ProcessSnapshot) -> String {
        if let type = CommandLineParser.electronProcessType(from: process.commandLineArgs) {
            switch type {
            case .renderer: return "Renderer"
            case .gpu: return "GPU Process"
            case .utility: return "Utility"
            case .broker: return "Broker"
            case .crashpad: return "Crash Handler"
            default: return type.rawValue
            }
        }
        if process.path.contains("Google Chrome") && !process.path.contains("Helper") {
            return "Main Process"
        }
        return process.name
    }

    private func iconForChrome(from processes: [ProcessSnapshot]) -> NSImage? {
        // Try to get the icon from the main Chrome process
        if let mainProc = processes.first(where: { !$0.path.contains("Helper") }) {
            return NSWorkspace.shared.icon(forFile: mainProc.path)
        }
        return nil
    }
}
