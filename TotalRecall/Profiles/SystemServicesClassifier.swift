import AppKit

/// Groups known macOS system daemons with human-readable names and explanations.
struct SystemServicesClassifier: ProcessClassifier {
    let name = "System"

    /// Dictionary of known daemon names → (display name, explanation).
    private static let knownServices: [String: (name: String, explanation: String)] = [
        "kernel_task": ("Kernel", "macOS kernel — memory management, I/O scheduling, thermal throttling"),
        "WindowServer": ("WindowServer", "Window compositing, rendering, and display management"),
        "mds_stores": ("Spotlight", "Spotlight search indexing — rebuilds index after file changes"),
        "mds": ("Spotlight Daemon", "Spotlight metadata server — coordinates search indexing"),
        "mds_worker": ("Spotlight Worker", "Spotlight indexing worker process"),
        "nsurlsessiond": ("Background Downloads", "System background download and upload service"),
        "bluetoothd": ("Bluetooth", "Bluetooth daemon — manages device connections"),
        "coreaudiod": ("Core Audio", "Audio routing and processing daemon"),
        "loginwindow": ("Login Window", "Login screen and user session management"),
        "Finder": ("Finder", "File manager and desktop"),
        "Dock": ("Dock", "Application launcher, window management, Spaces"),
        "SystemUIServer": ("System UI", "Menu bar extras, volume/brightness controls"),
        "launchd": ("launchd", "System and service manager — parent of most processes"),
        "configd": ("Network Config", "System configuration daemon — network settings"),
        "diskarbitrationd": ("Disk Arbitration", "Disk mount/unmount management"),
        "opendirectoryd": ("Directory Services", "User authentication and directory services"),
        "securityd": ("Security", "Keychain access, code signing, certificate validation"),
        "trustd": ("Trust Evaluation", "Certificate trust evaluation"),
        "syslogd": ("System Log", "System logging daemon"),
        "powerd": ("Power Management", "Sleep, wake, thermal management"),
        "UserEventAgent": ("User Event Agent", "Monitors user-level system events"),
        "symptomsd": ("Network Diagnostics", "Network quality monitoring and diagnostics"),
        "sharingd": ("Sharing", "AirDrop, Handoff, and sharing services"),
        "cloudd": ("CloudKit", "CloudKit sync daemon"),
        "bird": ("iCloud Documents", "iCloud document sync"),
        "iconservicesd": ("Icon Services", "Application icon cache management"),
        "lsd": ("Launch Services", "Application registration and file associations"),
        "spindump": ("Spindump", "System hang reporter"),
        "ReportCrash": ("Crash Reporter", "Captures crash logs for diagnostics"),
        "fileproviderd": ("File Provider", "Cloud storage file provider coordination"),
        "containermanagerd": ("Container Manager", "App sandbox container management"),
        "runningboardd": ("RunningBoard", "Process lifecycle management — launch, suspend, resume"),
        "thermalmonitord": ("Thermal Monitor", "CPU/GPU thermal management"),
        "corespeechd": ("Speech Recognition", "Siri and dictation speech processing"),
        "audioclocksyncd": ("Audio Clock Sync", "Audio device clock synchronization"),
        "mediaremoted": ("Media Remote", "Now Playing and remote media control"),
        "rapportd": ("Rapport", "Device-to-device communication (Universal Clipboard, etc.)"),
    ]

    func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        var claimed: [ProcessSnapshot] = []
        var claimedPIDs: Set<pid_t> = []

        for process in processes {
            let execName = CommandLineParser.executableName(from: process.path)
            if Self.knownServices[execName] != nil || Self.knownServices[process.name] != nil {
                claimed.append(process)
                claimedPIDs.insert(process.pid)
            }
        }

        guard !claimed.isEmpty else { return .empty }

        // Each known service is its own sub-entry within the "System Services" group
        let group = ProcessGroup(
            stableIdentifier: "system",
            name: "System Services",
            icon: NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "System"),
            classifierName: name,
            explanation: "macOS system daemons and services",
            processes: claimed,
            subGroups: nil,
            deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: claimed),
            nonResidentMemory: claimed.reduce(0) { $0 + $1.nonResidentMemory }
        )

        return ClassificationResult(groups: [group], claimedPIDs: claimedPIDs)
    }

    /// Get the human-readable explanation for a system process.
    static func explanation(for processName: String) -> String? {
        knownServices[processName]?.explanation
    }

    /// Get the display name for a system process.
    static func displayName(for processName: String) -> String? {
        knownServices[processName]?.name
    }
}
