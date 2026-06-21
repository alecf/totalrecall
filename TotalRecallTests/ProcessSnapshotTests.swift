import Foundation
import Testing
@testable import TotalRecallCore

@Suite("ProcessSnapshot")
struct ProcessSnapshotTests {
    private let now = Date()

    private func snapshot(
        pid: Int32 = 42,
        path: String = "/usr/bin/test",
        footprint: UInt64,
        resident: UInt64,
        startTimeSec: UInt64 = 1_000_000,
        startTimeUsec: UInt64 = 500
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            name: "test",
            path: path,
            commandLineArgs: [],
            parentPid: 1,
            responsiblePid: pid,
            bundleIdentifier: nil,
            workingDirectory: nil,
            physFootprint: footprint,
            residentSize: resident,
            sharedMemory: 0,
            startTimeSec: startTimeSec,
            startTimeUsec: startTimeUsec,
            firstSeen: now,
            lastSeen: now,
            exitedAt: nil,
            isPartialData: false
        )
    }

    @Test("nonResidentMemory is footprint minus resident when footprint exceeds resident")
    func nonResidentMemoryPositive() {
        let s = snapshot(footprint: 100, resident: 80)
        #expect(s.nonResidentMemory == 20)
    }

    @Test("nonResidentMemory is zero when footprint equals resident")
    func nonResidentMemoryZeroWhenEqual() {
        let s = snapshot(footprint: 100, resident: 100)
        #expect(s.nonResidentMemory == 0)
    }

    @Test("nonResidentMemory is zero when resident exceeds footprint")
    func nonResidentMemoryZeroWhenResidentExceeds() {
        let s = snapshot(footprint: 80, resident: 100)
        #expect(s.nonResidentMemory == 0)
    }

    @Test("processIdentity fields match the snapshot")
    func processIdentityFieldsMatch() {
        let s = snapshot(pid: 99, path: "/usr/local/bin/myapp", footprint: 200, resident: 150,
                         startTimeSec: 9_999_999, startTimeUsec: 123)
        let identity = s.processIdentity
        #expect(identity.pid == 99)
        #expect(identity.executablePath == "/usr/local/bin/myapp")
        #expect(identity.startTimeSec == 9_999_999)
        #expect(identity.startTimeUsec == 123)
    }
}

@Suite("ProcessIdentity")
struct ProcessIdentityTests {
    private func identity(
        pid: Int32 = 42,
        path: String = "/usr/bin/test",
        sec: UInt64 = 100,
        usec: UInt64 = 0
    ) -> ProcessIdentity {
        ProcessIdentity(pid: pid, executablePath: path, startTimeSec: sec, startTimeUsec: usec)
    }

    @Test("Two identities with the same fields are equal")
    func equalWhenAllFieldsMatch() {
        #expect(identity() == identity())
    }

    @Test("Different PID means not equal")
    func notEqualOnDifferentPID() {
        #expect(identity(pid: 1) != identity(pid: 2))
    }

    @Test("Different start time seconds means not equal")
    func notEqualOnDifferentStartTimeSec() {
        #expect(identity(sec: 100) != identity(sec: 200))
    }

    @Test("Different start time microseconds means not equal")
    func notEqualOnDifferentStartTimeUsec() {
        #expect(identity(usec: 0) != identity(usec: 1))
    }

    @Test("Different executable path means not equal")
    func notEqualOnDifferentPath() {
        #expect(identity(path: "/bin/a") != identity(path: "/bin/b"))
    }

    @Test("Identities can be used as Set members")
    func usableInSet() {
        let id = identity()
        let set: Set<ProcessIdentity> = [id, id]
        #expect(set.count == 1)
    }

    @Test("Identities can be used as dictionary keys")
    func usableAsDictionaryKey() {
        let id = identity()
        var dict: [ProcessIdentity: Int] = [:]
        dict[id] = 7
        #expect(dict[id] == 7)
    }
}
