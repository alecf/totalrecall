import AppKit
import Testing
@testable import TotalRecallCore

@Suite("SystemServicesClassifier")
struct SystemServicesClassifierTests {
    let classifier = SystemServicesClassifier()
    private let mb: UInt64 = 1024 * 1024

    // MARK: - displayName

    @Test("displayName returns the correct name for WindowServer")
    func displayNameWindowServer() {
        #expect(SystemServicesClassifier.displayName(for: "WindowServer") == "WindowServer")
    }

    @Test("displayName returns the correct name for mds_stores")
    func displayNameMdsStores() {
        #expect(SystemServicesClassifier.displayName(for: "mds_stores") == "Spotlight")
    }

    @Test("displayName returns the correct name for kernel_task")
    func displayNameKernelTask() {
        #expect(SystemServicesClassifier.displayName(for: "kernel_task") == "Kernel")
    }

    @Test("displayName returns the correct name for Finder")
    func displayNameFinder() {
        #expect(SystemServicesClassifier.displayName(for: "Finder") == "Finder")
    }

    @Test("displayName returns the correct name for launchd")
    func displayNameLaunchd() {
        #expect(SystemServicesClassifier.displayName(for: "launchd") == "launchd")
    }

    @Test("displayName returns nil for unknown process")
    func displayNameUnknown() {
        #expect(SystemServicesClassifier.displayName(for: "nonexistent_proc_xyz") == nil)
    }

    @Test("displayName returns nil for empty string")
    func displayNameEmpty() {
        #expect(SystemServicesClassifier.displayName(for: "") == nil)
    }

    // MARK: - explanation (additional cases)

    @Test("explanation returns non-empty string for known services")
    func explanationKnownServices() {
        let knownNames = ["kernel_task", "WindowServer", "mds_stores", "launchd",
                          "coreaudiod", "bluetoothd", "Dock", "Finder"]
        for name in knownNames {
            let exp = SystemServicesClassifier.explanation(for: name)
            #expect(exp != nil, "Expected explanation for \(name)")
            #expect(!(exp ?? "").isEmpty)
        }
    }

    @Test("explanation returns nil for unknown process names")
    func explanationUnknown() {
        #expect(SystemServicesClassifier.explanation(for: "my-custom-daemon") == nil)
    }

    // MARK: - classify by known service name

    @Test("classify groups kernel_task and WindowServer together")
    func classifyKernelAndWindowServer() {
        let processes = [FixtureBuilder.kernelTask(), FixtureBuilder.windowServer()]
        let result = classifier.classify(processes)
        #expect(result.groups.count == 1)
        #expect(result.groups.first?.name == "System Services")
        #expect(result.claimedPIDs.count == 2)
    }

    @Test("classify returns empty for non-system processes")
    func classifyNonSystemProcesses() {
        let processes = [
            FixtureBuilder.genericProcess(pid: 9000, name: "MyApp", path: "/Applications/MyApp.app/Contents/MacOS/MyApp"),
        ]
        let result = classifier.classify(processes)
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    @Test("classify returns empty for empty input")
    func classifyEmptyInput() {
        let result = classifier.classify([])
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    // MARK: - classify by system daemon paths

    @Test("classify claims processes from /usr/libexec/ path")
    func classifyFromUsrLibexec() {
        let process = makeSnapshot(
            pid: 8001, name: "notkhald", path: "/usr/libexec/notkhald",
            footprint: 5 * mb
        )
        let result = classifier.classify([process])
        #expect(!result.groups.isEmpty)
        #expect(result.claimedPIDs.contains(8001))
    }

    @Test("classify claims processes from /usr/sbin/ path")
    func classifyFromUsrSbin() {
        let process = makeSnapshot(
            pid: 8002, name: "sshd", path: "/usr/sbin/sshd",
            footprint: 3 * mb
        )
        let result = classifier.classify([process])
        #expect(!result.groups.isEmpty)
        #expect(result.claimedPIDs.contains(8002))
    }

    @Test("classify claims processes from /System/Library/CoreServices/ path")
    func classifyFromCoreServices() {
        let process = makeSnapshot(
            pid: 8003, name: "cfprefsd", path: "/System/Library/CoreServices/cfprefsd",
            footprint: 8 * mb
        )
        let result = classifier.classify([process])
        #expect(!result.groups.isEmpty)
        #expect(result.claimedPIDs.contains(8003))
    }

    @Test("classify claims processes from /System/Library/PrivateFrameworks/ path")
    func classifyFromPrivateFrameworks() {
        let process = makeSnapshot(
            pid: 8004, name: "some-daemon",
            path: "/System/Library/PrivateFrameworks/SomeFramework.framework/Versions/A/Resources/some-daemon",
            footprint: 10 * mb
        )
        let result = classifier.classify([process])
        #expect(!result.groups.isEmpty)
        #expect(result.claimedPIDs.contains(8004))
    }

    @Test("classify claims small processes from /System/Library/Frameworks/ path")
    func classifySmallFromFrameworks() {
        let process = makeSnapshot(
            pid: 8005, name: "WebKit.WebContent",
            path: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
            footprint: 20 * mb  // < 50 MB → eligible
        )
        let result = classifier.classify([process])
        #expect(!result.groups.isEmpty)
        #expect(result.claimedPIDs.contains(8005))
    }

    @Test("classify does NOT claim large XPC services from framework paths")
    func classifyDoesNotClaimLargeXPCService() {
        let process = makeSnapshot(
            pid: 8006, name: "Virtualization",
            path: "/System/Library/Frameworks/Virtualization.framework/XPCServices/VirtualizationService.xpc/Contents/MacOS/VirtualizationService",
            footprint: 200 * mb  // > 50 MB → excluded
        )
        let result = classifier.classify([process])
        // A large XPC service shouldn't be claimed by SystemServicesClassifier
        // (unless it's in knownServices by name — it's not)
        #expect(!result.claimedPIDs.contains(8006))
    }

    @Test("classify does NOT claim user-facing apps from /System/Applications/")
    func classifyDoesNotClaimSystemApps() {
        let process = makeSnapshot(
            pid: 8007, name: "Calculator",
            path: "/System/Applications/Calculator.app/Contents/MacOS/Calculator",
            footprint: 30 * mb
        )
        let result = classifier.classify([process])
        #expect(!result.claimedPIDs.contains(8007))
    }

    @Test("classify groups all claimed processes into a single System Services group")
    func classifyGroupsAllIntoOneGroup() {
        let processes = [
            FixtureBuilder.kernelTask(),
            FixtureBuilder.windowServer(),
            FixtureBuilder.mdsStores(),
            makeSnapshot(pid: 8008, name: "sshd", path: "/usr/sbin/sshd", footprint: 2 * mb),
        ]
        let result = classifier.classify(processes)
        #expect(result.groups.count == 1)
        let group = result.groups[0]
        #expect(group.stableIdentifier == "system")
        #expect(group.classifierName == "System")
    }

    // MARK: - Helpers

    private func makeSnapshot(pid: Int32, name: String, path: String, footprint: UInt64) -> ProcessSnapshot {
        let now = Date()
        return ProcessSnapshot(
            pid: pid, name: name, path: path,
            commandLineArgs: [name],
            parentPid: 1, responsiblePid: pid,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: footprint,
            residentSize: footprint > 1024 ? footprint - 1024 : 0,
            sharedMemory: 0,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
    }
}
