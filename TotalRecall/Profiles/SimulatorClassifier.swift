import AppKit
import Synchronization

/// Groups Xcode Simulator processes: one group per booted device, one per app
/// running on a device, plus one for the host-side CoreSimulator services.
///
/// A booted simulator is not a VM — its iOS (or watchOS/tvOS/visionOS) daemons
/// are ordinary host processes running under a per-device `launchd_sim`, from
/// binaries inside the runtime's `RuntimeRoot`. A single booted iPhone runs
/// well over a hundred of them, and their paths sit under a CoreSimulator
/// prefix that no system-path rule recognizes, so without this classifier each
/// one becomes its own top-level group.
///
/// Apps installed on a device get their own top-level groups rather than
/// sub-groups of the device: the app is the developer's code under test, the
/// device is overhead, and the two are what someone wants to compare.
public struct SimulatorClassifier: ProcessClassifier {
    public let name = "Simulator"

    /// Display name, bundle ID, and icon read from an installed app's bundle.
    public struct AppBundleInfo: Sendable {
        public let bundleIdentifier: String?
        public let name: String?
        public let icon: NSImage?
    }

    /// Resolves a device's display name (e.g. "iPhone 17 Pro") from its data
    /// directory. Injectable so tests don't touch the filesystem.
    private let deviceNameResolver: @Sendable (_ deviceDirectory: String) -> String?
    private let bundleInfoResolver: @Sendable (_ bundlePath: String) -> AppBundleInfo?
    private let cache = LookupCache()

    public init(
        deviceNameResolver: @escaping @Sendable (String) -> String? = SimulatorClassifier.deviceNameFromPlist,
        bundleInfoResolver: @escaping @Sendable (String) -> AppBundleInfo? = SimulatorClassifier.appBundleInfo
    ) {
        self.deviceNameResolver = deviceNameResolver
        self.bundleInfoResolver = bundleInfoResolver
    }

    private static let hostServicePrefix = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/"
    private static let simulatorAppBundleID = "com.apple.iphonesimulator"
    private static let appGroupPrefix = "simulator-app:"

    /// Whether a group is an app running on a simulator, as opposed to a
    /// device's own daemons or the host services. Only app groups are safe to
    /// bulk-kill: SIGKILLing a device's ~150 daemons or CoreSimulatorService
    /// wedges the simulator rather than shutting it down.
    public static func isAppGroup(_ group: ProcessGroup) -> Bool {
        group.stableIdentifier.hasPrefix(appGroupPrefix)
    }

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = processes.filter(Self.isLaunchdSim)
        let rootPIDs = Set(roots.map(\.pid))

        var deviceMembers: [pid_t: [ProcessSnapshot]] = [:]
        var orphanApps: [String: [ProcessSnapshot]] = [:]  // keyed by device directory
        var orphans: [ProcessSnapshot] = []
        var hostServices: [ProcessSnapshot] = []

        for process in processes {
            if rootPIDs.contains(process.pid) {
                deviceMembers[process.pid, default: []].append(process)
            } else if let root = Self.launchdSimAncestor(of: process, byPID: byPID, rootPIDs: rootPIDs) {
                deviceMembers[root, default: []].append(process)
            } else if let deviceDirectory = Self.deviceDirectory(fromAppPath: process.path) {
                // An app whose launchd_sim we can't see. Its path still names
                // the device, so it keeps its own group.
                orphanApps[deviceDirectory, default: []].append(process)
            } else if Self.isSimulatorRuntimeProcess(process) {
                // A runtime process whose launchd_sim we can't see (exited, or
                // the parent chain was unreadable). Still a simulator process.
                orphans.append(process)
            } else if Self.isHostService(process) {
                hostServices.append(process)
            }
        }

        let rootDirectories = Dictionary(uniqueKeysWithValues: roots.map {
            ($0.pid, Self.deviceDirectory(fromArgs: $0.commandLineArgs))
        })
        let deviceNames = resolveDeviceNames(
            Set(rootDirectories.values.compactMap { $0 }).union(orphanApps.keys)
        )

        var groups: [ProcessGroup] = []
        var bundlesInUse: Set<String> = []
        for root in roots {
            guard let members = deviceMembers[root.pid] else { continue }
            let directory = rootDirectories[root.pid] ?? nil
            groups.append(contentsOf: deviceGroups(
                members: members,
                deviceKey: directory.map { ($0 as NSString).lastPathComponent } ?? "pid-\(root.pid)",
                deviceName: directory.flatMap { deviceNames[$0] },
                bundlesInUse: &bundlesInUse
            ))
        }
        for (directory, procs) in orphanApps.sorted(by: { $0.key < $1.key }) {
            let deviceName = deviceNames[directory]
            groups.append(contentsOf: appGroups(
                procs,
                deviceKey: (directory as NSString).lastPathComponent,
                deviceName: deviceName,
                deviceDescription: deviceName ?? "Simulator",
                bundlesInUse: &bundlesInUse
            ))
        }
        if !orphans.isEmpty {
            groups.append(makeGroup(
                id: "simulator:runtime",
                name: "Simulator",
                icon: NSImage(systemSymbolName: "iphone", accessibilityDescription: "Simulator"),
                explanation: "Simulator runtime processes whose device couldn't be identified",
                processes: orphans
            ))
        }
        if !hostServices.isEmpty {
            groups.append(makeGroup(
                id: "simulator:host",
                name: "Simulator Services",
                icon: SystemProbe.iconFromBundleID(Self.simulatorAppBundleID)
                    ?? NSImage(systemSymbolName: "iphone", accessibilityDescription: "Simulator"),
                explanation: "Host-side CoreSimulator services shared by every booted device",
                processes: hostServices
            ))
        }

        cache.prune(keepingDevices: Set(deviceNames.keys), bundles: bundlesInUse)

        let claimed = deviceMembers.values.flatMap { $0 } + orphanApps.values.flatMap { $0 } + orphans + hostServices
        return ClassificationResult(groups: groups, claimedPIDs: Set(claimed.map(\.pid)))
    }

    // MARK: - Device groups

    /// Resolve each device's display name, disambiguating devices that share
    /// one (two booted "iPhone 17 Pro"s) with the start of their UDID.
    private func resolveDeviceNames(_ directories: Set<String>) -> [String: String] {
        var names: [String: String] = [:]
        for directory in directories {
            if let name = cache.deviceName(for: directory, resolve: deviceNameResolver) {
                names[directory] = name
            }
        }
        let counts = Dictionary(names.values.map { ($0, 1) }, uniquingKeysWith: +)
        for (directory, name) in names where counts[name, default: 0] > 1 {
            let udid = (directory as NSString).lastPathComponent
            names[directory] = "\(name) · \(udid.prefix(4))"
        }
        return names
    }

    private func deviceGroups(members: [ProcessSnapshot], deviceKey: String, deviceName: String?,
                              bundlesInUse: inout Set<String>) -> [ProcessGroup] {
        let runtime = members.lazy.compactMap { Self.runtimeName(fromPath: $0.path) }.first

        let name: String
        switch (deviceName, runtime) {
        case let (device?, runtime?): name = "\(device) (\(runtime))"
        case let (device?, nil): name = device
        case let (nil, runtime?): name = "\(runtime) Simulator"
        case (nil, nil): name = "Simulator"
        }

        let (appProcesses, runtimeProcesses) = members.reduce(into: ([ProcessSnapshot](), [ProcessSnapshot]())) {
            if Self.installedAppBundlePath(fromPath: $1.path) != nil { $0.0.append($1) } else { $0.1.append($1) }
        }

        let device = makeGroup(
            id: "simulator:\(deviceKey)",
            name: name,
            icon: NSImage(systemSymbolName: Self.symbolName(forDevice: deviceName), accessibilityDescription: "Simulator"),
            explanation: "Booted Xcode Simulator device — the simulated OS's own daemons",
            processes: runtimeProcesses
        )

        return [device] + appGroups(appProcesses, deviceKey: deviceKey, deviceName: deviceName,
                                    deviceDescription: name, bundlesInUse: &bundlesInUse)
    }

    /// One group per installed app bundle. Keyed by bundle ID, not display
    /// name, so a Debug and a Staging build that share a name stay distinct.
    private func appGroups(_ processes: [ProcessSnapshot], deviceKey: String, deviceName: String?,
                           deviceDescription: String, bundlesInUse: inout Set<String>) -> [ProcessGroup] {
        let byBundle = Dictionary(grouping: processes) { Self.installedAppBundlePath(fromPath: $0.path) ?? "" }
        return byBundle.sorted { $0.key < $1.key }.map { bundle, procs in
            bundlesInUse.insert(bundle)
            let info = cache.bundleInfo(for: bundle, resolve: bundleInfoResolver)
            let bundleName = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            let appName = info?.name ?? bundleName
            return makeGroup(
                id: "\(Self.appGroupPrefix)\(deviceKey):\(info?.bundleIdentifier ?? bundleName)",
                name: deviceName.map { "\(appName) (\($0))" } ?? appName,
                icon: info?.icon ?? NSImage(systemSymbolName: Self.symbolName(forDevice: deviceName),
                                            accessibilityDescription: appName),
                explanation: "App running on the \(deviceDescription) simulator",
                processes: procs
            )
        }
    }

    private func makeGroup(id: String, name: String, icon: NSImage?, explanation: String?,
                           processes: [ProcessSnapshot]) -> ProcessGroup {
        ProcessGroup(
            stableIdentifier: id,
            name: name,
            icon: icon,
            classifierName: self.name,
            explanation: explanation,
            processes: processes,
            subGroups: nil,
            deduplicatedFootprint: ProcessGroup.computeDeduplicatedFootprint(for: processes),
            nonResidentMemory: processes.reduce(0) { $0 + $1.nonResidentMemory }
        )
    }

    // MARK: - Path recognition

    static func isLaunchdSim(_ process: ProcessSnapshot) -> Bool {
        process.name == "launchd_sim" || process.path.hasSuffix("/launchd_sim")
    }

    /// Binaries shipped inside a simulator runtime, or apps installed on a device.
    static func isSimulatorRuntimeProcess(_ process: ProcessSnapshot) -> Bool {
        let path = process.path
        return (path.contains("/CoreSimulator/") && path.contains("/RuntimeRoot/"))
            || path.contains("/CoreSimulator/Devices/")
    }

    /// CoreSimulatorService, SimRenderServer, SimMetalHost, and Simulator.app itself.
    static func isHostService(_ process: ProcessSnapshot) -> Bool {
        process.path.hasPrefix(hostServicePrefix)
            || process.bundleIdentifier == simulatorAppBundleID
            || process.path.hasSuffix("/Simulator.app/Contents/MacOS/Simulator")
    }

    /// Walk the parent chain to the nearest `launchd_sim`, if any.
    static func launchdSimAncestor(of process: ProcessSnapshot, byPID: [pid_t: ProcessSnapshot],
                                   rootPIDs: Set<pid_t>) -> pid_t? {
        var current = process.parentPid
        var visited: Set<pid_t> = [process.pid]
        while current > 1, visited.insert(current).inserted {
            if rootPIDs.contains(current) { return current }
            guard let parent = byPID[current] else { return nil }
            current = parent.parentPid
        }
        return nil
    }

    /// `launchd_sim <device dir>/data/var/run/launchd_bootstrap.plist` → `<device dir>`.
    static func deviceDirectory(fromArgs args: [String]) -> String? {
        for arg in args {
            guard let range = arg.range(of: "/data/var/run/") else { continue }
            return String(arg[..<range.lowerBound])
        }
        return nil
    }

    /// `.../Runtimes/iOS 26.5.simruntime/...` → "iOS 26.5".
    static func runtimeName(fromPath path: String) -> String? {
        guard let end = path.range(of: ".simruntime/") else { return nil }
        let prefix = path[..<end.lowerBound]
        guard let slash = prefix.lastIndex(of: "/") else { return nil }
        let name = prefix[prefix.index(after: slash)...]
        return name.isEmpty ? nil : String(name)
    }

    /// `<device dir>/data/Containers/Bundle/Application/...` → `<device dir>`.
    static func deviceDirectory(fromAppPath path: String) -> String? {
        guard path.contains("/CoreSimulator/Devices/"),
              let marker = path.range(of: "/data/Containers/Bundle/Application/")
        else { return nil }
        return String(path[..<marker.lowerBound])
    }

    /// `.../data/Containers/Bundle/Application/<UUID>/Foo.app/Foo` → `.../<UUID>/Foo.app`.
    static func installedAppBundlePath(fromPath path: String) -> String? {
        guard let marker = path.range(of: "/data/Containers/Bundle/Application/"),
              let appEnd = path.range(of: ".app/", range: marker.upperBound..<path.endIndex)
        else { return nil }
        return String(path[..<appEnd.lowerBound]) + ".app"
    }

    static func symbolName(forDevice deviceName: String?) -> String {
        guard let deviceName else { return "iphone" }
        if deviceName.contains("iPad") { return "ipad" }
        if deviceName.contains("Watch") { return "applewatch" }
        if deviceName.contains("Vision") { return "visionpro" }
        if deviceName.contains("TV") { return "appletv" }
        return "iphone"
    }

    // MARK: - Filesystem lookups

    /// Reads `name` from the device's `device.plist`, next to its `data` directory.
    public static func deviceNameFromPlist(deviceDirectory: String) -> String? {
        let url = URL(fileURLWithPath: deviceDirectory).appendingPathComponent("device.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["name"] as? String
    }

    /// Display name and icon of an iOS app bundle. NSWorkspace can't render an
    /// iOS bundle's icon (it lives in Assets.car), but Xcode also copies the
    /// primary icon out as `<CFBundleIconFiles>@2x.png`, which loads directly.
    public static func appBundleInfo(bundlePath: String) -> AppBundleInfo? {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)

        let primary = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = primary?["CFBundleIconFiles"] as? [String] ?? []
        let icon = iconFiles.reversed().lazy.compactMap { base in
            ["@3x.png", "@2x.png", ".png"].lazy.compactMap { suffix in
                NSImage(contentsOf: bundleURL.appendingPathComponent(base + suffix))
            }.first
        }.first

        return AppBundleInfo(bundleIdentifier: plist["CFBundleIdentifier"] as? String, name: name, icon: icon)
    }
}

/// Memoizes device names and app bundle info across refreshes, so a 5s poll
/// doesn't re-read plists and decode icons for every booted device and app.
/// Failed lookups aren't cached, so a transient read error retries next time.
/// Entries for devices and bundles that disappear are pruned each pass; a
/// rebuilt app reinstalls into a new container path, so it misses naturally.
private final class LookupCache: Sendable {
    private struct State {
        var deviceNames: [String: String] = [:]
        var bundles: [String: SimulatorClassifier.AppBundleInfo] = [:]
    }

    private let state = Mutex(State())

    func deviceName(for directory: String, resolve: (String) -> String?) -> String? {
        if let cached = state.withLock({ $0.deviceNames[directory] }) { return cached }
        let name = resolve(directory)
        if let name { state.withLock { $0.deviceNames[directory] = name } }
        return name
    }

    func bundleInfo(for bundle: String, resolve: (String) -> SimulatorClassifier.AppBundleInfo?)
        -> SimulatorClassifier.AppBundleInfo? {
        if let cached = state.withLock({ $0.bundles[bundle] }) { return cached }
        let info = resolve(bundle)
        if let info { state.withLock { $0.bundles[bundle] = info } }
        return info
    }

    func prune(keepingDevices devices: Set<String>, bundles: Set<String>) {
        state.withLock {
            $0.deviceNames = $0.deviceNames.filter { devices.contains($0.key) }
            $0.bundles = $0.bundles.filter { bundles.contains($0.key) }
        }
    }
}
