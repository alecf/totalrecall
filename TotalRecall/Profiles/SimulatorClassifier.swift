import AppKit

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

    /// Resolves a device's display name (e.g. "iPhone 17 Pro") from its data
    /// directory. Injectable so tests don't touch the filesystem.
    private let deviceNameResolver: @Sendable (_ deviceDirectory: String) -> String?

    public init(deviceNameResolver: @escaping @Sendable (String) -> String? = SimulatorClassifier.deviceNameFromPlist) {
        self.deviceNameResolver = deviceNameResolver
    }

    private static let hostServicePrefix = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/"
    private static let simulatorAppBundleID = "com.apple.iphonesimulator"

    public func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = processes.filter(Self.isLaunchdSim)
        let rootPIDs = Set(roots.map(\.pid))

        var deviceMembers: [pid_t: [ProcessSnapshot]] = [:]
        var orphans: [ProcessSnapshot] = []
        var hostServices: [ProcessSnapshot] = []

        for process in processes {
            if rootPIDs.contains(process.pid) {
                deviceMembers[process.pid, default: []].append(process)
            } else if let root = Self.launchdSimAncestor(of: process, byPID: byPID, rootPIDs: rootPIDs) {
                deviceMembers[root, default: []].append(process)
            } else if Self.isSimulatorRuntimeProcess(process) {
                // A runtime process whose launchd_sim we can't see (exited, or
                // the parent chain was unreadable). Still a simulator process.
                orphans.append(process)
            } else if Self.isHostService(process) {
                hostServices.append(process)
            }
        }

        var groups: [ProcessGroup] = []
        for root in roots {
            guard let members = deviceMembers[root.pid] else { continue }
            groups.append(contentsOf: deviceGroups(root: root, members: members))
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
                icon: Self.simulatorAppIcon(),
                explanation: "Host-side CoreSimulator services shared by every booted device",
                processes: hostServices
            ))
        }

        let claimed = deviceMembers.values.flatMap { $0 } + orphans + hostServices
        return ClassificationResult(groups: groups, claimedPIDs: Set(claimed.map(\.pid)))
    }

    // MARK: - Device groups

    private func deviceGroups(root: ProcessSnapshot, members: [ProcessSnapshot]) -> [ProcessGroup] {
        let deviceDirectory = Self.deviceDirectory(fromArgs: root.commandLineArgs)
        let udid = deviceDirectory.map { ($0 as NSString).lastPathComponent }
        let deviceName = deviceDirectory.flatMap(deviceNameResolver)
        let runtime = members.lazy.compactMap { Self.runtimeName(fromPath: $0.path) }.first

        let name: String
        switch (deviceName, runtime) {
        case let (device?, runtime?): name = "\(device) (\(runtime))"
        case let (device?, nil): name = device
        case let (nil, runtime?): name = "\(runtime) Simulator"
        case (nil, nil): name = "Simulator"
        }

        var appProcesses: [String: [ProcessSnapshot]] = [:]
        var runtimeProcesses: [ProcessSnapshot] = []
        for process in members {
            if let bundle = Self.installedAppBundlePath(fromPath: process.path) {
                appProcesses[bundle, default: []].append(process)
            } else {
                runtimeProcesses.append(process)
            }
        }

        let id = "simulator:\(udid ?? String(root.pid))"
        let deviceSymbol = Self.symbolName(forDevice: deviceName)
        let device = makeGroup(
            id: id,
            name: name,
            icon: NSImage(systemSymbolName: deviceSymbol, accessibilityDescription: "Simulator"),
            explanation: "Booted Xcode Simulator device — the simulated OS's own daemons",
            processes: runtimeProcesses
        )

        let apps = appProcesses.sorted { $0.key < $1.key }.map { bundle, procs in
            let info = Self.appBundleInfo(bundlePath: bundle)
            let appName = info.name ?? ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            return makeGroup(
                id: "simulator-app:\(udid ?? String(root.pid)):\(appName)",
                name: deviceName.map { "\(appName) (\($0))" } ?? appName,
                icon: info.icon ?? NSImage(systemSymbolName: deviceSymbol, accessibilityDescription: appName),
                explanation: "App running on the \(name) simulator",
                processes: procs
            )
        }

        return [device] + apps
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
    static func appBundleInfo(bundlePath: String) -> (name: String?, icon: NSImage?) {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return (nil, nil) }

        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)

        let primary = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        let iconFiles = primary?["CFBundleIconFiles"] as? [String] ?? []
        let icon = iconFiles.reversed().lazy.compactMap { base in
            ["@3x.png", "@2x.png", ".png"].lazy.compactMap { suffix in
                NSImage(contentsOf: bundleURL.appendingPathComponent(base + suffix))
            }.first
        }.first

        return (name, icon)
    }

    private static func simulatorAppIcon() -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: simulatorAppBundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "iphone", accessibilityDescription: "Simulator")
    }
}
