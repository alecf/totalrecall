import AppKit
import Testing
@testable import TotalRecallCore

@Suite("ProcessActions.isGroupKillable")
struct ProcessActionsKillableTests {
    private func makeGroup(classifierName: String) -> ProcessGroup {
        ProcessGroup(
            stableIdentifier: "test:\(classifierName)",
            name: classifierName,
            icon: nil,
            classifierName: classifierName,
            explanation: nil,
            processes: [],
            subGroups: nil,
            deduplicatedFootprint: 0,
            nonResidentMemory: 0
        )
    }

    @Test("System group is not killable")
    func systemGroupNotKillable() {
        #expect(ProcessActions.isGroupKillable(makeGroup(classifierName: "System")) == false)
    }

    @Test("Chrome group is killable")
    func chromeGroupIsKillable() {
        #expect(ProcessActions.isGroupKillable(makeGroup(classifierName: "Chrome")) == true)
    }

    @Test("Electron group is killable")
    func electronGroupIsKillable() {
        #expect(ProcessActions.isGroupKillable(makeGroup(classifierName: "Electron")) == true)
    }

    @Test("Generic group is killable")
    func genericGroupIsKillable() {
        #expect(ProcessActions.isGroupKillable(makeGroup(classifierName: "Generic")) == true)
    }

    @Test("ClaudeCode group is killable")
    func claudeCodeGroupIsKillable() {
        #expect(ProcessActions.isGroupKillable(makeGroup(classifierName: "ClaudeCode")) == true)
    }
}

@Suite("ProcessActions.KillError descriptions")
struct KillErrorDescriptionTests {
    @Test("processExited mentions exiting")
    func processExitedDescription() {
        let error = ProcessActions.KillError.processExited
        let desc = error.errorDescription ?? ""
        #expect(!desc.isEmpty)
        #expect(desc.localizedCaseInsensitiveContains("exit"))
    }

    @Test("pidRecycled has a non-empty description")
    func pidRecycledDescription() {
        let error = ProcessActions.KillError.pidRecycled
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("permissionDenied mentions permission")
    func permissionDeniedDescription() {
        let error = ProcessActions.KillError.permissionDenied
        let desc = error.errorDescription ?? ""
        #expect(!desc.isEmpty)
        #expect(desc.localizedCaseInsensitiveContains("ermission"))
    }

    @Test("protectedProcess includes the process name")
    func protectedProcessIncludesName() {
        let error = ProcessActions.KillError.protectedProcess("kernel_task")
        #expect(error.errorDescription?.contains("kernel_task") == true)
    }

    @Test("selfKill has a non-empty description")
    func selfKillDescription() {
        let error = ProcessActions.KillError.selfKill
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("unknownError includes the numeric error code")
    func unknownErrorIncludesCode() {
        let error = ProcessActions.KillError.unknownError(42)
        #expect(error.errorDescription?.contains("42") == true)
    }
}
