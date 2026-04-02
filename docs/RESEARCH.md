# Total Recall -- Framework & API Research

Research gathered for building a macOS 26 menu bar memory monitor in Swift/SwiftUI, as specified in the PRD.

---

## 1. SwiftUI MenuBarExtra

### Summary

`MenuBarExtra` is a SwiftUI `Scene` type (macOS 13+) that renders a persistent icon in the system menu bar. It is the SwiftUI replacement for the AppKit `NSStatusItem` pattern.

### API Reference

**Documentation**: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra

#### Initializers

```swift
// Basic -- always shown
MenuBarExtra(content: () -> Content, label: () -> Label)
MenuBarExtra(_ titleKey: LocalizedStringKey, content: () -> Content)
MenuBarExtra(_ titleKey: LocalizedStringKey, systemImage: String, content: () -> Content)
MenuBarExtra(_ titleKey: LocalizedStringKey, image: String, content: () -> Content)

// With isInserted binding -- can be toggled on/off
MenuBarExtra(isInserted: Binding<Bool>, content: () -> Content, label: () -> Label)
MenuBarExtra(_ titleKey: LocalizedStringKey, isInserted: Binding<Bool>, content: () -> Content)
MenuBarExtra(_ titleKey: LocalizedStringKey, systemImage: String, isInserted: Binding<Bool>, content: () -> Content)
```

#### Styles

Apply via `.menuBarExtraStyle(_:)`:

| Style | Type | Behavior |
|---|---|---|
| `.menu` (default) | `PullDownMenuBarExtraStyle` | Content renders as a standard NSMenu pull-down. Only `Button`, `Toggle`, `Picker`, `Divider`, and sub-`Menu` are supported. |
| `.window` | `WindowMenuBarExtraStyle` | Content renders inside a chromeless floating window anchored below the menu bar icon. Supports arbitrary SwiftUI views (sliders, lists, custom controls). |

**Documentation**: https://developer.apple.com/documentation/swiftui/menubarextrastyle

#### Recommended Style for Total Recall

The PRD calls for a compact menu bar item that, when clicked, opens the inspection window. There are two approaches:

**Approach A -- MenuBarExtra with `.menu` style + separate Window**

Use a `.menu` style MenuBarExtra whose content contains a button that calls `openWindow`. This is the recommended approach when the menu bar click should open a full window rather than a popover panel.

```swift
@main
struct TotalRecallApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            Label("Total Recall", systemImage: "memorychip")
        }
        .menuBarExtraStyle(.menu)

        Window("Total Recall", id: "inspection") {
            InspectionWindowView()
        }
    }
}

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Total Recall") {
            openWindow(id: "inspection")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        Divider()
        // Quick stats here
        Text("Used: 12.4 / 16 GB")
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

**Approach B -- MenuBarExtra with `.window` style**

The `.window` style gives a compact floating panel for quick glances (like macOS Control Center). Good for showing the summary bar and top consumers inline without opening a full window.

```swift
MenuBarExtra {
    CompactSummaryView()  // Arbitrary SwiftUI -- lists, gauges, etc.
} label: {
    // This is what appears in the menu bar
    HStack(spacing: 4) {
        Image(systemName: "memorychip")
        Text("12.4 GB")
            .monospacedDigit()
    }
}
.menuBarExtraStyle(.window)
```

**Key limitation**: With `.window` style, the panel auto-dismisses when the user clicks outside. There is no built-in API to keep it pinned. Opening a full `Window` from inside a `.window`-style MenuBarExtra works via `openWindow` but the panel itself will dismiss.

#### Known Issues and Workarounds

- **No programmatic open/close**: There is no built-in SwiftUI API to programmatically show or hide the MenuBarExtra popover. The third-party library [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) adds `isPresented` binding support and access to the underlying `NSStatusItem`.
- **Settings window from menu bar**: On macOS 14+, use `SettingsLink()` inside the menu content. On earlier versions, use `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`.
- **Menu-style body re-rendering**: The `.menu` style body is re-evaluated each time the menu is opened (FB13683957). The `.window` style body persists.

### Guide

**Building and customizing the menu bar with SwiftUI**: https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI

---

## 2. SwiftUI Window and WindowGroup

### Summary

`Window` declares a single-instance window scene. `WindowGroup` declares a window that can have multiple instances. Both support identification by string ID and/or presented data type, and are opened programmatically via the `openWindow` environment action.

### API Reference

**Documentation**:
- https://developer.apple.com/documentation/swiftui/windowgroup
- https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow

#### Window (single instance)

```swift
Window("Inspector", id: "inspection") {
    InspectionWindowView()
}
.defaultSize(width: 800, height: 600)
.defaultPosition(.center)
```

#### WindowGroup (multiple instances, data-driven)

```swift
// Open a window for a specific value
WindowGroup("Process Detail", id: "process-detail", for: Int32.self) { $pid in
    if let pid {
        ProcessDetailView(pid: pid)
    }
}
```

#### Opening Windows

The `OpenWindowAction` is obtained from the SwiftUI environment:

```swift
struct SomeView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Inspector") {
            openWindow(id: "inspection")
        }
        Button("Show Process") {
            openWindow(id: "process-detail", value: pid)
        }
    }
}
```

#### Dismissing Windows

```swift
@Environment(\.dismissWindow) private var dismissWindow

Button("Close") {
    dismissWindow(id: "inspection")
}
```

#### Window Modifiers

```swift
Window("Title", id: "myWindow") { ... }
    .defaultSize(width: 800, height: 600)
    .defaultSize(CGSize(width: 800, height: 600))
    .defaultPosition(.center)           // .leading, .trailing, .topLeading, etc.
    .windowResizability(.contentSize)    // .automatic, .contentSize, .contentMinSize
    .windowStyle(.hiddenTitleBar)        // .automatic, .hiddenTitleBar, .titleBar
    .commandsRemoved()                   // Remove default menu commands (File > New Window)
```

#### Menu-Bar-Only App Pattern

To suppress the default window and only show the menu bar icon:

```swift
@main
struct TotalRecallApp: App {
    var body: some Scene {
        MenuBarExtra { ... } label: { ... }
            .menuBarExtraStyle(.menu)

        Window("Total Recall", id: "inspection") {
            InspectionWindowView()
        }
        .commandsRemoved()  // No File > New Window menu item
    }
}
```

Note: With this pattern, no window opens at launch -- only the menu bar icon appears. The user opens the inspection window by clicking the menu bar icon.

### WWDC Sessions

- **Bring multiple windows to your SwiftUI app** (WWDC22): https://developer.apple.com/videos/play/wwdc2022/10061/
- **Work with windows in SwiftUI** (WWDC24): https://developer.apple.com/videos/play/wwdc2024/10149/

---

## 3. SwiftUI List with DisclosureGroup and OutlineGroup

### Summary

SwiftUI provides two key components for expandable, tree-like lists:

- **`DisclosureGroup`**: A view that shows/hides content based on a disclosure control. Manual, explicit expand/collapse.
- **`OutlineGroup`**: Automatically traverses tree-structured data and generates nested DisclosureGroups. Data-driven.

### API Reference

**Documentation**:
- https://developer.apple.com/documentation/swiftui/disclosuregroup
- https://developer.apple.com/documentation/swiftui/outlinegroup
- https://developer.apple.com/documentation/swiftui/disclosuregroupstyle

#### DisclosureGroup

```swift
// With explicit binding
@State private var isExpanded = false

DisclosureGroup("Chrome -- Work Profile", isExpanded: $isExpanded) {
    Text("Google Chrome Helper (Renderer) -- 245 MB")
    Text("Google Chrome Helper (GPU) -- 89 MB")
}

// Without binding (SwiftUI manages state)
DisclosureGroup("System Services") {
    ForEach(systemProcesses) { proc in
        ProcessRowView(process: proc)
    }
}
```

#### OutlineGroup (tree-structured data)

For data that conforms to `Identifiable` and has an optional `children` property:

```swift
struct ProcessNode: Identifiable {
    let id: Int32           // pid
    let name: String
    let memory: UInt64
    var children: [ProcessNode]?
}

// OutlineGroup automatically creates nested DisclosureGroups
List {
    OutlineGroup(processTree, children: \.children) { node in
        ProcessRowView(node: node)
    }
}
```

#### List with Hierarchical Data (shorthand)

`List` itself has an initializer that accepts a `children` key path, combining `List` + `OutlineGroup`:

```swift
List(smartGroups, children: \.processes) { item in
    SmartGroupRowView(item: item)
}
```

#### Recommended Pattern for Total Recall

The smart group list needs two levels: groups and processes within groups. A manual `DisclosureGroup` inside a `List` gives the most control:

```swift
struct SmartGroupListView: View {
    let groups: [SmartGroup]
    @State private var expandedGroups: Set<SmartGroup.ID> = []

    var body: some View {
        List(groups) { group in
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedGroups.contains(group.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedGroups.insert(group.id)
                        } else {
                            expandedGroups.remove(group.id)
                        }
                    }
                )
            ) {
                // Expanded content: individual processes
                ForEach(group.processes) { process in
                    ProcessRowView(process: process)
                        .padding(.leading, 20)
                }
            } label: {
                SmartGroupRowView(group: group)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}
```

#### Custom DisclosureGroupStyle (macOS 13+)

```swift
struct CompactDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.2), value: configuration.isExpanded)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                configuration.isExpanded.toggle()
            }
        }
        if configuration.isExpanded {
            configuration.content
        }
    }
}
```

---

## 4. Swift Concurrency (Actors, Async/Await)

### Summary

Swift's structured concurrency model provides actors for state isolation, async/await for non-blocking operations, and `@MainActor` for UI-safe updates. This is the recommended approach for the background polling loop in Total Recall.

### API Reference

**Documentation**:
- https://developer.apple.com/documentation/swift/concurrency
- https://developer.apple.com/documentation/swift/globalactor
- https://developer.apple.com/videos/play/wwdc2025/268/ (Embracing Swift concurrency -- WWDC25)

#### Actor for Process Monitor

An actor serializes access to mutable state, making it safe for concurrent access without locks:

```swift
actor ProcessMonitor {
    private var previousSnapshot: [Int32: ProcessInfo] = [:]
    private var currentSnapshot: [Int32: ProcessInfo] = [:]

    func refresh() async -> [SmartGroup] {
        // This runs off the main thread, serialized by the actor
        let pids = enumerateAllPIDs()
        var newSnapshot: [Int32: ProcessInfo] = [:]
        for pid in pids {
            if let info = readProcessInfo(pid: pid) {
                newSnapshot[pid] = info
            }
        }
        previousSnapshot = currentSnapshot
        currentSnapshot = newSnapshot
        return groupProcesses(newSnapshot)
    }
}
```

#### @MainActor for UI State

```swift
@MainActor
@Observable
class AppState {
    var groups: [SmartGroup] = []
    var systemMemory: SystemMemoryInfo = .empty
    var isRefreshing = false

    private let monitor = ProcessMonitor()

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let newGroups = await monitor.refresh()
        groups = newGroups  // Safe: we are on @MainActor
    }
}
```

#### Periodic Polling with Task and Clock

The recommended modern approach uses `Task` with `Clock.sleep` rather than `Timer`:

```swift
@MainActor
@Observable
class AppState {
    private var pollingTask: Task<Void, Never>?
    var refreshInterval: Duration = .seconds(5)

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
```

#### AsyncStream for Continuous Updates (alternative)

```swift
actor ProcessMonitor {
    func updates(interval: Duration) -> AsyncStream<[SmartGroup]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let groups = await self.refresh()
                    continuation.yield(groups)
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
```

#### Task Cancellation and Cleanup

```swift
// In a SwiftUI view
.task {
    // Automatically cancelled when the view disappears
    for await groups in monitor.updates(interval: .seconds(5)) {
        self.groups = groups
    }
}
```

#### nonisolated for C Interop

The libproc calls are synchronous C functions. Mark them `nonisolated` if they are defined on an actor to avoid unnecessary actor hops:

```swift
actor ProcessMonitor {
    nonisolated func readProcessInfo(pid: Int32) -> ProcessInfo? {
        // C calls like proc_pidinfo are safe to call from any thread
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(size))
        guard ret == size else { return nil }
        // ...
    }
}
```

### WWDC Sessions

- **Meet async/await in Swift** (WWDC21): https://developer.apple.com/videos/play/wwdc2021/10132/
- **Protect mutable state with Swift actors** (WWDC21): https://developer.apple.com/videos/play/wwdc2021/10133/
- **Beyond the basics of structured concurrency** (WWDC23): https://developer.apple.com/videos/play/wwdc2023/10170/

---

## 5. libproc APIs

### Summary

The `libproc` library provides C functions for querying process information on macOS. These are public, stable APIs available in the Darwin module. No special entitlements are needed for same-user processes; Full Disk Access is needed for cross-user processes.

**Header**: `<libproc.h>` (imported automatically via `import Darwin`)

### proc_listallpids

Enumerates all PIDs on the system.

```c
// C declaration
int proc_listallpids(void *buffer, int buffersize);
// Returns: number of PIDs on success, 0 or -1 on failure
```

**Swift usage**:

```swift
import Darwin

func enumerateAllPIDs() -> [Int32] {
    // First call with nil to get count
    let estimatedCount = proc_listallpids(nil, 0)
    guard estimatedCount > 0 else { return [] }

    // Allocate buffer with padding for new processes
    let bufferSize = Int(estimatedCount) * MemoryLayout<Int32>.stride * 2
    var pids = [Int32](repeating: 0, count: Int(estimatedCount) * 2)

    let actualCount = proc_listallpids(&pids, Int32(bufferSize))
    guard actualCount > 0 else { return [] }

    return Array(pids.prefix(Int(actualCount)))
}
```

### proc_pidinfo -- PROC_PIDTBSDINFO

Retrieves BSD-level process information: name, parent PID, responsible PID, UID, GID, flags.

```c
// C declaration
int proc_pidinfo(int pid, int flavor, uint64_t arg,
                 void *buffer, int buffersize);
// Returns: bytes copied on success, 0 on failure

// flavor = PROC_PIDTBSDINFO (value 3)
// buffer type: struct proc_bsdinfo
```

**Swift usage**:

```swift
func getBSDInfo(pid: Int32) -> proc_bsdinfo? {
    var info = proc_bsdinfo()
    let size = MemoryLayout<proc_bsdinfo>.stride
    let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
    guard ret == size else { return nil }
    return info
}

// Accessing fields:
// info.pbi_ppid        -- parent PID
// info.pbi_name        -- process name (16 chars max, use proc_pidpath for full)
// info.e_tdev          -- responsible PID (via pbi_ruid for responsible user)
// info.pbi_flags       -- process flags
// info.pbi_uid         -- user ID
// info.pbi_start       -- start time
```

### proc_pidinfo -- PROC_PIDTASKINFO

Retrieves task-level information: resident memory size, virtual size, CPU times.

```c
// flavor = PROC_PIDTASKINFO (value 4)
// buffer type: struct proc_taskinfo
```

**Swift usage**:

```swift
func getTaskInfo(pid: Int32) -> proc_taskinfo? {
    var info = proc_taskinfo()
    let size = MemoryLayout<proc_taskinfo>.stride
    let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(size))
    guard ret == size else { return nil }
    return info
}

// Key fields:
// info.pti_resident_size   -- resident memory (bytes)
// info.pti_virtual_size    -- virtual memory (bytes)
// info.pti_total_user      -- total user CPU time (nanoseconds)
// info.pti_total_system    -- total system CPU time (nanoseconds)
// info.pti_threads_user    -- current threads user time
// info.pti_threads_system  -- current threads system time
```

### proc_pidpath

Retrieves the full executable path for a process.

```c
int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
// Returns: length of path on success, 0 on failure
// Maximum buffer size: PROC_PIDPATHINFO_MAXSIZE (4096)
```

**Swift usage**:

```swift
func getProcessPath(pid: Int32) -> String? {
    let pathBuffer = UnsafeMutablePointer<CChar>.allocate(
        capacity: Int(PROC_PIDPATHINFO_MAXSIZE)
    )
    defer { pathBuffer.deallocate() }

    let ret = proc_pidpath(pid, pathBuffer, UInt32(PROC_PIDPATHINFO_MAXSIZE))
    guard ret > 0 else { return nil }

    return String(cString: pathBuffer)
}
```

### proc_pid_rusage -- RUSAGE_INFO_V4 / V6

Retrieves detailed resource usage including the critical `ri_phys_footprint` field, which is the same "Memory" value shown in Activity Monitor.

```c
int proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer);
// flavor: RUSAGE_INFO_V0 through RUSAGE_INFO_V6
// Returns: 0 on success, -1 on failure
```

**rusage_info_v4 struct** (documented at https://developer.apple.com/documentation/kernel/rusage_info_v4):

Key fields:
- `ri_phys_footprint` -- physical memory footprint (the canonical memory number)
- `ri_resident_size` -- resident set size
- `ri_user_time` -- user CPU time (nanoseconds, but see note below)
- `ri_system_time` -- system CPU time
- `ri_proc_start_abstime` -- process start time (absolute time)
- `ri_proc_exit_abstime` -- process exit time
- `ri_child_user_time` -- cumulative child user CPU time
- `ri_child_system_time` -- cumulative child system CPU time

**RUSAGE_INFO_V6** adds fields beyond V4 (available on recent macOS versions). If the kernel does not support V6, fall back to V4.

**Swift usage**:

```swift
func getResourceUsage(pid: Int32) -> rusage_info_v4? {
    var usage = rusage_info_v4()
    let ret = withUnsafeMutablePointer(to: &usage) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rustPtr in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, rustPtr)
        }
    }
    guard ret == 0 else { return nil }
    return usage
}

// Primary memory metric:
let physicalFootprint = usage.ri_phys_footprint  // UInt64, bytes
```

**Important notes**:
- On some Apple Silicon systems, `ri_user_time` and `ri_system_time` may not be in nanoseconds but in a unit of approximately 40ns. Use `mach_timebase_info` to convert.
- `ri_phys_footprint` is the recommended metric for "how much memory is this process using" and matches Activity Monitor.

### Responsible PID

The responsible PID (the app that "owns" a process) is accessed via the `responsibility_get_pid_responsible_for_pid` function from the `libquarantine` / private responsibility API, or approximated using `proc_bsdinfo.pbi_rpid` (available in newer SDKs). An alternative is to parse the `KERN_PROCARGS2` data for XPC service processes.

---

## 6. host_statistics64

### Summary

Mach kernel API for retrieving system-wide virtual memory statistics. This is what `vm_stat` and Activity Monitor use internally.

**Documentation**: https://developer.apple.com/documentation/kernel/1502863-host_statistics64

### API Signature

```c
kern_return_t host_statistics64(
    host_t        host_priv,       // from mach_host_self()
    host_flavor_t flavor,          // HOST_VM_INFO64
    host_info64_t host_info_out,   // pointer to vm_statistics64
    mach_msg_type_number_t *host_info_outCnt  // in/out count
);
```

### Swift Usage

```swift
import Darwin
import MachO

struct SystemMemoryInfo {
    let totalPhysical: UInt64     // Total installed RAM
    let free: UInt64              // Free pages * page size
    let active: UInt64            // Active pages
    let inactive: UInt64          // Inactive pages
    let wired: UInt64             // Wired (non-purgeable)
    let compressed: UInt64        // Compressed pages
    let pageSize: UInt64

    static let empty = SystemMemoryInfo(
        totalPhysical: 0, free: 0, active: 0,
        inactive: 0, wired: 0, compressed: 0, pageSize: 0
    )
}

func getSystemMemoryInfo() -> SystemMemoryInfo? {
    // Page size
    let pageSize = UInt64(vm_kernel_page_size)

    // Total physical memory via sysctl
    var totalMemory: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)

    // VM statistics
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
    )

    let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
        statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
            host_statistics64(
                mach_host_self(),
                HOST_VM_INFO64,
                ptr,
                &count
            )
        }
    }

    guard result == KERN_SUCCESS else { return nil }

    return SystemMemoryInfo(
        totalPhysical: totalMemory,
        free: UInt64(stats.free_count) * pageSize,
        active: UInt64(stats.active_count) * pageSize,
        inactive: UInt64(stats.inactive_count) * pageSize,
        wired: UInt64(stats.wire_count) * pageSize,
        compressed: UInt64(stats.compressor_page_count) * pageSize,
        pageSize: pageSize
    )
}
```

### vm_statistics64 Key Fields

| Field | Type | Description |
|---|---|---|
| `free_count` | `natural_t` | Pages on the free list |
| `active_count` | `natural_t` | Pages in active use |
| `inactive_count` | `natural_t` | Pages recently used but currently inactive |
| `wire_count` | `natural_t` | Wired (locked in RAM, cannot be paged out) |
| `compressor_page_count` | `uint64_t` | Pages held by the compressor |
| `compressions` | `uint64_t` | Total compressions performed |
| `decompressions` | `uint64_t` | Total decompressions performed |
| `swapins` | `uint64_t` | Pages swapped in from disk |
| `swapouts` | `uint64_t` | Pages swapped out to disk |
| `external_page_count` | `natural_t` | File-backed pages |
| `internal_page_count` | `natural_t` | Anonymous (app) pages |
| `purgeable_count` | `natural_t` | Purgeable pages |
| `purges` | `uint64_t` | Pages purged |

### Memory Pressure

For the memory pressure indicator (green/yellow/red), use the `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` dispatch source or read from `host_statistics64`:

```swift
import Dispatch

func setupMemoryPressureMonitor(handler: @escaping (DispatchSource.MemoryPressureEvent) -> Void) {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical],
        queue: .main
    )
    source.setEventHandler {
        handler(source.data)
    }
    source.resume()
}
```

Alternatively, `kern.memorystatus_level` sysctl returns a 0-100 percentage that corresponds to the memory pressure gauge.

---

## 7. sysctl

### Summary

The `sysctl` family of functions retrieves kernel state. Two specific uses for Total Recall: process command-line arguments (`KERN_PROCARGS2`) and swap usage (`vm.swapusage`).

### KERN_PROCARGS2 -- Process Command-Line Arguments

This is the primary mechanism for resolving opaque process names (e.g., `node` to `webpack dev server`).

**Data format returned**: `[argc (int32)] [exec_path \0] [padding \0...] [arg0 \0] [arg1 \0] ... [argN \0] [env0=val \0] ...`

```swift
func getProcessArguments(pid: Int32) -> [String]? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var argMax: Int = 0
    var size = MemoryLayout<Int>.size

    // Get the maximum argument size
    var argMaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
    guard sysctl(&argMaxMib, 2, &argMax, &size, nil, 0) == 0 else { return nil }

    // Allocate buffer and fetch arguments
    var buffer = [UInt8](repeating: 0, count: argMax)
    size = argMax
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

    // Parse: first 4 bytes = argc
    let argc = buffer.withUnsafeBufferPointer { buf in
        buf.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
    }

    // Skip past argc (4 bytes), then read null-terminated strings
    var offset = MemoryLayout<Int32>.size
    var args: [String] = []

    // Skip executable path
    while offset < size && buffer[offset] != 0 { offset += 1 }
    // Skip null padding
    while offset < size && buffer[offset] == 0 { offset += 1 }

    // Read argc arguments
    var currentArg = ""
    var argsRead = 0
    while offset < size && argsRead < argc {
        if buffer[offset] == 0 {
            args.append(currentArg)
            currentArg = ""
            argsRead += 1
        } else {
            currentArg.append(Character(UnicodeScalar(buffer[offset])))
        }
        offset += 1
    }

    return args
}
```

**Security note**: `KERN_PROCARGS2` returns data for same-user processes without special permissions. For root-owned processes, Full Disk Access is required. The call will fail with `EPERM` otherwise -- handle this gracefully.

### vm.swapusage -- System Swap Statistics

```swift
struct SwapUsage {
    let total: UInt64
    let used: UInt64
    let free: UInt64
    let encrypted: Bool
}

func getSwapUsage() -> SwapUsage? {
    var swapUsage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 else {
        return nil
    }
    return SwapUsage(
        total: swapUsage.xsu_total,
        used: swapUsage.xsu_used,
        free: swapUsage.xsu_avail,
        encrypted: swapUsage.xsu_encrypted != 0
    )
}
```

The `xsw_usage` struct is defined in `<sys/sysctl.h>` and imported via Darwin:
- `xsu_total` -- total swap space (bytes)
- `xsu_avail` -- available swap space (bytes)
- `xsu_used` -- used swap space (bytes)
- `xsu_encrypted` -- whether swap is encrypted (always true on modern macOS)

### Other Useful sysctl Values

| Name | Type | Description |
|---|---|---|
| `hw.memsize` | `uint64_t` | Total physical RAM in bytes |
| `hw.ncpu` | `int` | Number of CPUs |
| `kern.memorystatus_level` | `int` | Memory pressure percentage (0-100) |
| `kern.osproductversion` | `string` | macOS version string |

---

## 8. NSRunningApplication

### Summary

`NSRunningApplication` (AppKit) provides information about running GUI applications: name, icon, bundle ID. It is the bridge between raw PIDs and user-facing app metadata.

**Documentation**: https://developer.apple.com/documentation/appkit/nsrunningapplication

### API Reference

#### Creating from PID

```swift
import AppKit

func getAppInfo(pid: Int32) -> (name: String?, icon: NSImage?, bundleID: String?)? {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        return nil  // PID does not correspond to a GUI application
    }
    return (
        name: app.localizedName,
        icon: app.icon,
        bundleID: app.bundleIdentifier
    )
}
```

#### Key Properties

```swift
// Instance properties
var localizedName: String?          // Display name (CFBundleDisplayName or CFBundleName)
var bundleIdentifier: String?       // e.g., "com.google.Chrome"
var bundleURL: URL?                 // Path to the .app bundle
var executableURL: URL?             // Path to the actual executable
var icon: NSImage?                  // App icon (NSImage)
var processIdentifier: pid_t        // PID
var launchDate: Date?               // When the app was launched
var isActive: Bool                  // Whether it is the frontmost app
var isHidden: Bool                  // Whether it is hidden
var activationPolicy: NSApplication.ActivationPolicy  // .regular, .accessory, .prohibited
```

#### Enumerating All Running Apps

```swift
let allApps = NSWorkspace.shared.runningApplications

for app in allApps {
    print("\(app.localizedName ?? "?") [\(app.processIdentifier)] -- \(app.bundleIdentifier ?? "?")")
}
```

#### Getting Icons for Non-GUI Processes

`NSRunningApplication` only works for processes that have registered with the window server (GUI apps). For daemons and CLI tools, use `NSWorkspace` to get an icon from the executable path:

```swift
func getIconForProcess(path: String) -> NSImage {
    return NSWorkspace.shared.icon(forFile: path)
}
```

#### Observing App Launch/Termination

```swift
let center = NSWorkspace.shared.notificationCenter

center.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil, queue: .main
) { notification in
    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication {
        print("Launched: \(app.localizedName ?? "?") PID=\(app.processIdentifier)")
    }
}

center.addObserver(
    forName: NSWorkspace.didTerminateApplicationNotification,
    object: nil, queue: .main
) { notification in
    // ...
}
```

### Integration with libproc

The recommended approach for Total Recall:

1. Use `proc_listallpids` to get all PIDs (includes daemons, CLI tools, everything).
2. For each PID, try `NSRunningApplication(processIdentifier:)` to get the app icon and bundle ID.
3. If that returns nil (non-GUI process), fall back to `proc_pidpath` + `NSWorkspace.shared.icon(forFile:)` for a file-type icon.
4. Use `proc_pidinfo` with `PROC_PIDTBSDINFO` for the process name regardless, since `localizedName` may differ from the actual process name.

---

## 9. Observation Framework (@Observable)

### Summary

The Observation framework (macOS 14+ / iOS 17+) provides the `@Observable` macro as a replacement for `ObservableObject` + `@Published`. It offers more granular change tracking -- SwiftUI only re-renders views that access the specific properties that changed, not the entire object.

**Documentation**:
- https://developer.apple.com/documentation/observation
- https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
- https://developer.apple.com/videos/play/wwdc2023/10149/ (Discover Observation in SwiftUI)

### Basic Usage

```swift
import Observation

@Observable
class ProcessStore {
    var groups: [SmartGroup] = []
    var systemMemory: SystemMemoryInfo = .empty
    var selectedGroupID: SmartGroup.ID?
    var isRefreshing = false

    // Computed properties are automatically tracked
    var totalUsedMemory: UInt64 {
        groups.reduce(0) { $0 + $1.totalMemory }
    }
}
```

### How It Differs from ObservableObject

| Feature | `ObservableObject` (old) | `@Observable` (new) |
|---|---|---|
| Import | `Combine` | `Observation` |
| Property wrapper | `@Published var` | Plain `var` (auto-tracked) |
| View injection | `@StateObject`, `@ObservedObject` | `@State` (for ownership), direct reference otherwise |
| Environment | `@EnvironmentObject` | `@Environment` |
| Change granularity | Entire object on any `@Published` change | Per-property tracking |
| Class requirement | Yes (class only) | Yes (class only; macro expands to class conformance) |

### Using in SwiftUI Views

```swift
// Owning reference (view creates and owns the object)
struct InspectionWindowView: View {
    @State private var store = ProcessStore()

    var body: some View {
        SmartGroupListView(groups: store.groups)
            .task {
                await store.startPolling()
            }
    }
}

// Non-owning reference (passed in)
struct SmartGroupListView: View {
    var groups: [SmartGroup]  // No wrapper needed; tracked via Observation

    var body: some View {
        List(groups) { group in
            // ...
        }
    }
}
```

### Environment Injection

```swift
// In the App struct
@main
struct TotalRecallApp: App {
    @State private var store = ProcessStore()

    var body: some Scene {
        MenuBarExtra { ... }
        Window("Inspection", id: "inspection") {
            InspectionWindowView()
                .environment(store)
        }
    }
}

// In any descendant view
struct SomeChildView: View {
    @Environment(ProcessStore.self) private var store

    var body: some View {
        Text("Groups: \(store.groups.count)")
    }
}
```

### Combining with Actors

```swift
@MainActor
@Observable
class AppState {
    var groups: [SmartGroup] = []
    var systemMemory: SystemMemoryInfo = .empty

    private let monitor = ProcessMonitor()  // actor

    func refresh() async {
        let (newGroups, memInfo) = await monitor.captureSnapshot()
        // Already on MainActor, safe to update published state
        groups = newGroups
        systemMemory = memInfo
    }
}
```

### Opting Out of Tracking

Use `@ObservationIgnored` for properties that should not trigger view updates:

```swift
@Observable
class ProcessStore {
    var groups: [SmartGroup] = []

    @ObservationIgnored
    var internalCache: [Int32: ProcessInfo] = [:]  // Does not trigger UI updates
}
```

---

## 10. Swift Testing Framework

### Summary

Swift Testing is Apple's modern test framework (included with Swift 6 / Xcode 16), designed to complement and eventually replace XCTest. It uses macros (`@Test`, `@Suite`) and the `#expect` assertion macro for expressive, parallelizable tests.

**Documentation**:
- https://developer.apple.com/xcode/swift-testing/
- https://github.com/swiftlang/swift-testing
- https://www.swift.org/packages/testing.html

### Basic Test Structure

```swift
import Testing

@Test("Process enumeration returns non-empty list")
func testProcessEnumeration() {
    let pids = enumerateAllPIDs()
    #expect(!pids.isEmpty)
    #expect(pids.contains(1))  // launchd is always PID 1
}
```

### @Suite for Organization

```swift
@Suite("Chrome App Profile")
struct ChromeProfileTests {
    let profile = ChromeAppProfile()

    @Test("Detects Chrome main process")
    func detectsMainProcess() {
        let process = ProcessSnapshot(
            pid: 100,
            name: "Google Chrome",
            path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            args: [],
            parentPID: 1
        )
        #expect(profile.matches(process: process))
    }

    @Test("Groups renderer by profile directory")
    func groupsByProfile() {
        // ...
    }
}
```

### Assertions with #expect

```swift
// Basic assertions
#expect(value == 42)
#expect(value != nil)
#expect(array.isEmpty)
#expect(memory > 0)

// With custom message
#expect(groups.count > 0, "Should find at least one smart group")

// Expecting errors
#expect(throws: ProcessError.accessDenied) {
    try readProcessInfo(pid: -1)
}

// Optional unwrap
let info = try #require(getProcessInfo(pid: 1))  // Fails test if nil
#expect(info.name == "launchd")
```

### Parameterized Tests

Ideal for testing app profiles against multiple process fixtures:

```swift
@Test("Detects known system daemons",
      arguments: [
        ("WindowServer", true),
        ("loginwindow", true),
        ("Safari", false),
        ("kernel_task", true)
      ])
func detectsSystemDaemons(name: String, expected: Bool) {
    let process = ProcessSnapshot(pid: 1, name: name, path: "/usr/sbin/\(name)", args: [])
    #expect(SystemServicesProfile().matches(process: process) == expected)
}
```

### Snapshot/Fixture-Based Testing Pattern

This aligns with the PRD's testing strategy of capturing real process snapshots and replaying them:

```swift
@Suite("Snapshot Replay Tests")
struct SnapshotReplayTests {
    // Load fixture once per suite
    static let fixture: [ProcessSnapshot] = {
        let url = Bundle.module.url(
            forResource: "heavy-chrome-usage",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode([ProcessSnapshot].self, from: data)
    }()

    @Test("Chrome profile groups from fixture")
    func chromeGrouping() throws {
        let engine = ProfileEngine(profiles: [ChromeAppProfile()])
        let groups = engine.group(processes: Self.fixture)

        let chromeGroups = groups.filter { $0.appProfile is ChromeAppProfile }
        #expect(chromeGroups.count >= 1)

        // Verify per-profile sub-grouping
        for group in chromeGroups {
            #expect(group.totalMemory > 0)
            #expect(!group.processes.isEmpty)
        }
    }

    @Test("Memory totals match expected values within tolerance")
    func memoryTotals() throws {
        let engine = ProfileEngine(profiles: ProfileRegistry.allProfiles)
        let groups = engine.group(processes: Self.fixture)
        let totalMemory = groups.reduce(0) { $0 + $1.totalMemory }

        // Total should be close to sum of individual process footprints
        let rawTotal = Self.fixture.reduce(0) { $0 + $1.physFootprint }
        // Deduplication means group total <= raw total
        #expect(totalMemory <= rawTotal)
        #expect(totalMemory > rawTotal / 2)  // But not absurdly lower
    }
}
```

### Coexistence with XCTest

Swift Testing and XCTest can coexist in the same target. You can migrate incrementally:

```swift
// Old XCTest (still works)
import XCTest

class LegacyTests: XCTestCase {
    func testSomething() {
        XCTAssertEqual(1 + 1, 2)
    }
}

// New Swift Testing (same target)
import Testing

@Test func modernTest() {
    #expect(1 + 1 == 2)
}
```

### Snapshot Testing with swift-snapshot-testing

The [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) library supports Swift Testing as of late 2024. Use `assertSnapshot` inside `@Test` functions:

```swift
import Testing
import SnapshotTesting

@Test func processListRendering() {
    let view = SmartGroupListView(groups: mockGroups)
    assertSnapshot(of: view, as: .image(size: CGSize(width: 400, height: 600)))
}
```

### Parallel Execution

Swift Testing runs `@Test` functions in parallel by default. To serialize tests that share mutable state:

```swift
@Suite(.serialized)
struct DatabaseTests {
    // These run one at a time
    @Test func test1() { ... }
    @Test func test2() { ... }
}
```

---

## Quick Reference: Complete App Skeleton

Putting it all together for Total Recall:

```swift
import SwiftUI
import Observation

@main
struct TotalRecallApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                Text(appState.memoryLabel)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.menu)

        // Inspection window (opened on demand)
        Window("Total Recall", id: "inspection") {
            InspectionWindowView()
                .environment(appState)
        }
        .defaultSize(width: 900, height: 700)
        .commandsRemoved()

        // Per-process detail window
        WindowGroup("Process Detail", id: "process-detail", for: Int32.self) { $pid in
            if let pid {
                ProcessDetailView(pid: pid)
                    .environment(appState)
            }
        }
    }
}

@MainActor
@Observable
class AppState {
    var groups: [SmartGroup] = []
    var systemMemory: SystemMemoryInfo = .empty
    var memoryLabel: String = "--"
    var isRefreshing = false

    private let monitor = ProcessMonitor()
    private var pollingTask: Task<Void, Never>?

    func startPolling(interval: Duration = .seconds(5)) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = await monitor.captureSnapshot()
        groups = snapshot.groups
        systemMemory = snapshot.memory
        memoryLabel = formatMemory(systemMemory)
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Total Recall") {
            openWindow(id: "inspection")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        Divider()
        if !appState.groups.isEmpty {
            let top = appState.groups.prefix(3)
            ForEach(top) { group in
                Text("\(group.name): \(formatBytes(group.totalMemory))")
            }
            Divider()
        }
        Button("Quit Total Recall") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

---

## Sources

### Apple Developer Documentation
- [MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [MenuBarExtraStyle](https://developer.apple.com/documentation/swiftui/menubarextrastyle)
- [Building and customizing the menu bar](https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
- [openWindow](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow)
- [OutlineGroup](https://developer.apple.com/documentation/swiftui/outlinegroup)
- [DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup)
- [DisclosureGroupStyle](https://developer.apple.com/documentation/swiftui/disclosuregroupstyle)
- [Swift Concurrency](https://developer.apple.com/documentation/swift/concurrency)
- [GlobalActor](https://developer.apple.com/documentation/swift/globalactor)
- [host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64)
- [rusage_info_v4](https://developer.apple.com/documentation/kernel/rusage_info_v4)
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)
- [NSRunningApplication.icon](https://developer.apple.com/documentation/appkit/nsrunningapplication/1529885-icon)
- [NSRunningApplication.bundleIdentifier](https://developer.apple.com/documentation/appkit/nsrunningapplication/1529140-bundleidentifier)
- [Migrating to @Observable](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Managing model data in your app](https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app)
- [Updating an App to Use Swift Concurrency](https://developer.apple.com/documentation/swift/updating_an_app_to_use_swift_concurrency)
- [os_proc_available_memory](https://developer.apple.com/documentation/os/3191911-os_proc_available_memory)
- [Swift Testing](https://developer.apple.com/xcode/swift-testing/)

### WWDC Sessions
- [Bring multiple windows to your SwiftUI app (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10061/)
- [Work with windows in SwiftUI (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10149/)
- [Discover Observation in SwiftUI (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10149/)
- [Meet async/await in Swift (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10132/)
- [Protect mutable state with Swift actors (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10133/)
- [Beyond the basics of structured concurrency (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10170/)
- [Embracing Swift concurrency (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/268/)
- [Stacks, Grids, and Outlines in SwiftUI (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10031/)

### GitHub & Community
- [swift-testing](https://github.com/swiftlang/swift-testing)
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess)
- [TrueTree process.swift (libproc usage)](https://github.com/themittenmac/TrueTree/blob/master/Src/process.swift)
- [Swift Playground -- running processes](https://gist.github.com/macshome/c18bd88a6b8973bd1e5bfaea738f739e)
- [Using libproc.h gist](https://gist.github.com/nguyen-phillip/de66b0ea2144e20ddd844c41c9d93eb9)
- [libproc.h header (XNU source)](https://newosxbook.com/code/xnu-8019/libsyscall/wrappers/libproc/libproc.h)
- [Get virtual memory usage on macOS](https://gist.github.com/algal/cd3b5dfc16c9d577846d96713f7fba40)
- [fastfetch memory stats (matching Activity Monitor)](https://github.com/fastfetch-cli/fastfetch/issues/2171)
- [Getting Running Process Arguments Using Swift](https://gaitatzis.medium.com/getting-running-process-arguments-using-swift-5cfe6c365e44)
- [How to fetch system information with sysctl in Swift](https://sanzaru84.medium.com/how-to-fetch-system-information-with-sysctl-in-swift-on-macos-8ffcdc9b5b99)
- [Swift Testing Complete Guide 2026](https://swiftcrafted.dev/article/complete-guide-swift-testing-first-test-advanced-patterns)
- [Mastering the Swift Testing Framework](https://fatbobman.com/en/posts/mastering-the-swift-testing-framework/)
- [Showing Settings from macOS Menu Bar Items](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
