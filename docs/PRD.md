# Total Recall — Product Requirements Document

## Overview

Total Recall is a macOS menu bar app that provides intelligent, human-readable views of memory (RAM) usage. Unlike Activity Monitor — which presents a flat or rigid parent/child list of processes with dozens of columns — Total Recall groups processes by *function* and uses built-in knowledge of specific applications to answer the questions users actually have:

- "Why is my Mac slow?"
- "Which Chrome profile is eating all my RAM?"
- "What even *is* this process?"
- "I have 3 Claude Code sessions — which one is the problem?"

## Problem Statement

Activity Monitor is the only built-in tool for understanding macOS memory usage, and it fails users in several ways:

1. **Process names are opaque.** Dozens of processes named `node`, `python3`, `Google Chrome Helper (Renderer)`, or `volta-shim` give no indication of what they're actually doing or which app they belong to.

2. **Grouping is too rigid.** You can view "All Processes" (flat, overwhelming) or "All Processes, Hierarchically" (misleading, since most things are children of `launchd`). There's no middle ground that groups by logical application.

3. **Too many columns, not enough insight.** Users end up clicking through columns and inspecting command-line arguments just to identify what a process is. The data is there, but the *understanding* isn't.

4. **No app-specific intelligence.** Chrome, Electron apps, Docker, Claude Code, and macOS system services all have unique process hierarchies. A generic process list can't surface the structure within them.

## Target User

Developers and power users who:
- Run memory-heavy workflows (multiple IDEs, browsers with many tabs, Docker, AI tools)
- Want to understand *where* their RAM is going without becoming a sysadmin
- Currently use Activity Monitor but find it frustrating
- May or may not understand concepts like swap, compressed memory, or shared pages

## Core Concepts

### Smart Process Groups

The central abstraction. Instead of showing raw processes, Total Recall organizes them into **groups** that represent logical applications or system functions. Each group:

- Has a human-readable name and icon (e.g., "Google Chrome — Work Profile")
- Aggregates memory from all child/related processes
- Can be expanded to show constituent processes
- Is defined by an **App Profile** (see below)

### App Profiles

An App Profile encodes knowledge about how a specific application manages its processes. For the MVP, these are defined in code. Each profile specifies:

- **Detection rules**: How to identify this app's processes (bundle ID, executable name, command-line patterns)
- **Grouping strategy**: How to organize child processes (e.g., Chrome groups by profile directory; Claude Code groups by workspace)
- **Labeling rules**: How to derive human-readable names for sub-groups (e.g., extracting a tab URL or workspace path from command-line args)
- **Explanations**: Short descriptions of what known process types do (e.g., "GPU Process — handles hardware-accelerated rendering")

### MVP App Profiles

| Application | Key Intelligence |
|---|---|
| **Google Chrome** | Group by profile. Identify renderer/GPU/utility/extension processes. Surface per-profile totals. |
| **Claude Code** | Distinguish CLI vs VS Code-embedded sessions. Group by workspace. Identify the MCP server and language server children. |
| **Docker Desktop** | Group by container where possible. Identify the VM overhead vs container workloads. |
| **VS Code** | Group by window/workspace. Identify extensions host, renderer, terminal shells, and language servers. |
| **Electron apps (generic)** | Identify main vs renderer vs utility. Fall back to bundle name. |
| **macOS system services** | Human-readable names and one-line explanations for common daemons: `WindowServer`, `kernel_task`, `mds_stores` (Spotlight indexing), `nsurlsessiond` (background downloads), `bluetoothd`, etc. |
| **Node.js / Python / Ruby** | When not claimed by a higher-level profile, identify the actual tool (e.g., resolve `node` → "webpack dev server" or `python3` → "jupyter kernel" from command-line args). |
| **Volta / nvm / pyenv shims** | Resolve the shim to the underlying tool and version. |

### Memory Model

Total Recall uses the **physical footprint** (`phys_footprint`) as its primary memory metric. This is the same value shown in Activity Monitor's "Memory" column and Xcode's memory gauge. It represents the actual physical memory impact of a process, accounting for:

- **Resident memory**: Pages currently in physical RAM
- **Compressed memory**: Pages that macOS has compressed in-place to save space (still in RAM, but smaller). This is not paging — it's a transparent optimization introduced in OS X Mavericks.
- **Swapped memory**: Pages written to disk to free up RAM. Heavy swapping causes I/O pressure that *feels* like CPU slowdown.
- **Purgeable memory**: Caches and speculative allocations the kernel can discard instantly without writing to disk. Not a concern for the user, but useful context.

For group totals, the approach is:
- Sum `phys_footprint` of all processes in the group, then subtract `RSHRD` from all-but-one process as a heuristic deduplication (count shared memory once per group, from the largest member)
- The deduplicated total is the headline number; individual processes still show their full footprint when expanded
- This is an approximation — precise deduplication would require kernel-level page table inspection — but it's closer to true physical impact than a naive sum

### Responsible PID

macOS tracks a **responsible PID** for each process — the application that "owns" it even if `launchd` is the literal parent. This is how Activity Monitor groups XPC services. Total Recall uses responsible PID as the *starting point* for grouping, then applies App Profile intelligence on top.

## Product Design

### Menu Bar

A compact menu bar item showing configurable memory stats. Options include:

- **Memory pressure indicator** (green/yellow/red) — the simplest useful signal
- **Used / Available** — e.g., "12.4 / 16 GB"
- **Swap usage** — only shown when non-trivial (e.g., "> 1 GB swap")
- **Top consumer** — e.g., "Chrome: 4.2 GB" (the single largest smart group)

Clicking the menu bar item opens the inspection window.

### Inspection Window

The main interface. A single-pane app window with:

#### Summary Bar (top)
- Total physical memory, used, available, compressed, swap
- Memory pressure gauge (mirrors the macOS kernel memory pressure state)
- Visual breakdown (proportional bar or compact treemap) colored by smart group

#### Smart Group List (main content)
A sorted list of smart groups, largest first. Each row shows:

- App icon + group name
- Total memory footprint (the big number)
- Spark indicator: trending up / stable / trending down
- Expansion disclosure triangle

**Expanded view** for a group shows:
- Individual processes within the group, with their memory and a human-readable label
- For app profiles with sub-groups (e.g., Chrome profiles), a nested level
- Brief explanation text for non-obvious processes (from the App Profile)
- If applicable: how much of this group's memory is in swap

#### Detail Panel (on selection)
When a group or process is selected, a side panel or popover shows:
- Full process info (PID, path, command-line args, uptime)
- Memory breakdown: footprint, resident, compressed, swap, shared
- For groups: note about shared memory between children
- For system services: a plain-English explanation of what this service does and why it might be using memory

### Interactions
- **Sort**: by memory (default), by name, by swap usage (groups without swap data sort to bottom)
- **Search/filter**: find a group or process by name
- **Refresh**: configurable interval (default: 5 seconds); manual refresh button
- **Kill process**: right-click context menu with options:
  - **Quit** (SIGTERM) — polite request; lets the process clean up
  - **Force Quit** (SIGKILL) — immediate kill, no cleanup
  - When targeting a **group**: offer "Quit Parent" (signal the root process only, letting it manage its children) and "Quit All" (signal every process in the group). Both variants available as SIGTERM or SIGKILL.
  - All kill actions require confirmation.

### Exited Process Retention

Short-lived processes can be significant — a process that forks repeatedly, thrashing or doing legitimate work, is invisible if it exits between refreshes. Total Recall captures metadata for every process it observes and can retain data for exited processes.

**Settings** (Preferences):
- **Don't show exited processes** (default) — exited processes leave lists and visualizations naturally shrink/grow
- **Keep for N seconds** — exited processes shown in the list with a visual indicator (dimmed/strikethrough), auto-removed after the configured duration
- **Keep until cleared** — exited processes persist until the user manually clears them, with a reasonable upper bound (e.g., 10,000 entries) to cap memory usage

**Behavior:**
- Retained entries store the last-captured `ProcessSnapshot` (the same data model used by the snapshot capture/testing tool): PID, name, group membership, memory metrics, command-line args, timestamps (first seen, last seen, exited at)
- If a process exits mid-inspection (between refresh cycles), the entry is marked with a flag indicating partial data — the UI shows which fields were captured vs. not
- Retained exited processes contribute to their smart group's history (e.g., "Chrome had 47 renderer processes in the last 5 minutes, 12 currently active") but do **not** count toward the group's current memory total
- A "Clear exited" button in the toolbar clears all retained entries

## Technical Architecture

### Language & Framework
- **Swift** with **SwiftUI** for the UI
- **Minimum deployment target: macOS 26** — modern Macs only, no backwards compatibility burden
- Menu bar implemented with `NSStatusItem` / `MenuBarExtra`
- Inspection window as a standard SwiftUI `Window`

### Data Layer

#### Process Enumeration
- `proc_listallpids()` to enumerate PIDs
- `proc_pid_rusage()` with `RUSAGE_INFO_V6` for memory metrics (especially `ri_phys_footprint`)
- `proc_pidinfo()` with `PROC_PIDTBSDINFO` for parent PID, responsible PID, process name
- `proc_pidpath()` for executable path
- `sysctl` for command-line arguments (`KERN_PROCARGS2`)
- No special entitlements required for same-user processes; Full Disk Access needed for cross-user processes (root daemons, system services)

#### App Profile Engine
- A protocol `AppProfile` with methods: `matches(process:) -> Bool`, `group(processes:) -> [SmartGroup]`
- Concrete implementations for each supported app (e.g., `ChromeProfile`, `ClaudeCodeProfile`)
- A `ProfileRegistry` that runs detection in priority order
- Unmatched processes fall through to a generic grouping by responsible PID + bundle ID

#### Memory Aggregation
- Per-process: `phys_footprint` as the canonical number; best-effort compressed/swap breakdown via `proc_pidinfo` with `PROC_PIDTASKINFO` / `TASK_VM_INFO` (graceful fallback if denied — show footprint only)
- Per-group: sum of member process footprints, minus shared memory (`RSHRD`) for all-but-one process in the group as a heuristic deduplication. This means group totals will be slightly lower than naive sums and closer to true physical impact, but individual process numbers will still show their full footprint. UI should show the deduplicated total as the headline number.
- System-wide: `host_statistics64()` for total/free/active/inactive/wired/compressed page counts
- Swap per-process: **Critical feature.** Note: `vmmap` is NOT feasible for third-party apps (requires `com.apple.system-task-ports` entitlement, Apple-only). Instead, use `ri_phys_footprint - ri_resident_size` from `proc_pid_rusage` as an approximation of compressed + swapped memory per process. This is imprecise (it conflates compressed and swapped) but is the best available signal without privileged entitlements. Combined with system-wide swap totals, this lets us identify which processes are likely contributing most to swap pressure.
- Swap system-wide: `sysctl` with `vm.swapusage`

#### Refresh Loop
- Timer-driven (configurable, default 5s)
- Diff against previous snapshot to compute trends (trending up/down/stable)
- Profile matching runs on each refresh (processes come and go)

### Testing Strategy

The data layer depends on live process state, which is non-deterministic and environment-specific. To make the App Profile engine and memory aggregation logic testable:

- **Snapshot capture tool**: A debug/CLI mode that dumps the current process list to a JSON file as an array of `ProcessSnapshot` — the same data model used by exited process retention. Fields: PID, name, path, command-line args, parent PID, responsible PID, memory metrics, and any other fields the profile engine uses. This is the "raw scan" output.
- **Snapshot replay**: The profile engine and aggregation logic accept a snapshot as input (not just live data). Tests load checked-in snapshot files and assert on grouping, labeling, and memory totals.
- **Checked-in test fixtures**: Capture snapshots from real systems with interesting process mixes (heavy Chrome usage, multiple Claude Code sessions, Docker containers, etc.) and commit them as test data. These serve as regression tests for profile detection and grouping logic.
- **Partial data testing**: Include snapshots with missing fields (simulating processes where `proc_pidinfo` was denied) to verify graceful fallback behavior.

### App Sandbox & Distribution
- Targeting **direct distribution** (DMG / Homebrew) for MVP — avoids App Store restrictions on process inspection APIs
- App Sandbox will likely need to be **disabled** since `proc_pid_rusage` on other users' processes and `KERN_PROCARGS2` are restricted in sandbox
- Hardened Runtime enabled, signed with Developer ID
- **Permissions note**: Research indicates that `proc_*` APIs work for same-user processes without special entitlements, and FDA (Full Disk Access) controls file-system TCC access, not Mach process inspection. For root-owned system processes, a non-sandboxed app may get basic info (name, PID, footprint) but command-line args may be restricted. The app should detect when data is incomplete for a process and show a "limited info" indicator. FDA may still be useful if future features need to read process-owned files, but is not required for MVP process monitoring.

## MVP Scope

### In Scope
- Menu bar presence with memory pressure + used/total display
- Inspection window with smart group list, expandable groups, and detail view
- App Profiles for: Chrome, Claude Code, VS Code, Docker, Electron (generic), macOS system services, Node/Python/Ruby runtime resolution, Volta/nvm shims
- Memory metrics: footprint, best-effort per-process compressed/swap, per-group deduplicated totals (RSHRD heuristic), trending
- Sort, search/filter, manual + auto refresh
- Exited process retention (3 modes: don't show, keep for N seconds, keep until cleared)
- Kill actions: Quit/Force Quit on processes; Quit Parent/Quit All on groups
- Snapshot capture for testing; checked-in test fixtures for profile engine

### Out of Scope (Future)
- User-defined or plugin-based App Profiles
- Historical memory tracking / timeline graphs
- Memory leak detection or alerts
- Notifications / warnings when memory pressure is high
- Safari tab-level detail (requires accessibility or extension, complex)
- Per-process network or CPU in the same view (stay focused on memory)
- App Store distribution
- iOS / iPadOS version

## Resolved Decisions

1. **Compressed/swap per-process**: Best-effort approach. Try `proc_pidinfo` with `PROC_PIDTASKINFO` / `TASK_VM_INFO` for per-process breakdown. Fall back gracefully to footprint-only when denied. UI shows whatever data is available without pretending to have more than it does.

2. **Swap per-process**: Critical feature — this is a key differentiator. Research confirmed `vmmap` is not available to third-party apps (requires Apple-only entitlement). The best available approach is `ri_phys_footprint - ri_resident_size` as an approximation of non-resident memory (compressed + swapped). Combined with system-wide swap from `vm.swapusage`, this lets us rank which processes likely contribute most to swap pressure.

3. **Shared memory deduplication**: Use RSHRD subtraction heuristic. For a group of N processes, count shared memory once (from the largest process) and subtract RSHRD from the remaining N-1. The deduplicated total is the headline number. Individual processes still show their full footprint when expanded.

4. **Permissions**: Prompt for Full Disk Access on first launch. Without it, the app works for current-user processes but shows a "limited visibility" indicator for system processes. FDA enables full `proc_pidinfo` / `KERN_PROCARGS2` data for root-owned daemons.

## Resolved: Refresh Performance

Benchmarked on a 32 GB Mac with 886 processes (see `tools/benchmark-collection.swift`):

| API | Total (886 PIDs) | Per-PID | Notes |
|---|---|---|---|
| `proc_listallpids` | 0.17 ms | — | Negligible |
| `proc_pid_rusage` | 2.6 ms | 2.9 μs | Core memory metric |
| `proc_pidinfo` + `proc_pidpath` | 2.8 ms | 3.2 μs | Cache per PID |
| `KERN_PROCARGS2` | 9.2 ms | 10.4 μs | Cache per PID, ~3.5x more expensive |
| `host_statistics64` + `vm.swapusage` | 0.01 ms | — | Negligible |
| **Full collection** | **~15 ms** | — | 0.3% of a 5s interval |

**Conclusion**: Full collection is well within budget even for 886 processes. The tiered caching strategy (only query path/args for new PIDs) is still good practice but not critical for typical workloads. A 50ms budget guard protects against pathological cases.

## Remaining Open Questions

1. **Swap approximation accuracy**: The `ri_phys_footprint - ri_resident_size` heuristic conflates compressed and swapped memory. Need to test on a system under memory pressure to see if this is useful enough to surface in the UI, or if it's too misleading. May need to label it "Non-Resident Memory" rather than "Swap" to be honest about what it measures.

## Success Criteria

- A user with 400+ processes can open Total Recall and within 5 seconds understand which application is using the most memory
- Chrome users can see per-profile memory breakdown without inspecting individual helper processes
- Claude Code users can identify which session/workspace is the memory hog
- Users never see a process labeled only as `node`, `python3`, or a numeric version string with no further context
- Memory numbers shown match Activity Monitor's "Memory" column to within 5% (since we use the same underlying metric)
