import Testing
import Foundation
@testable import TotalRecallCore

@Suite("ClaudeCodeClassifier - additional coverage")
struct ClaudeCodeClassifierAdditionalTests {
    let classifier = ClaudeCodeClassifier()

    // MARK: - Session labels

    @Test("session without working directory uses PID as label")
    func sessionWithoutWorkingDirectoryUsesPIDLabel() throws {
        let session = makeClaudeSession(pid: 6100, workingDirectory: nil)
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        #expect(group.explanation == "Session (PID 6100)")
    }

    @Test("session with root working directory uses PID as label")
    func sessionWithRootWorkingDirectoryUsesPIDLabel() throws {
        let session = makeClaudeSession(pid: 6200, workingDirectory: "/")
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        #expect(group.explanation == "Session (PID 6200)")
    }

    @Test("session with --resume flag appends '(resumed)' to label")
    func sessionWithResumeFlagHasResumedLabel() throws {
        let session = makeClaudeSessionWithResume(pid: 6300, workingDirectory: "/Users/dev/myproject")
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        // Label should contain both "in myproject" and "(resumed)"
        #expect(group.explanation?.contains("myproject") == true)
        #expect(group.explanation?.contains("(resumed)") == true)
    }

    @Test("session with --resume and no working directory label uses only '(resumed)'")
    func sessionWithResumeNoWorkingDirectoryLabel() throws {
        let session = makeClaudeSessionWithResume(pid: 6400, workingDirectory: nil)
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        #expect(group.explanation == "(resumed)")
    }

    // MARK: - Multiple sessions

    @Test("two Claude Code sessions create two separate groups")
    func twoSessionsCreateTwoGroups() {
        let session1 = FixtureBuilder.claudeCodeSession(rootPid: 6500, workingDirectory: "/Users/dev/project1")
        let session2 = FixtureBuilder.claudeCodeSession(rootPid: 6600, workingDirectory: "/Users/dev/project2")
        let result = classifier.classify(session1 + session2)
        #expect(result.groups.count == 2)
    }

    @Test("multiple sessions are each separate stable identifiers")
    func multipleSessionsHaveDifferentStableIDs() {
        let session1 = FixtureBuilder.claudeCodeSession(rootPid: 6700, workingDirectory: "/project1")
        let session2 = FixtureBuilder.claudeCodeSession(rootPid: 6800, workingDirectory: "/project2")
        let result = classifier.classify(session1 + session2)
        let ids = result.groups.map(\.stableIdentifier)
        #expect(ids.count == Set(ids).count)  // All unique
    }

    // MARK: - Non-Claude processes

    @Test("non-claude process returns empty result")
    func nonClaudeProcessReturnsEmpty() {
        let processes = [FixtureBuilder.vscodeMain()]
        let result = classifier.classify(processes)
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    @Test("empty process list returns empty result")
    func emptyInputReturnsEmpty() {
        let result = classifier.classify([])
        #expect(result.groups.isEmpty)
        #expect(result.claimedPIDs.isEmpty)
    }

    // MARK: - stream-json exclusion as interactive root

    @Test("stream-json claude invocation is not treated as an interactive root session")
    func streamJSONIsNotInteractiveRoot() {
        let bridge = FixtureBuilder.claudeAgentStreamJSONBridge()
        let result = classifier.classify(bridge)
        // The stream-json subprocess should NOT become a top-level Claude Code group
        #expect(result.groups.isEmpty)
    }

    // MARK: - Descendants included

    @Test("all descendants of a Claude Code root are included in the group")
    func descendantsIncludedInGroup() throws {
        let session = FixtureBuilder.claudeCodeSession(rootPid: 6900)
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        // Both the root claude and the MCP child node should be in the group
        #expect(group.processes.count == 2)
    }

    @Test("Claude Code group name is always 'Claude Code'")
    func groupNameIsAlwaysClaudeCode() throws {
        let session = FixtureBuilder.claudeCodeSession(rootPid: 7000)
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        #expect(group.name == "Claude Code")
    }

    @Test("Claude Code group classifierName is 'Claude Code'")
    func classifierNameIsClaudeCode() throws {
        let session = FixtureBuilder.claudeCodeSession(rootPid: 7100)
        let result = classifier.classify(session)
        let group = try #require(result.groups.first)
        #expect(group.classifierName == "Claude Code")
    }

    // MARK: - Helpers

    private func makeClaudeSession(pid: Int32, workingDirectory: String?) -> [ProcessSnapshot] {
        let now = Date()
        return [
            ProcessSnapshot(
                pid: pid,
                name: "claude",
                path: "/Users/dev/.local/bin/claude",
                commandLineArgs: ["claude"],
                parentPid: 1,
                responsiblePid: pid,
                bundleIdentifier: nil,
                workingDirectory: workingDirectory,
                physFootprint: 80 * 1024 * 1024,
                residentSize: 70 * 1024 * 1024,
                sharedMemory: 10 * 1024 * 1024,
                startTimeSec: 0, startTimeUsec: 0,
                firstSeen: now, lastSeen: now, exitedAt: nil,
                isPartialData: false
            )
        ]
    }

    private func makeClaudeSessionWithResume(pid: Int32, workingDirectory: String?) -> [ProcessSnapshot] {
        let now = Date()
        return [
            ProcessSnapshot(
                pid: pid,
                name: "claude",
                path: "/Users/dev/.local/bin/claude",
                commandLineArgs: ["claude", "--resume"],
                parentPid: 1,
                responsiblePid: pid,
                bundleIdentifier: nil,
                workingDirectory: workingDirectory,
                physFootprint: 80 * 1024 * 1024,
                residentSize: 70 * 1024 * 1024,
                sharedMemory: 10 * 1024 * 1024,
                startTimeSec: 0, startTimeUsec: 0,
                firstSeen: now, lastSeen: now, exitedAt: nil,
                isPartialData: false
            )
        ]
    }
}
