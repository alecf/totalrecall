#!/usr/bin/env swift
//
// benchmark-collection.swift
//
// Measures the real-world cost of each libproc API tier on your system.
// Run with: swift tools/benchmark-collection.swift
//
// Tier 1 (every cycle):  proc_listallpids + proc_pid_rusage
// Tier 2 (new PIDs):     proc_pidinfo(PROC_PIDTBSDINFO) + proc_pidpath
// Tier 3 (amortized):    sysctl KERN_PROCARGS2
// System:                 host_statistics64 + vm.swapusage
//

import Darwin
import Foundation

// MARK: - Helpers

func formatDuration(_ ns: UInt64) -> String {
    if ns < 1_000 { return "\(ns) ns" }
    if ns < 1_000_000 { return String(format: "%.1f μs", Double(ns) / 1_000) }
    if ns < 1_000_000_000 { return String(format: "%.2f ms", Double(ns) / 1_000_000) }
    return String(format: "%.2f s", Double(ns) / 1_000_000_000)
}

func formatBytes(_ bytes: UInt64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
    return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
}

func measure(_ label: String, _ block: () -> Void) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    block()
    let end = DispatchTime.now().uptimeNanoseconds
    return end - start
}

// MARK: - API Wrappers

func listAllPIDs() -> [pid_t] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(count) * 2)
    let actual = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
    guard actual > 0 else { return [] }
    return Array(pids.prefix(Int(actual)))
}

func getRusage(pid: pid_t) -> (footprint: UInt64, resident: UInt64)? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
        }
    }
    guard result == 0 else { return nil }
    return (info.ri_phys_footprint, info.ri_resident_size)
}

func getProcInfo(pid: pid_t) -> (ppid: pid_t, name: String)? {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard size == MemoryLayout<proc_bsdinfo>.size else { return nil }
    let name = withUnsafePointer(to: info.pbi_name) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cstr in
            String(cString: cstr)
        }
    }
    return (pid_t(info.pbi_ppid), name)
}

func getProcPath(pid: pid_t) -> String? {
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(4 * MAXPATHLEN))
    defer { buffer.deallocate() }
    let result = proc_pidpath(pid, buffer, UInt32(4 * MAXPATHLEN))
    guard result > 0 else { return nil }
    return String(cString: buffer)
}

func getCommandLineArgs(pid: pid_t) -> [String]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size: Int = 0

    // First call to get size
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

    let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
    defer { buffer.deallocate() }

    guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else { return nil }

    // Parse: first 4 bytes = argc, then exec_path (null-terminated), then null padding, then args
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

    return args
}

func getSystemMemory() -> (total: UInt64, free: UInt64, active: UInt64, wired: UInt64, compressed: UInt64)? {
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let host = mach_host_self()

    let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
        statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }

    let pageSize = UInt64(vm_kernel_page_size)
    return (
        total: UInt64(ProcessInfo.processInfo.physicalMemory),
        free: UInt64(stats.free_count) * pageSize,
        active: UInt64(stats.active_count) * pageSize,
        wired: UInt64(stats.wire_count) * pageSize,
        compressed: UInt64(stats.compressor_page_count) * pageSize
    )
}

func getSwapUsage() -> (total: UInt64, used: UInt64)? {
    var swapUsage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 else { return nil }
    return (UInt64(swapUsage.xsu_total), UInt64(swapUsage.xsu_used))
}

// MARK: - Benchmark

print("=== Total Recall Collection Benchmark ===")
print()

// Step 0: System info
if let mem = getSystemMemory() {
    print("System: \(formatBytes(mem.total)) RAM, \(formatBytes(mem.compressed)) compressed")
}
if let swap = getSwapUsage() {
    print("Swap: \(formatBytes(swap.used)) / \(formatBytes(swap.total))")
}
print()

// Step 1: Enumerate PIDs
var pids: [pid_t] = []
let t1 = measure("proc_listallpids") {
    pids = listAllPIDs()
}
print("--- Tier 0: Enumerate ---")
print("  proc_listallpids: \(formatDuration(t1)) → \(pids.count) processes")
print()

// Step 2: Tier 1 — proc_pid_rusage for ALL pids
var rusageSuccessCount = 0
var rusageFailCount = 0
var totalFootprint: UInt64 = 0
let t2 = measure("proc_pid_rusage (all)") {
    for pid in pids {
        if let info = getRusage(pid: pid) {
            rusageSuccessCount += 1
            totalFootprint += info.footprint
        } else {
            rusageFailCount += 1
        }
    }
}
let perPidRusage = pids.count > 0 ? t2 / UInt64(pids.count) : 0
print("--- Tier 1: Memory (every cycle) ---")
print("  proc_pid_rusage × \(pids.count): \(formatDuration(t2)) total, \(formatDuration(perPidRusage))/pid")
print("  success: \(rusageSuccessCount), failed: \(rusageFailCount) (ESRCH/permission)")
print("  total footprint: \(formatBytes(totalFootprint))")
print()

// Step 3: Tier 2 — proc_pidinfo + proc_pidpath for ALL pids
var infoSuccessCount = 0
var infoFailCount = 0
let t3a = measure("proc_pidinfo (all)") {
    for pid in pids {
        if getProcInfo(pid: pid) != nil {
            infoSuccessCount += 1
        } else {
            infoFailCount += 1
        }
    }
}
let perPidInfo = pids.count > 0 ? t3a / UInt64(pids.count) : 0

var pathSuccessCount = 0
var pathFailCount = 0
let t3b = measure("proc_pidpath (all)") {
    for pid in pids {
        if getProcPath(pid: pid) != nil {
            pathSuccessCount += 1
        } else {
            pathFailCount += 1
        }
    }
}
let perPidPath = pids.count > 0 ? t3b / UInt64(pids.count) : 0

print("--- Tier 2: Identity (new PIDs only) ---")
print("  proc_pidinfo × \(pids.count): \(formatDuration(t3a)) total, \(formatDuration(perPidInfo))/pid")
print("    success: \(infoSuccessCount), failed: \(infoFailCount)")
print("  proc_pidpath × \(pids.count): \(formatDuration(t3b)) total, \(formatDuration(perPidPath))/pid")
print("    success: \(pathSuccessCount), failed: \(pathFailCount)")
print()

// Step 4: Tier 3 — KERN_PROCARGS2 for ALL pids (the expensive one)
var argsSuccessCount = 0
var argsFailCount = 0
var totalArgsBytes = 0
let t4 = measure("KERN_PROCARGS2 (all)") {
    for pid in pids {
        if let args = getCommandLineArgs(pid: pid) {
            argsSuccessCount += 1
            totalArgsBytes += args.joined(separator: " ").utf8.count
        } else {
            argsFailCount += 1
        }
    }
}
let perPidArgs = pids.count > 0 ? t4 / UInt64(pids.count) : 0

print("--- Tier 3: Command-line args (amortized) ---")
print("  KERN_PROCARGS2 × \(pids.count): \(formatDuration(t4)) total, \(formatDuration(perPidArgs))/pid")
print("    success: \(argsSuccessCount), failed: \(argsFailCount)")
print("    total arg data: \(formatBytes(UInt64(totalArgsBytes)))")
print()

// Step 5: System-wide stats
let t5a = measure("host_statistics64") { _ = getSystemMemory() }
let t5b = measure("vm.swapusage") { _ = getSwapUsage() }
print("--- System-wide stats ---")
print("  host_statistics64: \(formatDuration(t5a))")
print("  vm.swapusage: \(formatDuration(t5b))")
print()

// Step 6: Simulate tiered collection cycle
print("=== Simulated Collection Cycles ===")
print()

let fullCycle = t1 + t2 + t3a + t3b + t4 + t5a + t5b
let tier1Only = t1 + t2 + t5a + t5b
let tier1and2 = t1 + t2 + t3a + t3b + t5a + t5b

print("  Full collection (all tiers, all PIDs):  \(formatDuration(fullCycle))")
print("  Tier 1 only (memory numbers + system):  \(formatDuration(tier1Only))")
print("  Tier 1+2 (+ identity, simulating new):  \(formatDuration(tier1and2))")
print()

// Step 7: Budget simulation — how many KERN_PROCARGS2 calls fit in a budget?
print("=== Budget Simulation ===")
print()

for budgetMs in [10, 20, 50] {
    let budgetNs = UInt64(budgetMs) * 1_000_000
    var count = 0
    let start = DispatchTime.now().uptimeNanoseconds

    for pid in pids {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed > budgetNs { break }
        _ = getCommandLineArgs(pid: pid)
        count += 1
    }

    let actualElapsed = DispatchTime.now().uptimeNanoseconds - start
    print("  \(budgetMs)ms budget: completed \(count)/\(pids.count) KERN_PROCARGS2 calls in \(formatDuration(actualElapsed))")
    if pids.count > 0 {
        let cyclesNeeded = (pids.count + count - 1) / max(count, 1)
        print("    → would need \(cyclesNeeded) cycles to cover all PIDs (\(cyclesNeeded * 5)s at 5s interval)")
    }
}
print()

// Step 8: Measure variance — run tier 1 multiple times to see consistency
print("=== Tier 1 Consistency (5 runs) ===")
print()
for i in 1...5 {
    var count = 0
    let t = measure("run \(i)") {
        let p = listAllPIDs()
        for pid in p {
            if getRusage(pid: pid) != nil { count += 1 }
        }
    }
    print("  Run \(i): \(formatDuration(t)) (\(count) processes)")
}
print()

print("=== Summary ===")
print()
print("  Processes on this system: \(pids.count)")
print("  Tier 1 (memory, every 5s):   \(formatDuration(tier1Only)) — \(tier1Only < 10_000_000 ? "SAFE" : tier1Only < 50_000_000 ? "OK" : "CONCERN")")
print("  Tier 2 (identity, new PIDs): \(formatDuration(tier1and2 - tier1Only)) — cached after first collection")
print("  Tier 3 (args, amortized):    \(formatDuration(t4)) — spread across \((pids.count + 50) / max(1, (pids.count > 0 ? Int(10_000_000 / max(perPidArgs, 1)) : 50))) cycles")
print()
print("  Recommendation:")
if fullCycle < 50_000_000 {
    print("    Full collection is under 50ms — tiering is optional but still good practice")
} else if tier1Only < 10_000_000 {
    print("    Tier 1 is fast (\(formatDuration(tier1Only))). Tier 3 needs amortization.")
    print("    Budget ~10-20ms per cycle for KERN_PROCARGS2 calls.")
} else {
    print("    Even Tier 1 is slow. Consider reducing refresh rate or sampling.")
}
