import Darwin
import Foundation
import AppKit

/// Low-level wrappers around libproc, sysctl, and Mach APIs.
/// All functions are static and safe to call from any thread.
public enum SystemProbe {

    // MARK: - Process Enumeration

    public static func listAllPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let actual = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard actual > 0 else { return [] }
        return Array(pids.prefix(Int(actual)))
    }

    // MARK: - Per-Process Memory (Tier 1: cheap, every cycle)

    public struct RusageInfo: Sendable {
        let physFootprint: UInt64
        let residentSize: UInt64
    }

    public static func getRusage(pid: pid_t) -> RusageInfo? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }
        guard result == 0 else { return nil }
        return RusageInfo(
            physFootprint: info.ri_phys_footprint,
            residentSize: info.ri_resident_size
        )
    }

    // MARK: - Process Info (Tier 2: cached per PID)

    public struct BSDInfo: Sendable {
        let name: String
        let parentPid: pid_t
        let responsiblePid: pid_t
        let startTimeSec: UInt64
        let startTimeUsec: UInt64
        let uid: UInt32
    }

    public static func getBSDInfo(pid: pid_t) -> BSDInfo? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard size == MemoryLayout<proc_bsdinfo>.size else { return nil }

        // pbi_name is a C tuple of chars — extract safely
        let name = withUnsafeBytes(of: &info.pbi_name) { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return "unknown" }
            let cString = baseAddress.assumingMemoryBound(to: CChar.self)
            return String(cString: cString)
        }

        // proc_bsdinfo doesn't expose responsible PID directly.
        // Use parent PID as the grouping signal; classifiers refine further.
        let responsiblePid = pid_t(info.pbi_ppid)

        return BSDInfo(
            name: name,
            parentPid: pid_t(info.pbi_ppid),
            responsiblePid: responsiblePid != 0 ? responsiblePid : pid,
            startTimeSec: UInt64(info.pbi_start_tvsec),
            startTimeUsec: UInt64(info.pbi_start_tvusec),
            uid: info.pbi_uid
        )
    }

    public static func getProcessPath(pid: pid_t) -> String? {
        let maxSize = 4 * Int(MAXPATHLEN)
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: maxSize)
        defer { buffer.deallocate() }
        let result = proc_pidpath(pid, buffer, UInt32(maxSize))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Shared Memory (RSHRD)

    public struct TaskInfo: Sendable {
        let residentSize: UInt64
        let virtualSize: UInt64
    }

    public static func getTaskInfo(pid: pid_t) -> TaskInfo? {
        var info = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard size == MemoryLayout<proc_taskinfo>.size else { return nil }
        return TaskInfo(
            residentSize: UInt64(info.pti_resident_size),
            virtualSize: UInt64(info.pti_virtual_size)
        )
    }

    // MARK: - Working Directory

    /// Get the current working directory of a process via proc_pidinfo.
    public static func getWorkingDirectory(pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo,
                                Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard size == MemoryLayout<proc_vnodepathinfo>.size else { return nil }

        return withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cstr in
                let str = String(cString: cstr)
                return str.isEmpty ? nil : str
            }
        }
    }

    // MARK: - Command Line Args (Tier 3: expensive, cached per PID)

    public static func getCommandLineArgs(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        defer { buffer.deallocate() }

        guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else { return nil }
        guard size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.load(as: Int32.self)
        var offset = MemoryLayout<Int32>.size

        // Skip exec_path
        while offset < size && buffer.load(fromByteOffset: offset, as: UInt8.self) != 0 {
            offset += 1
        }
        // Skip null padding
        while offset < size && buffer.load(fromByteOffset: offset, as: UInt8.self) == 0 {
            offset += 1
        }

        // Read args
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            let start = buffer.advanced(by: offset)
            let str = String(cString: start.assumingMemoryBound(to: CChar.self))
            args.append(str)
            offset += str.utf8.count + 1
        }

        return args  // No redaction for live display — user is viewing their own processes
    }

    // MARK: - App Icon

    public static func getAppIcon(pid: pid_t) -> NSImage? {
        // Best: NSRunningApplication provides the correct app icon
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.icon
        }
        // Fallback: resolve via the .app bundle path (not the executable)
        if let path = getProcessPath(pid: pid) {
            return iconFromPath(path)
        }
        return nil
    }

    /// Get an icon for a path, preferring the .app bundle icon over the executable icon.
    public static func iconFromPath(_ path: String) -> NSImage? {
        // Extract .app bundle path and use that for the icon
        if let appPath = extractAppBundlePath(from: path) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    /// Get an icon via bundle identifier (most reliable for known apps).
    public static func iconFromBundleID(_ bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    /// Extract the .app bundle path from an executable path.
    /// "/Applications/Foo.app/Contents/MacOS/Foo" → "/Applications/Foo.app"
    private static func extractAppBundlePath(from path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[path.startIndex..<range.lowerBound]) + ".app"
        }
        if path.hasSuffix(".app") {
            return path
        }
        return nil
    }

    // MARK: - Bundle Identifier

    public static func getBundleIdentifier(pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - System-Wide Memory

    public static func getSystemMemory() -> SystemMemoryInfo {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let host = mach_host_self()

        let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }

        // vm_kernel_page_size is effectively constant after boot; use sysctl instead
        let pageSize = UInt64(getPageSize())
        let totalPhysical = UInt64(ProcessInfo.processInfo.physicalMemory)

        guard result == KERN_SUCCESS else {
            return SystemMemoryInfo(
                totalPhysical: totalPhysical, used: 0, free: 0, active: 0,
                inactive: 0, wired: 0, compressed: 0,
                memoryPressure: .normal, swapTotal: 0, swapUsed: 0
            )
        }

        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        // Swap
        let (swapTotal, swapUsed) = getSwapUsage()

        // Memory pressure from the dispatch source level
        let pressure = getMemoryPressure()

        return SystemMemoryInfo(
            totalPhysical: totalPhysical,
            used: used,
            free: free,
            active: active,
            inactive: inactive,
            wired: wired,
            compressed: compressed,
            memoryPressure: pressure,
            swapTotal: swapTotal,
            swapUsed: swapUsed
        )
    }

    private static func getPageSize() -> Int {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        return Int(pageSize)
    }

    private static func getSwapUsage() -> (total: UInt64, used: UInt64) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 else {
            return (0, 0)
        }
        return (UInt64(swapUsage.xsu_total), UInt64(swapUsage.xsu_used))
    }

    private static func getMemoryPressure() -> MemoryPressure {
        // Use kern.memorystatus_level to approximate pressure
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        // level is a percentage (0-100) of available memory
        if level < 10 { return .critical }
        if level < 30 { return .warning }
        return .normal
    }
}
