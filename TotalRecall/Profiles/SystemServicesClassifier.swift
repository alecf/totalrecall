import AppKit

/// Groups known macOS system daemons with human-readable names and explanations.
public struct SystemServicesClassifier: ProcessClassifier {
    public let name = "System"

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
        "mediaanalysisd": ("Media Analysis", "Apple media analysis daemon — photo/video classification"),
        "ControlCenter": ("Control Center", "macOS Control Center — Wi-Fi, Bluetooth, Sound toggles"),
        "AppleIDSettings": ("Apple ID Settings", "Apple ID settings pane"),
        "com.apple.WebKit.WebContent": ("WebContent", "Safari/WebKit content rendering process"),
        "com.apple.WebKit.GPU": ("WebKit GPU", "Safari/WebKit GPU acceleration process"),
        "mdworker_shared": ("Spotlight Worker", "Spotlight indexing shared worker process"),
        "corespotlightd": ("Core Spotlight", "Core Spotlight indexing daemon"),
        "WindowManager": ("Window Manager", "macOS window management service"),
        "NotificationCenter": ("Notification Center", "macOS Notification Center"),
        "WallpaperAgent": ("Wallpaper Agent", "Desktop wallpaper management"),
        "AccessibilityUIServer": ("Accessibility", "Accessibility UI services"),
        "WiFiAgent": ("Wi-Fi Agent", "Wi-Fi connection management agent"),
        "universalaccessd": ("Universal Access", "Accessibility services daemon"),
        "AppleSpell": ("Spell Checker", "System-wide spell checking service"),
        "identityservicesd": ("Identity Services", "Apple ID and iMessage identity services"),
        "accountsd": ("Accounts", "Internet accounts management daemon"),
        "BiomeAgent": ("Biome Agent", "System intelligence and activity tracking"),
        "chronod": ("Chronod", "Time-based scheduling daemon"),
        "fontd": ("Font Daemon", "Font management and rendering service"),
        "iconservicesagent": ("Icon Services Agent", "Application icon cache agent"),
        "usernoted": ("User Notifications", "User notification delivery daemon"),
        "suggestd": ("Suggestions", "Siri suggestions and search ranking daemon"),
        "assistantd": ("Siri Assistant", "Siri backend processing daemon"),
        "siriactionsd": ("Siri Actions", "Siri shortcut actions daemon"),
        "imagent": ("iMessage Agent", "iMessage and FaceTime agent"),
        "familycircled": ("Family Circle", "Family Sharing coordination daemon"),
        "passd": ("Wallet/Passes", "Apple Wallet passes daemon"),
        "searchpartyuseragent": ("Find My Agent", "Find My network user agent"),
        "StatusKitAgent": ("Status Kit", "Focus/status management agent"),
        "routined": ("Routined", "Location and routine learning daemon"),
        "duetexpertd": ("Duet Expert", "Proactive intelligence and app prediction"),
        "homed": ("Home Daemon", "HomeKit coordination daemon"),
        "callservicesd": ("Call Services", "Phone and FaceTime call management daemon"),
        "spotlightknowledged.updater": ("Spotlight Knowledge", "Spotlight knowledge graph updater"),
        "talagentd": ("TAL Agent", "Transparency, Accountability, and Logging agent"),
        "secd": ("Security Daemon", "Security and keychain daemon"),
        "CursorUIViewService": ("Cursor UI", "Text cursor and input UI service"),
        "TextInputMenuAgent": ("Text Input", "Input method and keyboard menu agent"),
        "UserNotificationCenter": ("Notification Center", "User notification presentation"),
        "CoreServicesUIAgent": ("Core Services UI", "System dialog and alert presentation"),
        "universalAccessAuthWarn": ("Accessibility Warning", "Accessibility permission warning agent"),
        "VTDecoderXPCService": ("Video Decoder", "Hardware video decoding service"),
        "MobileDeviceUpdater": ("Mobile Device Updater", "iOS device update service"),
        "IntelligencePlatformComputeService": ("Apple Intelligence", "Apple Intelligence compute service"),
        "com.apple.SafariPlatformSupport": ("Safari Platform Support", "Safari platform support helper"),
        "com.apple.AuthenticationServicesUIAgent": ("Authentication UI", "Authentication and sign-in UI service"),
    ]

    /// Path prefixes that identify system processes even if not in knownServices.
    private static let systemPathPrefixes = [
        "/System/Library/",
        "/usr/libexec/",
        "/usr/sbin/",
    ]

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        var claimed: [ProcessSnapshot] = []
        var claimedPIDs: Set<pid_t> = []

        for process in processes {
            let execName = CommandLineParser.executableName(from: process.path)
            if Self.knownServices[execName] != nil || Self.knownServices[process.name] != nil {
                claimed.append(process)
                claimedPIDs.insert(process.pid)
            }
        }

        // Also claim low-level system daemons/agents running from system paths
        // that are small (< 50 MB) and have no .app bundle — these are background services.
        // Exclude: user-facing apps, XPC services for user apps (like Virtualization.framework),
        // and large processes that warrant their own groups.
        for process in processes where !claimedPIDs.contains(process.pid) {
            if isSystemDaemon(process) {
                claimed.append(process)
                claimedPIDs.insert(process.pid)
            }
        }

        guard !claimed.isEmpty else { return .empty }

        // Each known service is its own sub-entry within the "System Services" group
        let group = ProcessGroup(
            stableIdentifier: "system",
            name: "System Services",
            icon: {
                let img = NSImage(systemSymbolName: "gearshape.2", accessibilityDescription: "System")
                img?.isTemplate = false
                return img
            }(),
            classifierName: name,
            explanation: "macOS system daemons and services",
            processes: claimed,
            subGroups: nil,
            deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: claimed),
            nonResidentMemory: claimed.reduce(0) { $0 + $1.nonResidentMemory }
        )

        return ClassificationResult(groups: [group], claimedPIDs: claimedPIDs)
    }

    /// Check if a process is a low-level system daemon (not a user-facing app or XPC service for user apps).
    private func isSystemDaemon(_ process: ProcessSnapshot) -> Bool {
        let path = process.path

        // Never claim user-facing apps
        if path.hasPrefix("/System/Applications/") ||
           path.hasPrefix("/System/Volumes/Preboot/Cryptexes/App/System/Applications/") {
            return false
        }

        // Never claim large XPC services (e.g., Virtualization framework for Docker) — they
        // deserve their own groups or should be grouped with the parent app.
        if path.contains(".framework/") && path.contains("XPCServices") &&
           process.physFootprint > 50 * 1024 * 1024 {
            return false
        }

        // Claim processes from system daemon/service paths
        let alwaysSystemPrefixes = [
            "/usr/libexec/",
            "/usr/sbin/",
            "/System/Library/CoreServices/",
            "/System/Library/PrivateFrameworks/",
            "/System/Library/ExtensionKit/",
            "/System/Library/Input Methods/",
            "/System/Library/Image Capture/",
        ]
        for prefix in alwaysSystemPrefixes {
            if path.hasPrefix(prefix) { return true }
        }

        // Claim small XPC services from system frameworks (< 50 MB) — these are
        // system background services like WebKit networking, authentication UI, etc.
        let conditionalSystemPrefixes = [
            "/System/Library/Frameworks/",
            "/System/Volumes/Preboot/Cryptexes/OS/System/Library/",
            "/System/Volumes/Preboot/Cryptexes/App/usr/libexec/",
        ]
        for prefix in conditionalSystemPrefixes {
            if path.hasPrefix(prefix) && process.physFootprint < 50 * 1024 * 1024 {
                return true
            }
        }

        return false
    }

    /// Get the human-readable explanation for a system process.
    public static func explanation(for processName: String) -> String? {
        knownServices[processName]?.explanation
    }

    /// Get the display name for a system process.
    public static func displayName(for processName: String) -> String? {
        knownServices[processName]?.name
    }
}
