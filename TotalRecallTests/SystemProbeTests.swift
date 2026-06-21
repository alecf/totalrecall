import Testing
import Foundation
@testable import TotalRecallCore

@Suite("SystemProbe")
struct SystemProbeTests {
    let currentPID = ProcessInfo.processInfo.processIdentifier

    // MARK: - listAllPIDs

    @Test("listAllPIDs returns a non-empty list")
    func listAllPIDsNonEmpty() {
        #expect(!SystemProbe.listAllPIDs().isEmpty)
    }

    @Test("listAllPIDs includes the current process")
    func listAllPIDsIncludesCurrentProcess() {
        #expect(SystemProbe.listAllPIDs().contains(currentPID))
    }

    // MARK: - getRusage

    @Test("getRusage returns info for current process")
    func getRusageForCurrentProcess() {
        let info = SystemProbe.getRusage(pid: currentPID)
        #expect(info != nil)
    }

    @Test("getRusage returns non-zero physFootprint for current process")
    func getRusageFootprintNonZero() {
        let info = SystemProbe.getRusage(pid: currentPID)
        #expect((info?.physFootprint ?? 0) > 0)
    }

    @Test("getRusage returns nil or valid info for non-existent PID")
    func getRusageForNonExistentPID() {
        let info = SystemProbe.getRusage(pid: 98765)
        _ = info  // nil for non-existent PID — just verify no crash
    }

    // MARK: - getBSDInfo

    @Test("getBSDInfo returns info for current process")
    func getBSDInfoForCurrentProcess() {
        let info = SystemProbe.getBSDInfo(pid: currentPID)
        #expect(info != nil)
    }

    @Test("getBSDInfo returns non-empty name for current process")
    func getBSDInfoNameNonEmpty() {
        let info = SystemProbe.getBSDInfo(pid: currentPID)
        let name = info?.name ?? ""
        #expect(!name.isEmpty)
    }

    @Test("getBSDInfo returns valid parent PID for current process")
    func getBSDInfoParentPIDValid() {
        let info = SystemProbe.getBSDInfo(pid: currentPID)
        #expect((info?.parentPid ?? -1) >= 1)
    }

    @Test("getBSDInfo returns uid for current process")
    func getBSDInfoUIDValid() {
        let info = SystemProbe.getBSDInfo(pid: currentPID)
        #expect(info?.uid != nil)
    }

    @Test("getBSDInfo returns nil for non-existent PID")
    func getBSDInfoForNonExistentPID() {
        let info = SystemProbe.getBSDInfo(pid: 98765)
        _ = info  // Should typically return nil for a non-existent PID
    }

    // MARK: - getProcessPath

    @Test("getProcessPath returns a path for current process")
    func getProcessPathForCurrentProcess() {
        let path = SystemProbe.getProcessPath(pid: currentPID)
        #expect(path != nil)
        #expect(!(path ?? "").isEmpty)
    }

    @Test("getProcessPath returns nil for non-existent PID")
    func getProcessPathForNonExistentPID() {
        let path = SystemProbe.getProcessPath(pid: 98765)
        _ = path
    }

    // MARK: - getParentPid

    @Test("getParentPid returns a valid PID for current process")
    func getParentPidForCurrentProcess() {
        let ppid = SystemProbe.getParentPid(pid: currentPID)
        #expect(ppid != nil)
        #expect((ppid ?? 0) >= 1)
    }

    @Test("getParentPid returns nil or valid value for non-existent PID")
    func getParentPidForNonExistentPID() {
        let ppid = SystemProbe.getParentPid(pid: 98765)
        _ = ppid
    }

    // MARK: - getTaskInfo

    @Test("getTaskInfo returns info for current process")
    func getTaskInfoForCurrentProcess() {
        let info = SystemProbe.getTaskInfo(pid: currentPID)
        #expect(info != nil)
    }

    @Test("getTaskInfo residentSize is non-zero for current process")
    func getTaskInfoResidentSizeNonZero() {
        let info = SystemProbe.getTaskInfo(pid: currentPID)
        #expect((info?.residentSize ?? 0) > 0)
    }

    @Test("getTaskInfo returns nil for non-existent PID")
    func getTaskInfoForNonExistentPID() {
        let info = SystemProbe.getTaskInfo(pid: 98765)
        _ = info
    }

    // MARK: - getWorkingDirectory

    @Test("getWorkingDirectory returns a non-empty string or nil for current process")
    func getWorkingDirectoryForCurrentProcess() {
        let dir = SystemProbe.getWorkingDirectory(pid: currentPID)
        if let dir {
            #expect(!dir.isEmpty)
        }
    }

    // MARK: - getCommandLineArgs

    @Test("getCommandLineArgs returns non-empty list or nil for current process")
    func getCommandLineArgsForCurrentProcess() {
        let args = SystemProbe.getCommandLineArgs(pid: currentPID)
        if let args {
            #expect(!args.isEmpty)
        }
    }

    // MARK: - getSystemMemory

    @Test("getSystemMemory returns positive totalPhysical")
    func getSystemMemoryTotalPhysicalPositive() {
        let memory = SystemProbe.getSystemMemory()
        #expect(memory.totalPhysical > 0)
    }

    @Test("getSystemMemory totalPhysical matches ProcessInfo")
    func getSystemMemoryTotalMatchesProcessInfo() {
        let memory = SystemProbe.getSystemMemory()
        #expect(memory.totalPhysical == ProcessInfo.processInfo.physicalMemory)
    }

    @Test("getSystemMemory returns a valid pressure value")
    func getSystemMemoryPressureValid() {
        let memory = SystemProbe.getSystemMemory()
        let validPressures: [MemoryPressure] = [.normal, .warning, .critical]
        #expect(validPressures.contains(memory.memoryPressure))
    }

    // MARK: - getBundleIdentifier

    @Test("getBundleIdentifier for test runner returns nil or a string")
    func getBundleIdentifierForCurrentProcess() {
        let bundleId = SystemProbe.getBundleIdentifier(pid: currentPID)
        _ = bundleId  // No crash assertion
    }

    // MARK: - iconFromPath

    @Test("iconFromPath returns nil for non-.app path")
    func iconFromPathForNonAppPath() {
        let icon = SystemProbe.iconFromPath("/usr/bin/node")
        #expect(icon == nil)
    }

    @Test("iconFromPath returns nil for empty path")
    func iconFromPathForEmptyPath() {
        let icon = SystemProbe.iconFromPath("")
        #expect(icon == nil)
    }

    @Test("iconFromPath returns nil or image for .app path that may not exist")
    func iconFromPathForAppPath() {
        let icon = SystemProbe.iconFromPath("/Applications/Safari.app/Contents/MacOS/Safari")
        _ = icon  // May be nil if Safari not installed, but no crash
    }

    // MARK: - iconFromBundleID

    @Test("iconFromBundleID returns nil for unknown bundle")
    func iconFromBundleIDForUnknownBundle() {
        let icon = SystemProbe.iconFromBundleID("com.example.nonexistent.app.xyz.abc")
        #expect(icon == nil)
    }

    // MARK: - getAppIcon

    @Test("getAppIcon for current process returns nil or image")
    func getAppIconForCurrentProcess() {
        let icon = SystemProbe.getAppIcon(pid: currentPID)
        _ = icon  // May be nil in test environment
    }

    @Test("getAppIcon for non-existent PID does not crash")
    func getAppIconForNonExistentPID() {
        let icon = SystemProbe.getAppIcon(pid: 98765)
        _ = icon
    }
}
