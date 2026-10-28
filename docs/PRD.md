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

#### Memory River (top)
- Horizontal stacked bar spanning the full physical RAM of the machine
- Process groups occupy the left, sized by proportional resident memory (shared pages split between the processes mapping them), so together they add up to app memory instead of overcounting shared libraries
- After the groups come segments measured from kernel page counts: "Other" (app memory no group accounts for, such as processes Total Recall can't inspect), "Kernel" (wired memory), and "Compressor" (the pool's physical size; its readout says what it holds uncompressed). A toolbar toggle, on by default, shares the Compressor out to the groups instead, charging each pool RAM in proportion to its compressed memory at one machine-wide rate; the readout marks the estimated share with "~"
- A trailing "Available" segment matches the same available figure shown in the summary stats; its hover readout says how much of it is cached files macOS can drop
- The bar splits at a midline. Above it, every segment fills a fixed-height blue band whose width is its in-RAM memory. Below it, each segment hangs an amber stub for what is compressed or swapped, deep enough that the stub's area is that memory on the same scale as the band. A deep stub flags an app far larger than its width suggests. Segments whose non-resident tail is under 100 MB hang no stub, keeping idle daemons quiet
- Groups too narrow to draw to scale (under ~3 pt at true width) fold into one "small groups" segment after the last drawn group, sized and stubbed from their summed memory. The group list still shows each one; hovering the segment highlights their rows, and clicking it selects the first folded group in display order
- Segment labels appear when the segment is wide enough
- Readout line beneath the bar names the hovered segment and its share of total RAM; a group's readout adds its compressed memory, how much of its resident size is shared with other groups, and its swap-in rate when it is reading from swap. The Compressor's readout says what the pool holds uncompressed and how much compressed memory has been written to swap

#### Summary Bar (below the river)
- Total physical memory, used, available, compressed, swap. Used and available follow Activity Monitor and add up to total: used is app memory + wired + compressor pool, available is free pages plus cached files. Compressed shows both the uncompressed size the pool holds and the RAM it occupies
- Memory pressure gauge (mirrors the macOS kernel memory pressure state)

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
- If applicable: how fast this group is reading back from swap right now

#### Detail Panel (on selection)
When a group or process is selected, a side panel or popover shows:
- Full process info (PID, path, command-line args, uptime)
- Memory breakdown: footprint, resident, compressed / swapped, shared, and the current swap-in rate when the group is reading from swap
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
- Per-process: `phys_footprint` as the canonical number; compressed memory from the VM-region walk that measures PSS: each region's compressed pages, with a shared object's compressed pages split evenly across the processes mapping it, so each page counts once. Between walks the figure moves with the kernel's own count, `task_vm_info.compressed`, read every refresh with `task_name_for_pid` + `task_info(TASK_VM_INFO)`; before a process's first walk that count is used directly, clamped to its footprint. A task name port needs no root or entitlements for same-user processes; other users' processes fall back to `phys_footprint - resident_size`
- Per-group: sum of member process footprints, minus shared memory (`RSHRD`) for all-but-one process in the group as a heuristic deduplication. This means group totals will be slightly lower than naive sums and closer to true physical impact, but individual process numbers will still show their full footprint. UI should show the deduplicated total as the headline number.
- System-wide: `host_statistics64()` for free/active/inactive/wired/internal/purgeable/file-backed page counts plus the compressor pool (physical pages occupied and uncompressed pages held)
- Swap per-process: **Critical feature.** The compressed count includes pages in compressor segments that macOS has written to swap. It compresses first and swaps whole segments mixing many processes' pages, so how much of one process's compressed memory is on disk is not knowable from user space — root-only routes report the same number. What is exact per process is swap *activity*: `task_vm_info.ledger_swapins` (lifetime bytes read back from swap), differenced between refreshes, says which processes are waiting on disk right now.
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

1. **Compressed/swap per-process**: the VM-region walk splits compressed pages across the processes mapping them, and `TASK_VM_INFO` via a task name port keeps the figure current between walks for every same-user process; other users' processes fall back to `phys_footprint - resident_size`, and the UI marks a group's figure approximate ("~") when any member used the fallback.

2. **Swap per-process**: Critical feature — this is a key differentiator. The compressed-in-RAM vs swapped-to-disk split is not available per process, so the UI labels the figure "compressed / swapped" and does not estimate the split from system-wide ratios (swap evicts the oldest segments first, so idle daemons are mostly on disk and active apps mostly in RAM). Swap pressure is attributed by each process's live swap-in rate from `ledger_swapins`, shown on any group reading more than 1 MB/s; system-wide swap comes from `vm.swapusage`.

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

**Conclusion**: Full collection is well within budget even for 886 processes. The tiered caching strategy (only query path/args for new PIDs) is still good practice but not critical for typical workloads. A 50ms budget guard protects against pathological cases. Reading each same-user process's compressed count and swap-in counter (`task_name_for_pid` + `TASK_VM_INFO`) adds ~12 ms per refresh, cheap enough to run every cycle.

## Success Criteria

- A user with 400+ processes can open Total Recall and within 5 seconds understand which application is using the most memory
- Chrome users can see per-profile memory breakdown without inspecting individual helper processes
- Claude Code users can identify which session/workspace is the memory hog
- Users never see a process labeled only as `node`, `python3`, or a numeric version string with no further context
- Memory numbers shown match Activity Monitor's "Memory" column to within 5% (since we use the same underlying metric)
