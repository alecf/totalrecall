import Testing
import Foundation
@testable import TotalRecallCore

@Suite("ChromeClassifier")
struct ChromeClassifierTests {
    let classifier = ChromeClassifier()

    // MARK: - Empty input

    @Test("returns empty result for empty process list")
    func emptyInputReturnsEmpty() {
        let result = classifier.classify([])
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    @Test("returns empty result for non-Chrome processes")
    func nonChromeProcessReturnsEmpty() {
        let process = FixtureBuilder.vscodeMain()
        let result = classifier.classify([process])
        #expect(result.groups.isEmpty)
    }

    // MARK: - Single Chrome main process

    @Test("single Chrome main process creates one group with no subGroups")
    func singleChromeMainCreatesGroupWithoutSubGroups() {
        let result = classifier.classify([FixtureBuilder.chromeMain()])
        #expect(result.groups.count == 1)
        let group = result.groups[0]
        #expect(group.name == "Google Chrome")
        #expect(group.classifierName == "Chrome")
        #expect(group.stableIdentifier == "chrome")
        #expect(group.subGroups == nil)
    }

    @Test("single Chrome main process claims its PID")
    func singleChromeMainClaimsPID() {
        let result = classifier.classify([FixtureBuilder.chromeMain()])
        #expect(result.claimedPIDs.contains(1000))
    }

    // MARK: - GPU process goes to unprofiledProcesses

    @Test("GPU process with no profile directory is in unprofiledProcesses not subGroups")
    func gpuProcessIsUnprofiled() {
        let processes = [FixtureBuilder.chromeMain(), FixtureBuilder.chromeGPU()]
        let result = classifier.classify(processes)
        let group = result.groups.first!
        // GPU has no profile dir → unprofiledProcesses
        #expect(group.processes.contains { $0.pid == 1010 })
        // No subGroups since renderers haven't been added
        #expect(group.subGroups == nil || group.subGroups!.isEmpty)
    }

    // MARK: - Renderer with profile directory creates subGroups

    @Test("renderer processes create profile sub-groups")
    func renderersCreateProfileSubGroups() {
        let processes = [
            FixtureBuilder.chromeMain(),
            FixtureBuilder.chromeRenderer(pid: 1001, profile: "Default"),
            FixtureBuilder.chromeRenderer(pid: 1002, profile: "Profile 1"),
        ]
        let result = classifier.classify(processes)
        let group = result.groups.first!
        let subGroups = group.subGroups
        #expect(subGroups != nil)
        #expect(subGroups!.count == 2)
    }

    @Test("profile sub-groups are sorted alphabetically by profile directory")
    func profileSubGroupsSortedAlphabetically() {
        let processes = [
            FixtureBuilder.chromeMain(),
            FixtureBuilder.chromeRenderer(pid: 1001, profile: "Profile 1"),
            FixtureBuilder.chromeRenderer(pid: 1002, profile: "Default"),
        ]
        let result = classifier.classify(processes)
        let subGroups = result.groups.first!.subGroups!
        // Sorted alphabetically: "Default" < "Profile 1"
        #expect(subGroups[0].stableIdentifier == "chrome:Default")
        #expect(subGroups[1].stableIdentifier == "chrome:Profile 1")
    }

    // MARK: - Bundle ID detection

    @Test("Chrome process detected by bundle ID when path doesn't contain 'Google Chrome'")
    func chromeDetectedByBundleID() {
        let process = ProcessSnapshot(
            pid: 9999,
            name: "Google Chrome",
            path: "/private/var/folders/some/path/Google Chrome",
            commandLineArgs: [],
            parentPid: 1,
            responsiblePid: 9999,
            bundleIdentifier: "com.google.Chrome",
            workingDirectory: nil,
            physFootprint: 100 * 1024 * 1024,
            residentSize: 80 * 1024 * 1024,
            sharedMemory: 0,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: Date(), lastSeen: Date(), exitedAt: nil,
            isPartialData: false
        )
        let result = classifier.classify([process])
        #expect(!result.groups.isEmpty)
        #expect(result.claimedPIDs.contains(9999))
    }

    // MARK: - Profile name humanization

    @Test("Default profile name is humanized to 'Default Profile'")
    func defaultProfileHumanized() {
        let processes = [
            FixtureBuilder.chromeMain(),
            FixtureBuilder.chromeRenderer(pid: 1001, profile: "Default"),
        ]
        let result = classifier.classify(processes)
        let defaultSubGroup = result.groups.first!.subGroups?.first { $0.stableIdentifier == "chrome:Default" }
        #expect(defaultSubGroup?.name == "Default Profile")
    }

    @Test("Profile N names are kept as-is")
    func profileNNameKeptAsIs() {
        let processes = [
            FixtureBuilder.chromeMain(),
            FixtureBuilder.chromeRenderer(pid: 1001, profile: "Profile 3"),
        ]
        let result = classifier.classify(processes)
        let subGroup = result.groups.first!.subGroups?.first { $0.stableIdentifier == "chrome:Profile 3" }
        #expect(subGroup?.name == "Profile 3")
    }

    // MARK: - All processes claimed

    @Test("all Chrome processes are claimed by the classifier")
    func allChromeProcessesAreClaimed() {
        let processes = [
            FixtureBuilder.chromeMain(),
            FixtureBuilder.chromeGPU(),
            FixtureBuilder.chromeRenderer(pid: 1001, profile: "Default"),
            FixtureBuilder.chromeRenderer(pid: 1002, profile: "Default"),
        ]
        let result = classifier.classify(processes)
        let claimedPIDs = result.claimedPIDs
        for process in processes {
            #expect(claimedPIDs.contains(process.pid))
        }
    }
}
