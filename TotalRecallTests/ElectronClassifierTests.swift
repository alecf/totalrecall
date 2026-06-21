import Testing
@testable import TotalRecallCore

@Suite("ElectronClassifier")
struct ElectronClassifierTests {
    let classifier = ElectronClassifier()
    private let mb: UInt64 = 1024 * 1024

    // MARK: - Empty input

    @Test("returns empty result for empty process list")
    func emptyInputReturnsEmpty() {
        let result = classifier.classify([])
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    @Test("returns empty result for non-Electron processes")
    func nonElectronProcessReturnsEmpty() {
        let result = classifier.classify([FixtureBuilder.chromeMain()])
        #expect(result.groups.isEmpty)
    }

    // MARK: - VS Code grouping

    @Test("VS Code processes are grouped as a single Electron app")
    func vscodeGroupedAsElectronApp() throws {
        let processes = [
            FixtureBuilder.vscodeMain(),
            FixtureBuilder.vscodeRenderer(pid: 2001),
            FixtureBuilder.vscodeRenderer(pid: 2002),
        ]
        let result = classifier.classify(processes)
        #expect(result.groups.count == 1)
        let group = try #require(result.groups.first)
        #expect(group.name == "Visual Studio Code")
        #expect(group.classifierName == "Electron")
        #expect(group.explanation == "Electron app")
    }

    @Test("all VS Code PIDs are claimed by Electron classifier")
    func vscodePIDsAllClaimed() {
        let processes = [
            FixtureBuilder.vscodeMain(),
            FixtureBuilder.vscodeRenderer(pid: 2001),
        ]
        let result = classifier.classify(processes)
        for process in processes {
            #expect(result.claimedPIDs.contains(process.pid))
        }
    }

    @Test("Electron group stable identifier uses lowercased app name")
    func electronGroupStableIdentifier() throws {
        let result = classifier.classify([FixtureBuilder.vscodeMain(), FixtureBuilder.vscodeRenderer()])
        let group = try #require(result.groups.first)
        #expect(group.stableIdentifier == "electron:visual studio code")
    }

    // MARK: - Child process adoption

    @Test("child processes of Electron app main process are included in the group")
    func childProcessesIncluded() {
        let now = Date()
        let main = FixtureBuilder.vscodeMain()

        // A bash shell child of VS Code
        let shell = ProcessSnapshot(
            pid: 2100, name: "bash",
            path: "/bin/bash",
            commandLineArgs: ["bash"],
            parentPid: 2000,  // child of vscodeMain (pid 2000)
            responsiblePid: 2000,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: 5 * mb, residentSize: 4 * mb, sharedMemory: 1 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let result = classifier.classify([main, shell])
        #expect(result.claimedPIDs.contains(2100))
    }

    // MARK: - Multiple Electron apps

    @Test("two different Electron apps create two separate groups")
    func twoElectronAppsCreateSeparateGroups() {
        let now = Date()
        let slack = ProcessSnapshot(
            pid: 3000, name: "Slack",
            path: "/Applications/Slack.app/Contents/Frameworks/Electron Framework.framework/Versions/Current/Helpers/Electron Helper.app/Contents/MacOS/Electron Helper",
            commandLineArgs: ["Electron Helper", "--type=renderer"],
            parentPid: 1, responsiblePid: 3000,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            workingDirectory: nil,
            physFootprint: 200 * mb, residentSize: 180 * mb, sharedMemory: 40 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let vsCode = FixtureBuilder.vscodeMain()

        let result = classifier.classify([slack, vsCode, FixtureBuilder.vscodeRenderer(pid: 2001)])
        // Each app should be its own group
        #expect(result.groups.count == 2)
    }

    // MARK: - Stable identifier

    @Test("Electron group stable identifier is lowercased app name")
    func stableIdentifierIsLowercased() throws {
        let result = classifier.classify([FixtureBuilder.vscodeMain(), FixtureBuilder.vscodeRenderer()])
        let group = try #require(result.groups.first)
        #expect(group.stableIdentifier == "electron:visual studio code")
        #expect(group.stableIdentifier == group.stableIdentifier.lowercased())
    }
}
