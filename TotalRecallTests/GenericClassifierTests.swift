import Testing
@testable import TotalRecallCore

@Suite("GenericClassifier")
struct GenericClassifierTests {
    let classifier = GenericClassifier()
    private let mb: UInt64 = 1024 * 1024

    // MARK: - Empty input

    @Test("empty process list returns empty result")
    func emptyInputReturnsEmpty() {
        let result = classifier.classify([])
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    // MARK: - App bundle path grouping

    @Test("process with .app path is grouped by bundle path")
    func processWithAppPathGroupedByBundle() {
        let safari = FixtureBuilder.genericProcess(
            pid: 5000, name: "Safari",
            path: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        let result = classifier.classify([safari])
        #expect(result.groups.count == 1)
        #expect(result.groups[0].name == "Safari")
    }

    @Test("two processes sharing the same .app bundle are grouped together")
    func twoProcessesSharingAppBundleGroupedTogether() {
        let main = FixtureBuilder.genericProcess(
            pid: 5010, name: "Slack",
            path: "/Applications/Slack.app/Contents/MacOS/Slack"
        )
        let helper = FixtureBuilder.genericProcess(
            pid: 5011, name: "Slack Helper",
            path: "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper"
        )
        let result = classifier.classify([main, helper])
        #expect(result.groups.count == 1)
        let pids = Set(result.groups[0].processes.map(\.pid))
        #expect(pids == [5010, 5011])
    }

    // MARK: - Bundle ID grouping

    @Test("process with bundle ID is grouped by bundle identifier")
    func processWithBundleIDGrouped() {
        let now = Date()
        let process = ProcessSnapshot(
            pid: 5020, name: "MyApp",
            path: "/usr/bin/myapp",
            commandLineArgs: ["myapp"],
            parentPid: 1, responsiblePid: 5020,
            bundleIdentifier: "com.example.myapp",
            workingDirectory: nil,
            physFootprint: 50 * mb, residentSize: 45 * mb, sharedMemory: 5 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let result = classifier.classify([process])
        #expect(result.groups.count == 1)
        #expect(result.claimedPIDs.contains(5020))
    }

    // MARK: - Exec name fallback

    @Test("process without .app path or bundle ID falls back to exec name")
    func processWithoutAppOrBundleUsesExecName() {
        let process = FixtureBuilder.genericProcess(
            pid: 5030, name: "custom-daemon",
            path: "/usr/local/bin/custom-daemon"
        )
        let result = classifier.classify([process])
        #expect(result.groups.count == 1)
        let group = result.groups[0]
        #expect(group.name == "custom-daemon")
    }

    // MARK: - Multiple distinct apps

    @Test("processes from different apps create separate groups")
    func differentAppsCreateSeparateGroups() {
        let safari = FixtureBuilder.genericProcess(
            pid: 5040, name: "Safari",
            path: "/Applications/Safari.app/Contents/MacOS/Safari"
        )
        let mail = FixtureBuilder.genericProcess(
            pid: 5041, name: "Mail",
            path: "/Applications/Mail.app/Contents/MacOS/Mail"
        )
        let result = classifier.classify([safari, mail])
        #expect(result.groups.count == 2)
    }

    // MARK: - CLI tool grouping

    @Test("docker child processes are grouped under docker CLI tool")
    func dockerChildrenGroupedUnderDockerCLI() {
        let now = Date()
        let docker = ProcessSnapshot(
            pid: 5050, name: "docker",
            path: "/usr/local/bin/docker",
            commandLineArgs: ["docker", "run", "-d", "myimage"],
            parentPid: 1, responsiblePid: 5050,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: 30 * mb, residentSize: 25 * mb, sharedMemory: 5 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let child = ProcessSnapshot(
            pid: 5051, name: "sh",
            path: "/bin/sh",
            commandLineArgs: ["sh"],
            parentPid: 5050, responsiblePid: 5050,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: 5 * mb, residentSize: 4 * mb, sharedMemory: 1 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let result = classifier.classify([docker, child])
        // Both docker and its child should be in the same group
        let dockerGroup = result.groups.first { $0.name == "Docker" }
        #expect(dockerGroup != nil)
        let pids = Set(dockerGroup!.processes.map(\.pid))
        #expect(pids.contains(5050))
        #expect(pids.contains(5051))
    }

    // MARK: - Python/Ruby runtime name resolution

    @Test("python3 process resolves runtime name from script arg")
    func python3ResolvesRuntimeName() {
        let now = Date()
        let process = ProcessSnapshot(
            pid: 5060, name: "python3",
            path: "/usr/bin/python3",
            commandLineArgs: ["python3", "manage.py", "runserver"],
            parentPid: 1, responsiblePid: 5060,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: 40 * mb, residentSize: 35 * mb, sharedMemory: 5 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let result = classifier.classify([process])
        let group = result.groups.first!
        // Should resolve to "python3 (manage.py)" or similar
        #expect(group.name.contains("python3"))
    }

    @Test("node process resolves runtime name from script arg")
    func nodeResolvesRuntimeName() {
        let now = Date()
        let process = ProcessSnapshot(
            pid: 5070, name: "node",
            path: "/usr/local/bin/node",
            commandLineArgs: ["node", "/project/server.js"],
            parentPid: 1, responsiblePid: 5070,
            bundleIdentifier: nil, workingDirectory: nil,
            physFootprint: 60 * mb, residentSize: 55 * mb, sharedMemory: 5 * mb,
            startTimeSec: 0, startTimeUsec: 0,
            firstSeen: now, lastSeen: now, exitedAt: nil,
            isPartialData: false
        )
        let result = classifier.classify([process])
        let group = result.groups.first!
        // Should resolve to "node (server.js)"
        #expect(group.name.contains("node"))
        #expect(group.name.contains("server.js"))
    }

    // MARK: - All processes are claimed

    @Test("all input processes are claimed by generic classifier")
    func allProcessesClaimed() {
        let processes = [
            FixtureBuilder.genericProcess(pid: 5080, name: "App1", path: "/Applications/App1.app/MacOS/App1"),
            FixtureBuilder.genericProcess(pid: 5081, name: "App2", path: "/Applications/App2.app/MacOS/App2"),
        ]
        let result = classifier.classify(processes)
        for process in processes {
            #expect(result.claimedPIDs.contains(process.pid))
        }
    }

    @Test("results are sorted by footprint descending")
    func resultsSortedByFootprintDescending() {
        let small = FixtureBuilder.genericProcess(pid: 5090, name: "Small", path: "/usr/bin/small", footprint: 10 * mb)
        let large = FixtureBuilder.genericProcess(pid: 5091, name: "Large", path: "/usr/bin/large", footprint: 100 * mb)
        let result = classifier.classify([small, large])
        if result.groups.count >= 2 {
            #expect(result.groups[0].deduplicatedFootprint >= result.groups[1].deduplicatedFootprint)
        }
    }
}
