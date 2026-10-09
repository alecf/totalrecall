import AppKit
import Synchronization
import Testing
@testable import TotalRecallCore

@Suite("SimulatorClassifier")
struct SimulatorClassifierTests {
    let classifier = SimulatorClassifier(deviceNameResolver: { _ in "iPhone 17 Pro" })

    // MARK: - Device grouping

    private func deviceGroup(_ result: ClassificationResult) -> ProcessGroup? {
        result.groups.first { $0.stableIdentifier.hasPrefix("simulator:") }
    }

    private func appGroups(_ result: ClassificationResult) -> [ProcessGroup] {
        result.groups.filter { $0.stableIdentifier.hasPrefix("simulator-app:") }
    }

    @Test("A booted device's runtime processes form one group named after the device and runtime")
    func groupsBootedDevice() {
        let procs = FixtureBuilder.bootedSimulator()
        let result = classifier.classify(procs)

        #expect(result.claimedPIDs == Set(procs.map(\.pid)))
        let group = deviceGroup(result)
        #expect(group?.name == "iPhone 17 Pro (iOS 26.0)")
        #expect(group?.stableIdentifier == "simulator:11111111-2222-3333-4444-555555555555")
        #expect(group?.classifierName == "Simulator")
        #expect(group?.processCount == 4)
    }

    @Test("Descendants of launchd_sim are claimed even at system-looking paths")
    func claimsGrandchildAtSystemPath() {
        let result = classifier.classify(FixtureBuilder.bootedSimulator(rootPid: 6000))
        // assetsd lives at /usr/libexec and is parented by xpcproxy_sim, not launchd_sim
        #expect(result.claimedPIDs.contains(6003))
        #expect(deviceGroup(result)?.uniqueProcesses.contains { $0.name == "assetsd" } == true)
    }

    @Test("Apps installed on the device get their own top-level groups, labeled with the device")
    func installedAppsAreSeparateGroups() {
        let result = classifier.classify(FixtureBuilder.bootedSimulator())
        let apps = appGroups(result)

        #expect(result.groups.count == 2)
        #expect(apps.map(\.name) == ["MyApp (iPhone 17 Pro)"])
        #expect(apps.first?.stableIdentifier == "simulator-app:11111111-2222-3333-4444-555555555555:MyApp")
        #expect(deviceGroup(result)?.subGroups == nil)
        #expect(deviceGroup(result)?.processes.contains { $0.name == "MyApp" } == false)
    }

    @Test("Device footprint excludes the apps running on it")
    func deviceFootprintExcludesApps() {
        let procs = FixtureBuilder.bootedSimulator()
        let runtimeOnly = procs.filter { $0.name != "MyApp" }
        let group = deviceGroup(classifier.classify(procs))
        #expect(group?.deduplicatedFootprint == ProcessGroup.computeDeduplicatedFootprint(for: runtimeOnly))
    }

    @Test("Locates the app bundle for a process installed on a device")
    func installedAppBundlePath() {
        let bundle = "\(FixtureBuilder.simDeviceDirectory)/data/Containers/Bundle/Application/AAAA/MyApp.app"
        #expect(SimulatorClassifier.installedAppBundlePath(fromPath: "\(bundle)/MyApp") == bundle)
        #expect(SimulatorClassifier.installedAppBundlePath(fromPath: "\(bundle)/PlugIns/Widget.appex/Widget") == bundle)
        #expect(SimulatorClassifier.installedAppBundlePath(fromPath: "/Applications/Foo.app/Contents/MacOS/Foo") == nil)
    }

    @Test("Two booted devices produce two groups")
    func twoDevices() {
        let otherDevice = "/Users/test/Library/Developer/CoreSimulator/Devices/99999999-2222-3333-4444-555555555555"
        let procs = FixtureBuilder.bootedSimulator(rootPid: 6000)
            + FixtureBuilder.bootedSimulator(rootPid: 7000, deviceDirectory: otherDevice)
        let result = classifier.classify(procs)

        #expect(result.groups.count == 4)
        #expect(Set(result.groups.map(\.stableIdentifier)).count == 4)
        #expect(appGroups(result).count == 2)
    }

    @Test("Two devices with the same name are told apart by UDID prefix")
    func duplicateDeviceNames() {
        let otherDevice = "/Users/test/Library/Developer/CoreSimulator/Devices/99999999-2222-3333-4444-555555555555"
        let procs = FixtureBuilder.bootedSimulator(rootPid: 6000)
            + FixtureBuilder.bootedSimulator(rootPid: 7000, deviceDirectory: otherDevice)
        let result = classifier.classify(procs)

        let names = Set(result.groups.map(\.name))
        #expect(names.count == 4)
        #expect(names.contains("iPhone 17 Pro · 1111 (iOS 26.0)"))
        #expect(names.contains("MyApp (iPhone 17 Pro · 9999)"))
    }

    @Test("Apps sharing a display name but not a bundle ID get distinct groups")
    func sameNameDifferentBundleID() {
        let classifier = SimulatorClassifier(
            deviceNameResolver: { _ in "iPhone 17 Pro" },
            bundleInfoResolver: { bundle in
                .init(bundleIdentifier: bundle.contains("Staging") ? "com.example.myapp.staging" : "com.example.myapp",
                      name: "MyApp", icon: nil)
            }
        )
        let staging = FixtureBuilder.genericProcess(
            pid: 6100, name: "MyApp",
            path: "\(FixtureBuilder.simDeviceDirectory)/data/Containers/Bundle/Application/FFFF/MyApp Staging.app/MyApp"
        )
        var procs = FixtureBuilder.bootedSimulator()
        procs.append(ProcessSnapshotTestCopy.reparent(staging, to: 6000))
        let apps = appGroups(classifier.classify(procs))

        #expect(apps.count == 2)
        #expect(Set(apps.map(\.stableIdentifier)) == [
            "simulator-app:11111111-2222-3333-4444-555555555555:com.example.myapp",
            "simulator-app:11111111-2222-3333-4444-555555555555:com.example.myapp.staging",
        ])
    }

    @Test("Without a device directory, IDs don't end in a bare PID that InstanceMerger would strip")
    func missingDeviceDirectoryKeepsDevicesApart() {
        let procs = FixtureBuilder.bootedSimulator(rootPid: 6000).map {
            $0.name == "launchd_sim" ? ProcessSnapshotTestCopy.withArgs($0, ["launchd_sim"]) : $0
        }
        let device = deviceGroup(classifier.classify(procs))
        #expect(device?.stableIdentifier == "simulator:pid-6000")
        #expect(InstanceMerger.appKey(from: device!.stableIdentifier) == "simulator:pid-6000")
    }

    @Test("Device names and bundle info are looked up once, not on every refresh")
    func lookupsAreCached() {
        let calls = Mutex(0)
        let classifier = SimulatorClassifier(
            deviceNameResolver: { _ in calls.withLock { $0 += 1 }; return "iPhone 17 Pro" },
            bundleInfoResolver: { _ in calls.withLock { $0 += 1 }; return .init(bundleIdentifier: "a", name: "A", icon: nil) }
        )
        let procs = FixtureBuilder.bootedSimulator()
        _ = classifier.classify(procs)
        _ = classifier.classify(procs)
        _ = classifier.classify(procs)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test("Only app groups are bulk-killable")
    func onlyAppGroupsKillable() {
        let result = classifier.classify(FixtureBuilder.bootedSimulator() + FixtureBuilder.simulatorHostServices())
        for group in result.groups {
            #expect(ProcessActions.isGroupKillable(group) == SimulatorClassifier.isAppGroup(group), "\(group.name)")
        }
        #expect(appGroups(result).allSatisfy(ProcessActions.isGroupKillable))
        #expect(result.groups.contains { !ProcessActions.isGroupKillable($0) })
    }

    @Test("Falls back to the runtime name when the device name can't be read")
    func unknownDeviceName() {
        let classifier = SimulatorClassifier(deviceNameResolver: { _ in nil })
        let result = classifier.classify(FixtureBuilder.bootedSimulator())
        #expect(deviceGroup(result)?.name == "iOS 26.0 Simulator")
        #expect(appGroups(result).map(\.name) == ["MyApp"])
    }

    // MARK: - Orphans and host services

    @Test("Runtime processes without a visible launchd_sim still group together")
    func orphanRuntimeProcesses() {
        let procs = FixtureBuilder.bootedSimulator().filter { $0.name != "launchd_sim" }
        let result = classifier.classify(procs)

        // assetsd's path is a plain /usr/libexec path and its parent chain is broken,
        // so it's left for SystemServices; the rest are recognizably simulator paths.
        #expect(result.groups.contains { $0.stableIdentifier == "simulator:runtime" })
        #expect(!result.claimedPIDs.contains(6003))
        #expect(result.claimedPIDs.contains(6001))
    }

    @Test("An app whose launchd_sim isn't visible keeps its own group, keyed by the device in its path")
    func orphanAppKeepsOwnGroup() {
        let procs = FixtureBuilder.bootedSimulator().filter { $0.name != "launchd_sim" }
        let result = classifier.classify(procs)
        let apps = appGroups(result)

        #expect(apps.map(\.name) == ["MyApp (iPhone 17 Pro)"])
        #expect(apps.first?.stableIdentifier == "simulator-app:11111111-2222-3333-4444-555555555555:MyApp")
        let runtime = result.groups.first { $0.stableIdentifier == "simulator:runtime" }
        #expect(runtime?.processes.contains { $0.name == "MyApp" } == false)
    }

    @Test("CoreSimulator services and Simulator.app form a host group")
    func hostServices() {
        let result = classifier.classify(FixtureBuilder.simulatorHostServices())
        #expect(result.groups.map(\.stableIdentifier) == ["simulator:host"])
        #expect(result.claimedPIDs == [6900, 6901])
    }

    @Test("Ignores non-simulator processes")
    func ignoresOthers() {
        let result = classifier.classify(FixtureBuilder.devWorkstation())
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    @Test("Registry routes simulator processes away from System and Generic")
    func registryOrdering() {
        let procs = FixtureBuilder.devWorkstation() + FixtureBuilder.bootedSimulator()
        let groups = ClassifierRegistry.default.classify(snapshots: procs)
        let simGroups = groups.filter { $0.classifierName == "Simulator" }

        #expect(simGroups.count == 2)
        #expect(simGroups.reduce(0) { $0 + $1.processCount } == 5)
        #expect(!groups.contains { $0.classifierName == "Generic" && $0.name == "SiriAUSP" })
    }

    // MARK: - Path parsing

    @Test("Extracts the device directory from launchd_sim's arguments")
    func deviceDirectoryFromArgs() {
        let args = ["launchd_sim", "\(FixtureBuilder.simDeviceDirectory)/data/var/run/launchd_bootstrap.plist"]
        #expect(SimulatorClassifier.deviceDirectory(fromArgs: args) == FixtureBuilder.simDeviceDirectory)
        #expect(SimulatorClassifier.deviceDirectory(fromArgs: ["launchd_sim"]) == nil)
    }

    @Test("Extracts the runtime name from a RuntimeRoot path")
    func runtimeNameFromPath() {
        #expect(SimulatorClassifier.runtimeName(fromPath: "\(FixtureBuilder.simRuntimeRoot)/usr/libexec/foo") == "iOS 26.0")
        #expect(SimulatorClassifier.runtimeName(fromPath: "/usr/libexec/foo") == nil)
    }

    @Test("Picks an SF Symbol per device family")
    func deviceSymbols() {
        #expect(SimulatorClassifier.symbolName(forDevice: "iPad Pro 13-inch (M5)") == "ipad")
        #expect(SimulatorClassifier.symbolName(forDevice: "Apple Watch Series 11 (46mm)") == "applewatch")
        #expect(SimulatorClassifier.symbolName(forDevice: "iPhone 17 Pro") == "iphone")
        #expect(SimulatorClassifier.symbolName(forDevice: nil) == "iphone")
    }
}

/// Field-for-field copies of a fixture snapshot with one field changed.
private enum ProcessSnapshotTestCopy {
    static func reparent(_ p: ProcessSnapshot, to parentPid: Int32) -> ProcessSnapshot {
        copy(p, args: p.commandLineArgs, parentPid: parentPid)
    }

    static func withArgs(_ p: ProcessSnapshot, _ args: [String]) -> ProcessSnapshot {
        copy(p, args: args, parentPid: p.parentPid)
    }

    private static func copy(_ p: ProcessSnapshot, args: [String], parentPid: Int32) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: p.pid, name: p.name, path: p.path, commandLineArgs: args,
            parentPid: parentPid, responsiblePid: p.responsiblePid,
            bundleIdentifier: p.bundleIdentifier, workingDirectory: p.workingDirectory,
            physFootprint: p.physFootprint, residentSize: p.residentSize, sharedMemory: p.sharedMemory,
            startTimeSec: p.startTimeSec, startTimeUsec: p.startTimeUsec,
            firstSeen: p.firstSeen, lastSeen: p.lastSeen, exitedAt: p.exitedAt,
            isPartialData: p.isPartialData
        )
    }
}
