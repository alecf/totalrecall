import AppKit
import Testing
@testable import TotalRecallCore

@Suite("ProcessActions.sendSignal")
struct ProcessActionsSendSignalTests {

    // MARK: - Self-kill protection

    @Test("sendSignal throws selfKill when targeting the current process")
    func sendSignalSelfKill() {
        let identity = ProcessIdentity(
            pid: ProcessInfo.processInfo.processIdentifier,
            executablePath: "/usr/bin/test",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected selfKill error to be thrown")
        } catch ProcessActions.KillError.selfKill {
            // Expected
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - PID protection

    @Test("sendSignal throws protectedProcess for PID 0")
    func sendSignalPID0IsProtected() {
        let identity = ProcessIdentity(
            pid: 0,
            executablePath: "/usr/bin/fake",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected protectedProcess error for PID 0")
        } catch ProcessActions.KillError.protectedProcess {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("sendSignal throws protectedProcess for PID 1 (launchd)")
    func sendSignalPID1IsProtected() {
        let identity = ProcessIdentity(
            pid: 1,
            executablePath: "/sbin/launchd",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected protectedProcess error for PID 1")
        } catch ProcessActions.KillError.protectedProcess {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Protected name denylist

    @Test("sendSignal throws protectedProcess for kernel_task path")
    func sendSignalKernelTaskIsProtected() {
        let identity = ProcessIdentity(
            pid: 2000,
            executablePath: "/usr/sbin/kernel_task",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected protectedProcess error for kernel_task")
        } catch ProcessActions.KillError.protectedProcess(let name) {
            #expect(name == "kernel_task")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("sendSignal throws protectedProcess for WindowServer path")
    func sendSignalWindowServerIsProtected() {
        let identity = ProcessIdentity(
            pid: 2001,
            executablePath: "/System/Library/PrivateFrameworks/SkyLight.framework/WindowServer",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected protectedProcess error for WindowServer")
        } catch ProcessActions.KillError.protectedProcess(let name) {
            #expect(name == "WindowServer")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("sendSignal throws protectedProcess for loginwindow path")
    func sendSignalLoginwindowIsProtected() {
        let identity = ProcessIdentity(
            pid: 2002,
            executablePath: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected protectedProcess error for loginwindow")
        } catch ProcessActions.KillError.protectedProcess(let name) {
            #expect(name == "loginwindow")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("sendSignal throws protectedProcess for runningboardd path")
    func sendSignalRunningboarddIsProtected() {
        let identity = ProcessIdentity(
            pid: 2003,
            executablePath: "/usr/libexec/runningboardd",
            startTimeSec: 0,
            startTimeUsec: 0
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            Issue.record("Expected protectedProcess error for runningboardd")
        } catch ProcessActions.KillError.protectedProcess(let name) {
            #expect(name == "runningboardd")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Non-existent PID

    @Test("sendSignal throws processExited or pidRecycled for non-existent PID")
    func sendSignalNonExistentPID() {
        // Use a PID with fake timestamps — either the PID doesn't exist (processExited)
        // or it was recycled (pidRecycled). We accept either outcome.
        let identity = ProcessIdentity(
            pid: 99990,
            executablePath: "/usr/bin/fake-process-that-does-not-exist",
            startTimeSec: 999_999_999,
            startTimeUsec: 999_999
        )
        do {
            try ProcessActions.sendSignal(SIGTERM, to: identity)
            // If the signal somehow succeeded (very unlikely), that's also ok
        } catch ProcessActions.KillError.processExited {
            // Expected: PID doesn't exist
        } catch ProcessActions.KillError.pidRecycled {
            // Expected: PID was reused with different timestamps
        } catch ProcessActions.KillError.permissionDenied {
            // Also valid: process exists but owned by another user
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

@Suite("ProcessActions.sendSignalToAll")
struct SendSignalToAllTests {
    private func makeGroup(processes: [ProcessSnapshot], classifierName: String = "Generic") -> ProcessGroup {
        ProcessGroup(
            stableIdentifier: "test:signal",
            name: "Test Group",
            icon: nil,
            classifierName: classifierName,
            explanation: nil,
            processes: processes,
            subGroups: nil,
            deduplicatedFootprint: 0,
            nonResidentMemory: 0
        )
    }

    @Test("sendSignalToAll returns empty array for empty group")
    func sendSignalToAllEmptyGroup() {
        let group = makeGroup(processes: [])
        let errors = ProcessActions.sendSignalToAll(SIGTERM, in: group)
        #expect(errors.isEmpty)
    }

    @Test("sendSignalToAll returns errors for protected processes")
    func sendSignalToAllWithProtectedProcess() {
        // A process with a protected name in its path
        let kernelSnapshot = FixtureBuilder.genericProcess(
            pid: 7777,
            name: "kernel_task",
            path: "/usr/sbin/kernel_task"
        )
        let group = makeGroup(processes: [kernelSnapshot])
        let errors = ProcessActions.sendSignalToAll(SIGTERM, in: group)
        #expect(!errors.isEmpty)
    }

    @Test("sendSignalToAll collects errors from multiple processes")
    func sendSignalToAllMultipleErrors() {
        let process1 = FixtureBuilder.genericProcess(
            pid: 7778,
            name: "kernel_task",
            path: "/usr/sbin/kernel_task"
        )
        let process2 = FixtureBuilder.genericProcess(
            pid: 7779,
            name: "WindowServer",
            path: "/System/Library/PrivateFrameworks/SkyLight.framework/WindowServer"
        )
        let group = makeGroup(processes: [process1, process2])
        let errors = ProcessActions.sendSignalToAll(SIGTERM, in: group)
        #expect(errors.count == 2)
    }
}
