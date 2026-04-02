# feat: Total Recall MVP — macOS Smart Memory Monitor

## Enhancement Summary

**Deepened on:** 2026-04-01
**Review agents used:** Architecture Strategist, Performance Oracle, Security Sentinel, Code Simplicity Reviewer, Pattern Recognition Specialist, Framework Docs Researcher

### Key Improvements

1. **AppProfile protocol redesigned** — single `classify([ProcessSnapshot])` replacing `claims()` + `group()` to enable context-aware process claiming (avoids Chrome/Electron/Claude Code ownership conflicts)
2. **Secret redaction layer** — command-line args run through `RedactionFilter` at capture time (before storage, display, or serialization) to mask passwords, tokens, and API keys
3. **SmartGroup gets `stableIdentifier`** — profile name + grouping key (e.g., `"chrome:Profile 1"`) enables correct trending across snapshots as processes join/leave groups
4. **ProfileRegistry runs inside actor** — classification moved off `@MainActor` to keep CPU-bound regex/string matching on the background thread
5. **Memory River built as HStack of Rectangles** — gives per-segment hover, click, accessibility, and spring animation with no custom `animatableData` math
6. **Synthetic test fixtures only** — never capture real process data to JSON (secrets in command-line args). Build fixtures programmatically with fake data.
7. **Phase 3 split into 3a (data pipeline) and 3b (visual design)** — de-risks the architecture integration from the UI effort

### Scope Reductions (from Simplicity Review)

- MVP profiles reduced from 8 to 4 (Chrome, System Services, Electron, Generic). Claude Code, VS Code, Docker, Runtime deferred to Phase 5.
- Sparkle auto-updates deferred to post-MVP
- Animations use SwiftUI defaults; only pressure dot pulse is custom
- OKLCH colors pre-computed as sRGB constants with small embedded converter for hover
- Search/filter and sort deferred — group list is ~15 rows, sort by memory always
- Snapshot versioning removed — `Codable` decode errors are sufficient

### Critical Security Additions

- `RedactionFilter` for command-line args (passwords, tokens, bearer headers)
- `#if DEBUG` gate on snapshot capture (never available in release builds)
- PID denylist for kill actions (kernel_task, WindowServer, loginwindow, etc.)
- Kill verification uses full `ProcessIdentity` (pid + path + startTime), not just name
- Audit logging for all kill actions via `os_log`

### Performance Architecture

- `SmartGroup` as struct with whole-array replacement on 5s cycle (acceptable per @Observable research)
- `.contentTransition(.numericText())` instead of custom cross-fade animations
- Dead zone on river animations (skip if segment changes < 0.5%)
- menuBarOnly refresh skips all per-process calls (just `host_statistics64` + `vm.swapusage`)
- Immediate full refresh triggered when inspection window opens
- Store only aggregate footprint per group for trending (not full process snapshots)

---

## Overview

Build Total Recall from scratch: a macOS 26 menu bar app that provides intelligent, grouped views of memory (RAM) usage using app-specific knowledge. The app replaces Activity Monitor for developers who want to understand *where* their RAM is going.

**PRD**: `docs/PRD.md`
**Research**: `docs/RESEARCH.md`

## Problem Statement

Activity Monitor shows opaque process names, rigid grouping (flat or parent/child via launchd), and too many columns. Developers running Chrome, VS Code, Claude Code, Docker, and system services can't quickly answer "what's eating my RAM?" without manually inspecting command-line arguments.

## Proposed Solution

A menu bar app with:
1. A compact **menu bar item** showing memory pressure + usage
2. An **inspection window** with smart process groups that aggregate by logical application
3. **App Profiles** encoding per-app knowledge (Chrome profiles, Claude Code workspaces, Docker containers, etc.)

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Layer                     │
│  ┌──────────────┐  ┌────────────────────────────┐   │
│  │ MenuBarExtra  │  │    Inspection Window        │   │
│  │ (.menu style) │  │  ┌──────────┐ ┌─────────┐  │   │
│  │  - pressure   │  │  │ Summary  │ │ Detail  │  │   │
│  │  - used/total │  │  │   Bar    │ │  Panel  │  │   │
│  │  - open btn   │  │  ├──────────┤ │         │  │   │
│  └──────────────┘  │  │  Smart   │ │ (on     │  │   │
│                     │  │  Group   │ │ select) │  │   │
│                     │  │  List    │ │         │  │   │
│                     │  └──────────┘ └─────────┘  │   │
│                     └────────────────────────────┘   │
├─────────────────────────────────────────────────────┤
│              @Observable AppState (@MainActor)        │
│  - groups: [SmartGroup]                              │
│  - systemMemory: SystemMemoryInfo                    │
│  - retainedExited: [ProcessSnapshot]                 │
│  - expandedGroups: Set<ID>                           │
├─────────────────────────────────────────────────────┤
│              actor ProcessMonitor                     │
│  - collectSnapshot() → [ProcessSnapshot]             │
│  - pidCache: [pid_t: CachedProcessInfo]              │
│  - polling loop (Task + sleep)                       │
├─────────────────────────────────────────────────────┤
│              ProfileRegistry                         │
│  - profiles: [AppProfile]                            │
│  - classify(snapshots:) → [SmartGroup]               │
├─────────────────────────────────────────────────────┤
│              System APIs (libproc / sysctl / Mach)   │
│  proc_listallpids, proc_pid_rusage, proc_pidinfo,   │
│  proc_pidpath, KERN_PROCARGS2, host_statistics64,    │
│  vm.swapusage                                        │
└─────────────────────────────────────────────────────┘
```

**Key architectural decisions** (from research):
- **`@Observable`** (not `ObservableObject`) for per-property change tracking — critical for a 500+ process list
- **Actor** for the polling loop — serializes proc_* calls off main thread
- **`MenuBarExtra(.menu)`** + separate `Window(id:)` — menu bar shows quick stats, button opens the full inspection window
- **`LSUIElement = YES`** — no Dock icon, menu-bar-only app
- **macOS 26 minimum** — use latest Swift/SwiftUI without compat burden
- **No App Sandbox** — required for proc_* APIs on other processes
- **No FDA required** for MVP — proc_* APIs work for same-user processes without it

### Key Technical Constraints

1. **`vmmap` is NOT available** to third-party apps (requires `com.apple.system-task-ports`). Per-process swap approximation uses `ri_phys_footprint - ri_resident_size` instead.
2. **`KERN_PROCARGS2` is expensive** — cache per PID, only query new processes.
3. **`proc_pid_rusage` is cheap** (~1-5μs per PID) — safe to call for all processes every 5s.
4. **Shared memory deduplication** uses RSHRD subtraction heuristic, not exact kernel page inspection.

### Design Decisions (from spec-flow analysis)

The following gaps were identified by spec-flow analysis and are resolved here with default assumptions. These should be validated with the user before or during implementation.

**Menu bar interaction model**: Approach A — `.menu` style dropdown with quick stats + "Open Total Recall" button (⌘⇧M). This matches standard macOS menu bar patterns. The dropdown re-renders each time it opens, showing fresh stats.

**Window lifecycle**: Closing the inspection window keeps the app running in the menu bar. Cmd+W closes the window; Cmd+Q quits the app. Reopening via menu bar dropdown or ⌘⇧M.

**Two-tier refresh**: Fast (5s, full data) when inspection window is visible. Slow (30s, system-wide stats only for menu bar) when it's not. Saves CPU/battery.

**Kill action safety**:
- Re-verify process name + start time match before sending any signal (guards against PID reuse)
- Disable "Quit Parent" / "Quit All" on system services groups and any group whose root is PID 1 (launchd)
- Confirmation dialog names the target and warns about data loss: "Force Quit 'Google Chrome' (47 processes)? Unsaved work will be lost."

**Trending algorithm**: Rolling window of 6 snapshots (30s at default 5s). "Trending up" if linear slope > +5% of current value. "Trending down" if < -5%. Otherwise "stable". First snapshot shows no indicator (dash).

**Group lifecycle**: Groups with zero active processes AND zero retained exited processes are removed from the list. In "keep until cleared" mode, a quit Chrome still shows as a dimmed group with its exited processes.

**RSHRD explanation**: Info icon on group total with tooltip: "Adjusted for shared memory. Individual processes may sum to more than the group total."

**Launch at Login**: Settings toggle (off by default) using `SMAppService.mainApp.register()`.

**Empty/loading states**: Spinner on first load. "No matching processes" for empty search. "Limited visibility — some system processes require elevated permissions" banner when data is restricted.

**Detail panel**: Slides in on selection, disappears when deselected. Not always visible.

**Accessibility**: VoiceOver labels on all interactive elements. Memory pressure indicator includes text label (not color-only). Keyboard navigation for the group list (arrow keys, Enter to expand).

**Snapshot versioning**: Include a `version: Int` field in fixture JSON. Increment when `ProcessSnapshot` model changes. Tests fail fast on version mismatch with a clear message.

**Large groups**: Show first 20 processes when expanded, with a "Show all (N)" button for groups with more.

### Implementation Phases

---

#### Phase 1: Project Scaffolding & Data Layer

**Goal**: Xcode project builds, can enumerate processes and read memory stats from the command line.

**Tasks:**

1. **Create Xcode project**
   - macOS App target, Swift/SwiftUI, macOS 26 deployment target
   - Bundle ID: `com.totalrecall.app` (or similar)
   - `LSUIElement = YES` in Info.plist
   - Disable App Sandbox in entitlements
   - Enable Hardened Runtime
   - Files: `TotalRecall.xcodeproj`, `TotalRecall/TotalRecallApp.swift`, `Info.plist`, `TotalRecall.entitlements`

2. **`ProcessSnapshot` data model**
   - Shared model used by data layer, exited process retention, AND snapshot testing
   - `Codable` + `Sendable` (crosses actor boundaries, serialized for test fixtures)
   - Fields: `pid`, `name`, `path`, `commandLineArgs` (**redacted at capture time** — see RedactionFilter), `parentPid`, `responsiblePid`, `bundleIdentifier`, `physFootprint`, `residentSize`, `sharedMemory` (RSHRD), `startTime` (seconds + microseconds from `pbi_start_tvsec`/`pbi_start_tvusec`), `firstSeen`, `lastSeen`, `exitedAt`, `isPartialData`
   - `processIdentity: ProcessIdentity` — computed struct of `(pid, path, startTime)` used for kill verification and PID-reuse cache guard
   - File: `TotalRecall/Models/ProcessSnapshot.swift`

   **`RedactionFilter`** — applied at capture time in `SystemProbe.getCommandLineArgs()`:
   - Masks values after known secret flags: `--password`, `--token`, `-p`, `--secret`, `--key`, `--auth`, `--api-key`, `--db-password`
   - Masks `-H "Authorization: Bearer ..."` headers
   - Masks `-e KEY=VALUE` / `--env KEY=VALUE` environment variable assignments
   - Masks long base64-like strings (>40 chars of `[A-Za-z0-9+/=]`)
   - Replaces with `[REDACTED]`
   - File: `TotalRecall/DataLayer/RedactionFilter.swift`

3. **`SystemMemoryInfo` model**
   - Fields from `host_statistics64`: `totalPhysical`, `used`, `free`, `active`, `inactive`, `wired`, `compressed`, `memoryPressure` (green/yellow/red)
   - Swap from `vm.swapusage`: `swapTotal`, `swapUsed`
   - File: `TotalRecall/Models/SystemMemoryInfo.swift`

4. **`SystemProbe` — low-level API wrapper**
   - Static functions wrapping libproc/sysctl/Mach calls
   - `listAllPIDs() -> [pid_t]`
   - `getProcessInfo(pid:) -> ProcessSnapshot?` — combines `proc_pid_rusage`, `proc_pidinfo(PROC_PIDTBSDINFO)`, `proc_pidpath`
   - `getCommandLineArgs(pid:) -> [String]?` — `sysctl KERN_PROCARGS2` with binary parsing
   - `getSystemMemory() -> SystemMemoryInfo` — `host_statistics64` + `vm.swapusage`
   - `getAppIcon(pid:) -> NSImage?` — `NSRunningApplication(processIdentifier:)?.icon` with fallback to `NSWorkspace.shared.icon(forFile:)`
   - File: `TotalRecall/DataLayer/SystemProbe.swift`

5. **`ProcessMonitor` actor — with tiered collection strategy**

   Benchmarked on a 32 GB Mac with 886 processes (`tools/benchmark-collection.swift`):

   | Tier | What | Cost (886 PIDs) | Per-PID | Strategy |
   |---|---|---|---|---|
   | 0 | `proc_listallpids` | 0.17 ms | — | Every cycle |
   | 1 | `proc_pid_rusage` (memory) | 2.6 ms | 2.9 μs | Every cycle — this is the core product |
   | 2 | `proc_pidinfo` + `proc_pidpath` | 2.8 ms | 3.2 μs | Cache per PID, only query new PIDs |
   | 3 | `KERN_PROCARGS2` (cmdline args) | 9.2 ms | 10.4 μs | Cache per PID, only query new PIDs |
   | Sys | `host_statistics64` + `vm.swapusage` | 0.01 ms | — | Every cycle |

   **Full collection (all tiers, all PIDs): ~15ms** — well under a 50ms budget, even at 886 processes. The tiered strategy is defensive design for worst-case systems (2000+ processes, kernel under load), not a necessity on typical hardware.

   **Collection architecture:**
   - Owns the polling loop (`Task` + `Task.sleep(for:)`) at `.utility` priority
   - **Two-tier refresh**: `.full` (all tiers) when inspection window visible, `.menuBarOnly` (tier 0+1+sys) when not
   - **PID cache**: `path`, `commandLineArgs`, `procInfo` keyed by PID — only query new PIDs for tiers 2-3
   - Cache eviction: remove entries for PIDs that disappear from `proc_listallpids`
   - **Budget guard**: measure elapsed time with `ContinuousClock`. If a full cycle exceeds 50ms, log a warning and skip remaining tier 3 calls, carrying forward cached data. This guards against pathological cases (thousands of processes, kernel under pressure).
   - **Cooperative cancellation**: check `Task.isCancelled` between tiers. If the user closes the window mid-collection, the cycle stops cleanly.
   - **Yield between tiers**: call `Task.yield()` between tier 1 and tier 2/3 to let UI work proceed. Not strictly necessary at 15ms total, but good practice.
   - **Owns `ClassifierRegistry`** and runs classification inside the actor context (keeps CPU-bound regex/string work off @MainActor)
   - Returns `([ProcessGroup], SystemMemoryInfo, exitedPIDs: Set<pid_t>)` — fully classified groups, not raw snapshots
   - `AppState` receives finished results and does only: assign properties, compute trends, manage retention
   - **PID-reuse cache guard**: when serving cached path/args, verify process start time matches. Evict and re-query on mismatch.
   - File: `TotalRecall/DataLayer/ProcessMonitor.swift`

6. **Snapshot capture & test fixtures**
   - Snapshot capture tool: **`#if DEBUG` only** (never available in release builds — security requirement, prevents process data exfiltration)
   - Dumps `ProcessMonitor` output to JSON for local debugging
   - **Test fixtures are synthetic, not captured from real machines** — command-line args on real systems contain secrets (passwords, tokens, API keys). Build fixtures programmatically with realistic but fake data:
     ```swift
     static let chromeFixture = ProcessSnapshot(
         pid: 1234, name: "Google Chrome Helper (Renderer)",
         path: "/Applications/Google Chrome.app/.../Helper",
         commandLineArgs: ["--type=renderer", "--profile-directory=Default"],
         ...
     )
     ```
   - Add `Fixtures/*.json` to `.gitignore` (any real captures stay local)
   - Files: `TotalRecall/DataLayer/SnapshotCapture.swift` (`#if DEBUG`), `TotalRecallTests/Fixtures/FixtureBuilder.swift`

**Success criteria:**
- `ProcessMonitor` can poll and print all processes with memory stats
- `ProcessSnapshot` round-trips through JSON
- At least one captured fixture checked in

**Estimated files:** 6-8 Swift files, 1-2 JSON fixtures

---

#### Phase 2: App Profile Engine

**Goal**: Processes are classified into smart groups by the profile engine. Testable against fixtures.

**Tasks:**

1. **`ProcessGroup` model** (renamed from `SmartGroup` — "smart" is marketing, not technical)
   - Fields: `id`, `stableIdentifier: String` (e.g., `"chrome:Profile 1"`, `"system:WindowServer"` — constructed by the classifier, persists across snapshots even as member processes change), `name`, `icon` (NSImage?), `classifierName` (which classifier created it), `processes: [ProcessSnapshot]`, `subGroups: [ProcessGroup]?` (e.g., Chrome profiles), `deduplicatedFootprint` (sum minus RSHRD heuristic), `nonResidentMemory` (swap approximation sum), `explanation: String?`
   - `trend` is a **stored property set by AppState** (not computed — ProcessGroup cannot compute trends without historical data it doesn't own)
   - Conforms to `Identifiable` (via `stableIdentifier`), `Sendable` (crosses actor boundary)
   - File: `TotalRecall/Models/ProcessGroup.swift`

2. **`ProcessClassifier` protocol** (renamed from `AppProfile` for clarity)
   ```swift
   protocol ProcessClassifier {
       var name: String { get }
       /// Receives the full remaining (unclaimed) process list.
       /// Returns groups and the PIDs consumed, enabling context-aware claiming
       /// (e.g., a `node` process claimed by ClaudeCodeProfile if its parent is claude).
       func classify(_ processes: [ProcessSnapshot]) -> ClassificationResult
   }

   struct ClassificationResult {
       let groups: [ProcessGroup]
       let claimedPIDs: Set<pid_t>
   }
   ```
   - **Why single `classify()` instead of `claims()` + `group()`**: The two-phase approach breaks when ownership depends on context (Chrome vs Electron overlap, Claude Code's `node` children). Each classifier sees the full unclaimed list and can make holistic decisions.
   - **No `priority` field** — the `ClassifierRegistry` maintains an explicit ordered array. Priority is the position in the array, not a sortable integer.
   - File: `TotalRecall/Profiles/ProcessClassifier.swift`

3. **`ClassifierRegistry`**
   - Holds ordered array of `ProcessClassifier` implementations
   - `classify(snapshots: [ProcessSnapshot]) -> [ProcessGroup]`
     - For each classifier in order, pass remaining unclaimed processes
     - Classifier returns groups + claimed PIDs; remove claimed PIDs from remaining
     - `GenericClassifier` (last in order) groups all remaining by responsible PID + bundle ID
   - **Runs inside the `ProcessMonitor` actor** (not on @MainActor) — classification involves regex/string matching on command-line args, which is CPU work
   - Computes RSHRD deduplication per group
   - Asserts `subGroups` depth <= 2 after classification (prevents accidental infinite recursion)
   - File: `TotalRecall/Profiles/ClassifierRegistry.swift`

4. **MVP Classifiers** (4 for MVP, 4 deferred — ordered by registry position):

   a. **`ChromeClassifier`** — detect by executable path containing `Google Chrome`. Group by `--profile-directory=` arg. Label renderer/GPU/utility/extension processes. Identify per-profile sub-groups.
      File: `TotalRecall/Profiles/ChromeClassifier.swift`

   b. **`ElectronClassifier`** — generic for Electron apps (detect by `Electron` framework in path or `--type=` args). Group main/renderer/utility. Fall back to bundle name. Covers VS Code, Slack, Discord, etc. without custom logic.
      File: `TotalRecall/Profiles/ElectronClassifier.swift`

   c. **`SystemServicesClassifier`** — dictionary of known daemon names → human-readable descriptions. `WindowServer` → "Window compositing and rendering", `mds_stores` → "Spotlight search indexing", `kernel_task` → "macOS kernel (memory management, I/O)", etc.
      File: `TotalRecall/Profiles/SystemServicesClassifier.swift`

   d. **`GenericClassifier`** — catch-all (always last). Groups by responsible PID, uses bundle ID or executable name as label. Gets app icon from `NSRunningApplication`.
      File: `TotalRecall/Profiles/GenericClassifier.swift`

   **Shared utility**: `CommandLineParser` — extracts process roles, flags, and discriminators from command-line args. Consumed by classifiers rather than each re-implementing arg parsing.
      File: `TotalRecall/Profiles/CommandLineParser.swift`

   **Deferred to Phase 5 (post-MVP classifiers):**
   - `ClaudeCodeClassifier` — workspace grouping, CLI vs VS Code distinction
   - `VSCodeClassifier` — workspace/window grouping, extension host identification
   - `DockerClassifier` — VM overhead vs container workloads
   - `RuntimeClassifier` — resolve `node`/`python3`/`ruby` to actual tools, volta/nvm/pyenv shims

5. **Profile engine tests**
   - Load fixture JSON, run through `ProfileRegistry.classify()`, assert on group names, membership, and memory totals
   - Test partial data handling (processes with missing command-line args)
   - Test RSHRD deduplication math
   - File: `TotalRecallTests/ProfileEngineTests.swift`

**Success criteria:**
- Fixture-based tests pass: Chrome processes grouped by profile, Claude Code by workspace, system services labeled
- `ProfileRegistry.classify()` handles 500+ process snapshots in < 50ms
- Processes are never double-claimed by multiple profiles

**Estimated files:** 10-12 Swift files

---

#### Phase 3a: Data Pipeline Integration & Basic UI

**Goal**: Full data pipeline wired end-to-end (ProcessMonitor → ClassifierRegistry → AppState → Views) with a minimal diagnostic UI. Validates architecture before investing in visual design.

**Tasks:**

1. **`AppState` — the observable model**
   - `@MainActor @Observable class AppState`
   - Properties: `groups: [ProcessGroup]`, `systemMemory`, `retainedExited`, `selectedGroupID`, `isInspectionWindowVisible`
   - Receives finished `[ProcessGroup]` from `ProcessMonitor` actor — does NOT run classification itself
   - Computes trends: maintains ring buffer of 6 aggregate footprints per group (keyed by `stableIdentifier`). Only stores the footprint value, not full process lists (~1KB total).
   - Manages exited process retention (single mode for MVP: keep 60 seconds, then remove)
   - **Immediate full refresh**: when `isInspectionWindowVisible` transitions to `true`, cancels current sleep and triggers immediate `.full` collection
   - File: `TotalRecall/AppState.swift`

2. **Window visibility detection**
   - Try `@Environment(\.appearsActive)` first (macOS 26) — if it correctly reports `false` when the window is closed/minimized, use it
   - Fallback: `NSWindow` notification bridge via `NSViewRepresentable` (didBecomeKey, willClose, didMiniaturize, didDeminiaturize)
   - File: `TotalRecall/Views/WindowVisibilityTracker.swift`

3. **Basic app shell**
   - `TotalRecallApp: App` with `MenuBarExtra(.menu)` + `Window(id: "inspection")`
   - Menu bar: pressure dot + used/total + "Open Total Recall" button
   - Inspection window: plain `List` of group names + memory numbers (no design, no river, no animations)
   - Validates: data flows correctly, refresh works, groups appear, trends compute
   - Activation policy toggle: `.regular` when window opens, `.accessory` when it closes
   - File: `TotalRecall/TotalRecallApp.swift`

4. **Kill action infrastructure**
   - `ProcessIdentity` struct: `(pid, executablePath, startTimeSec, startTimeUsec)`
   - Before kill: re-query `proc_pidinfo` and compare full identity. Abort if stale.
   - PID denylist: `kernel_task` (PID 0), `launchd` (PID 1), `WindowServer`, `loginwindow`, `opendirectoryd`, `diskarbitrationd`, any process with UID != current user
   - Group-level kill disabled for `SystemServicesClassifier` groups
   - Self-protection: refuse to kill own PID
   - Audit logging: every kill action logged via `os_log` with full ProcessIdentity and result
   - Confirmation dialog: names the target + warns about data loss
   - File: `TotalRecall/DataLayer/ProcessActions.swift`

**Success criteria:**
- App launches, menu bar shows live stats
- Inspection window shows grouped processes from ClassifierRegistry
- Trends show after 30 seconds of running
- Can force-quit a process with PID verification
- Kill denied on system processes
- Close window → slow refresh, open → immediate full refresh

---

#### Phase 3b: Visual Design & Polish

**Goal**: The full "Observatory" visual design applied to the working data pipeline.

##### Design Direction — "The Observatory"

**Concept**: You're standing in a mission control room, watching your system's memory through a precision instrument. Not the sterile white of Apple's Activity Monitor, not a gamer's RGB dashboard — something closer to a Dieter Rams oscilloscope or a Bloomberg terminal stripped to its essence. Every pixel communicates. Nothing decorates.

**The one thing someone will remember**: The **memory river** — a horizontal stacked bar that flows across the top of the window like a geological cross-section, showing exactly where your RAM is going at a glance. Each stratum is a smart group, its width proportional to its footprint. It's the first thing you see, and it tells the whole story before you read a single number.

---

**Typography**:
- **Numbers/metrics**: `SF Mono` at bold weights. Memory figures are the *heroes* of every row — they should read like the altitude readout on an instrument panel. Size them at 15pt in the group list, 20pt in the detail panel, 11pt in the menu bar. Always `.monospacedDigit()` so columns don't jitter on refresh.
- **Labels/names**: `SF Pro Medium` at 13pt. Slightly smaller than the numbers — the hierarchy is: number > name > explanation. Never bold for labels (that's reserved for numbers).
- **Explanations/secondary**: `SF Pro` regular at 11pt, in secondary text color. These whisper context; they never compete with the data.
- **Detail panel headers**: `SF Pro Display` semibold at 16pt, with generous letter-spacing (+0.5pt). These are section titles, not data.

---

**Color System**:

The palette is built in **OKLCH** (perceptually uniform) to guarantee that group colors are equally readable against the dark background regardless of hue. Every group accent is at **L=0.72, C=0.15** — vivid enough to pop against the dark surface, muted enough to not scream.

```
Background layer:
  --bg-void:       oklch(0.13  0.005  260)   // near-black with a cold blue undertone
  --bg-surface:    oklch(0.16  0.005  260)   // rows, cards — barely lifted off void
  --bg-hover:      oklch(0.20  0.008  260)   // hover state — subtle brightening
  --bg-selected:   oklch(0.22  0.015  260)   // selected row — hint of the accent hue

Text:
  --text-primary:  oklch(0.93  0.005  90)    // warm off-white, not pure white
  --text-secondary:oklch(0.55  0.005  260)   // cool gray, recedes clearly
  --text-muted:    oklch(0.38  0.005  260)   // exited processes, timestamps

Group accents (all at L=0.72, C=0.15 for equal visual weight):
  --chrome:        oklch(0.72  0.15   260)   // blue
  --vscode:        oklch(0.72  0.15   240)   // teal-blue
  --claude:        oklch(0.72  0.15   55)    // warm copper
  --docker:        oklch(0.72  0.15   250)   // cyan-blue
  --system:        oklch(0.72  0.15   35)    // burnt orange
  --electron:      oklch(0.72  0.15   310)   // violet
  --runtime:       oklch(0.72  0.15   155)   // muted green
  --generic:       oklch(0.55  0.02   260)   // desaturated gray — intentionally quiet

Signals (brighter, higher chroma for alarm states):
  --pressure-ok:   oklch(0.75  0.20   145)   // clear green
  --pressure-warn: oklch(0.82  0.18   85)    // amber
  --pressure-crit: oklch(0.68  0.22   25)    // urgent red
  --swap-warn:     oklch(0.76  0.16   65)    // deep gold
  --trend-up:      oklch(0.68  0.18   25)    // red-tinted (bad: growing)
  --trend-down:    oklch(0.72  0.16   155)   // green-tinted (good: shrinking)
```

**Why OKLCH**: Two blues (Chrome, VS Code) at the same lightness/chroma but different hues are distinguishable even to deuteranopia users. The equal-lightness constraint means the treemap bar reads as a clean stripe of color blocks, not a jarring patchwork. The SwiftUI implementation uses `Color(red:green:blue:)` converted from OKLCH at build time (or a small OKLCH→sRGB helper).

---

**Spatial Composition & Layout**:

The window is 780×560pt default, split into three vertical zones with deliberately different densities:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  THE MEMORY RIVER (Summary Bar)                                            │
│  ═══════════════════════════════════════════════════════════════            │
│                                                                             │
│  ┌─ Stacked bar: width ∝ footprint, colored by group ─────────────────┐    │
│  │▓▓▓▓▓▓▓▓▓▓▓▓ Chrome ▓▓▓▓▓▓▓▓ VS Code ▓▓▓▓▓ Docker ▓▓▓ Sys ░░░░░░│    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│   16.0 GB                    12.4 GB USED             3.6 GB FREE          │
│   ───────                    ──────────── ●           ───────────          │
│   total                      compressed: 3.1 GB       pressure: NORMAL     │
│                              swap: 2.1 GB                                  │
│                                                                             │
├── 40pt breathing room ──────────────────────────────────────────────────────┤
│                                                                             │
│  SMART GROUPS                                           DETAIL             │
│  ┌──────────────────────────────────────────┐ ┌────────────────────────┐   │
│  │ ⌕ filter                    ▾ by memory  │ │                        │   │
│  │                                          │ │  Google Chrome         │   │
│  │  ● Chrome                    4.2 GB   ▲  │ │  Work Profile          │   │
│  │  │                                       │ │                        │   │
│  │  │  ┌─ Work Profile ──────── 2.8 GB ──┐ │ │  ┌────────────────┐   │   │
│  │  │  │  renderer (×12)        1.9 GB   │ │ │  │ 2.8 GB         │   │   │
│  │  │  │  gpu process            340 MB   │ │ │  │ total footprint│   │   │
│  │  │  │  extensions             280 MB   │ │ │  └────────────────┘   │   │
│  │  │  │  utility                210 MB   │ │ │                        │   │
│  │  │  └─────────────────────────────────┘ │ │  15 processes           │   │
│  │  │                                       │ │  ~890 MB non-resident  │   │
│  │  └─ Personal             ─── 1.4 GB ──  │ │                        │   │
│  │                                          │ │  ℹ Adjusted for shared │   │
│  │  ● Claude Code               2.3 GB   ▲ │ │    memory between      │   │
│  │  ● VS Code                   2.1 GB   ─ │ │    processes            │   │
│  │  ● Docker                    1.8 GB   ▼ │ │                        │   │
│  │  ● System                    1.1 GB   ─ │ │  ── breakdown ──       │   │
│  │  ● node › webpack             420 MB  ─ │ │  resident    2.1 GB    │   │
│  │  ● python3 › jupyter          280 MB  ▲ │ │  compressed   540 MB   │   │
│  │                                          │ │  shared       320 MB   │   │
│  │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │ │                        │   │
│  │  3 exited processes          [clear ×]   │ │  ── processes ──       │   │
│  └──────────────────────────────────────────┘ │  12 renderers          │   │
│                                               │  1 gpu process         │   │
│                                               │  2 extension hosts     │   │
│                                               └────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  ⟳ 2s ago          5s ▾                                          ⚙        │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Spatial principles:**
- **The river dominates.** It spans the full window width and is the first 80pt of the window. This is the "one glance" view. Below it, the window splits into the group list (60% width) and detail panel (40% width).
- **Breathing room.** 40pt of empty space between the river and the list. Not padding — deliberate negative space that separates the overview from the drill-down. This is a Dieter Rams move: the pause makes both zones read more clearly.
- **Asymmetric split.** The group list is wider than the detail panel because it's the primary interaction zone. The detail panel is a *supporting* view, not a co-equal pane.
- **No borders, no dividers.** Zones are separated by background color shifts (void → surface → void) and spacing, never by drawn lines. The only hard line in the entire UI is the river bar itself.
- **Left-aligned group dots.** Each top-level group has a colored dot (its accent color) replacing the traditional app icon position. The dot is 8pt, vertically centered. This creates a color column that visually links the list to the river above — you can scan down the dots and see the same colors as the river strata.

---

**The Memory River (detail)**:

The river is a single horizontal bar, 48pt tall, with rounded corners (8pt radius). Each segment:
- Width proportional to group footprint (as fraction of total used memory)
- Colored with the group's accent color
- Minimum width: 3pt (so tiny groups don't disappear entirely)
- Segments have 1pt gaps between them (the void color shows through)
- **Hover**: segment brightens (+0.08 L in OKLCH), a tooltip appears above showing group name + memory. The corresponding group row in the list below gets a subtle highlight simultaneously.
- **Click**: selects that group, scrolls the list to it, opens the detail panel.
- The "free" space at the right end is rendered as the void background — it's just absence, not a colored segment.

Below the river, the summary stats are laid out in a horizontal baseline:
```
16.0 GB          12.4 GB USED  ●         3.6 GB FREE
total            compressed: 3.1 GB       pressure: NORMAL
                 swap: 2.1 GB
```
- The big numbers (`16.0`, `12.4`, `3.6`) are SF Mono Bold 20pt, anchored to a baseline.
- The labels (`total`, `USED`, `FREE`) are SF Pro 11pt in secondary color, directly below their number.
- The pressure indicator is a filled circle (8pt) in the alarm color, with the text label ("NORMAL", "WARNING", "CRITICAL") next to it in the same color.
- Compressed and swap are secondary stats in SF Pro 11pt, tucked under "USED". They only appear when non-trivial.

---

**Smart Group Rows (detail)**:

Each collapsed group row is 44pt tall:
```
 ●  Google Chrome                                    4.2 GB    ▲
 8pt dot                                          SF Mono 15pt Bold
 accent color    SF Pro Medium 13pt                              trend
```

- The dot, name, and number are on the same baseline.
- The memory number is **right-aligned** to a fixed position (e.g., 80pt from the right edge). This creates a clean numerical column that's instantly scannable.
- The trend indicator is 12pt, right of the number, tinted with `--trend-up` or `--trend-down`. Stable state shows a thin dash (`─`) in `--text-muted`.
- **Hover**: row background shifts to `--bg-hover`. The transition is 120ms ease-out.
- **Expanded state**: the disclosure triangle (a small chevron, 10pt) rotates 90° with a 200ms spring animation. Children slide in with a staggered delay (30ms per child) for a cascading reveal effect.

Expanded children are indented 24pt and use a lighter weight:
```
     renderer (×12)                                  1.9 GB
     gpu process                                      340 MB
     extensions                                       280 MB
     SF Pro Regular 12pt, --text-secondary            SF Mono 12pt
```

Sub-groups (Chrome profiles) get an intermediate indentation (12pt) and slightly bolder treatment than individual processes.

**Exited processes** within a group:
- Opacity reduced to 0.4
- Name in italic
- A small `×` badge after the name indicating exited
- Clustered at the bottom of their group's expanded section

---

**Detail Panel (detail)**:

The panel is 280pt wide, slides in from the right with a 250ms ease-out animation when a group or process is selected. Slides out when deselected.

**Group detail layout:**
```
┌─────────────────────────────┐
│                             │
│  Google Chrome              │  SF Pro Display Semibold 16pt
│  Work Profile               │  SF Pro Regular 13pt, --text-secondary
│                             │
│  ┌───────────────────────┐  │
│  │       2.8 GB          │  │  SF Mono Bold 28pt, centered
│  │   total footprint     │  │  SF Pro 11pt, --text-secondary
│  └───────────────────────┘  │  card: --bg-surface, 12pt radius
│                             │
│  15 processes               │
│  ~890 MB non-resident       │
│                             │
│  ℹ Adjusted for shared      │  11pt, --text-muted, italic
│    memory between procs     │
│                             │
│  ── memory breakdown ──     │  section divider: 11pt, --text-muted
│                             │
│  resident        2.1 GB    │  label left, number right, SF Mono 13pt
│  compressed       540 MB    │
│  shared           320 MB    │
│                             │
│  ── process types ──        │
│                             │
│  12 renderers               │
│  1 gpu process              │
│  2 extension hosts          │
│                             │
└─────────────────────────────┘
```

The hero number (2.8 GB) is inside a subtle card — the only "card" element in the UI. It's the anchor of the detail view. Everything else is text with consistent left-aligned labels and right-aligned numbers.

**Process detail layout** (when a single process is selected):
- Same structure but shows: PID, executable path (truncated with `…` in the middle), full command-line args (scrollable, monospaced, 10pt), uptime, and the full memory breakdown (footprint, resident, compressed, non-resident, shared).
- System services show an explanation block: a paragraph of text in `--text-secondary` explaining what the daemon does and why it might be using memory.

---

**Motion & Micro-interactions**:

- **River segments on refresh**: widths animate to their new proportions with a 400ms spring animation (damping: 0.8, response: 0.4). This creates a gentle "breathing" effect as memory shifts between groups.
- **Number changes**: memory values cross-fade (opacity 1→0→1 over 200ms) when they change, rather than snapping. The old number fades out while the new one fades in at the same position. This prevents the jarring "flickering numbers" effect.
- **Group list reordering**: when sort order changes (due to a group growing/shrinking past another), rows animate their position with `.animation(.spring(duration: 0.3))`. The list feels alive but not frantic.
- **Detail panel**: slides in/out with `.transition(.move(edge: .trailing).combined(with: .opacity))`.
- **Trend indicator changes**: the arrow fades between states (▲→─→▼) with a 300ms crossfade.
- **Menu bar pressure dot**: pulses gently (opacity 0.7→1.0→0.7 over 2s) when in WARNING state. Solid when NORMAL. Rapid pulse (0.5s) when CRITICAL.
- **Expansion cascade**: child rows appear with staggered delays (`.animation(.spring(duration: 0.25).delay(Double(index) * 0.03))`), creating a waterfall effect.

---

**Menu Bar**:

```
 ● 12.4 / 16 GB
```

- Pressure dot (8pt filled circle, alarm color) + used/total in SF Mono 11pt
- When swap is significant: ` ● 12.4 / 16 GB  ⬡ 2.1`  (hexagon glyph + swap amount)
- The dot pulses in warning/critical states (see motion section)
- Total width ~120pt in default config, which fits comfortably in the menu bar

**Menu dropdown** (`.menu` style):
```
┌──────────────────────────────────┐
│  Memory    12.4 / 16.0 GB       │
│  Pressure  ● Normal              │
│  Swap      2.1 GB                │
│  ───────────────────────         │
│  Top: Chrome — 4.2 GB           │
│  ───────────────────────         │
│  Open Total Recall       ⌘⇧M    │
│  ───────────────────────         │
│  Preferences...          ⌘,     │
│  Quit Total Recall       ⌘Q     │
└──────────────────────────────────┘
```

---

**Accessibility specifics**:

- Pressure indicator: dot + text label ("Normal" / "Warning" / "Critical"). Never color-only.
- Trend indicators: VoiceOver reads "trending up", "stable", "trending down" — not just the glyph.
- Group rows: VoiceOver announces "Google Chrome, 4.2 gigabytes, trending up, collapsed. Double-tap to expand."
- River segments: VoiceOver can navigate segments left/right, announcing group name + size.
- All text respects Dynamic Type (relative sizes via `.font(.system(size:relativeTo:))`).
- Keyboard: arrow keys navigate the group list, Enter expands/collapses, Tab moves to detail panel, Escape closes detail panel.
- Minimum contrast: all text/background combinations exceed WCAG AA (4.5:1 for body, 3:1 for large text). The OKLCH palette was designed with this constraint.

---

**Dark/Light Mode**:

MVP ships dark-only. The aesthetic *is* the dark palette — like a terminal or an instrument panel, this tool lives in the dark. Light mode is a future consideration, and it would need a complete repalette (not just an inversion) to maintain the same visual character.

---

**Implementation note — new view files from this design**:

The enhanced design adds one new view file and splits responsibility more clearly:

| File | Responsibility |
|---|---|
| `TotalRecall/Views/MemoryRiverView.swift` | The stacked proportional bar with hover/click/animation |
| `TotalRecall/Views/SummaryBarView.swift` | Stats below the river: total/used/free, pressure, compressed, swap |
| `TotalRecall/Views/SmartGroupListView.swift` | The scrollable list with DisclosureGroups |
| `TotalRecall/Views/SmartGroupRowView.swift` | Single collapsed group row (dot + name + number + trend) |
| `TotalRecall/Views/ProcessRowView.swift` | Individual process within expanded group |
| `TotalRecall/Views/DetailPanelView.swift` | Sliding detail panel |
| `TotalRecall/Views/InspectionWindowView.swift` | Container: river + list + detail panel composition |
| `TotalRecall/Theme/TotalRecallTheme.swift` | All colors, typography, spacing constants. Single source of truth. |

**Tasks:**

1. **Theme system**
   - `TotalRecallTheme` enum with pre-computed sRGB color constants (OKLCH values in comments for design reference)
   - Embedded ~50-line OKLCH→sRGB converter for runtime hover brightening only (from CSS Color Level 4 spec)
   - `Color.oklch(L, C, H)` extension for convenience
   - Typography, spacing constants
   - Dark-only for MVP
   - File: `TotalRecall/Theme/TotalRecallTheme.swift`

2. **Apply visual design to app shell** (already wired in Phase 3a)
   - Menu bar: pressure dot (pulses in warning/critical — the one custom animation) + used/total in SF Mono 11pt
   - Try SwiftUI `MenuBarExtra` label animation first; fall back to `NSStatusItem` + `NSHostingView` if pulse doesn't render
   - Activation policy: `.regular` on window open, `.accessory` on close (already in 3a)

3. **`AppState` — the observable model**
   - `@MainActor @Observable class AppState`
   - Properties: `groups`, `systemMemory`, `retainedExited`, `expandedGroups`, `selectedGroup`, `searchText`, `sortOrder`, `refreshInterval`, `exitedRetentionMode`, `isInspectionWindowVisible`
   - Owns `ProcessMonitor` actor, starts/stops polling
   - On each refresh: collect snapshot → run through `ProfileRegistry` → diff for trends → update properties
   - Manage exited process retention per the 3 modes
   - Switches between `.full` and `.menuBarOnly` refresh mode based on `isInspectionWindowVisible`
   - File: `TotalRecall/AppState.swift`

4. **Memory River view**
   - **Built as `HStack` of `RoundedRectangle` views inside `GeometryReader`** (not Canvas or Shape — gives per-segment hover, click, and VoiceOver accessibility for free)
   - 48pt tall, 8pt corner radius on outer clip shape, 1pt gap between segments
   - Each segment: `frame(width: fraction * availableWidth)`, min 3pt
   - **Hover**: brightens +0.08 L using OKLCH helper, tooltip with name + size
   - **Click**: selects group in list
   - **Animation**: `.animation(.spring(duration: 0.4, bounce: 0.2), value: fraction)` — but with **dead zone**: skip animation if proportional change < 0.5% (eliminates ~80% of unnecessary springs on stable refreshes)
   - **Accessibility**: each segment has `.accessibilityLabel("\(group.name), \(formatMemory(...))")`
   - File: `TotalRecall/Views/MemoryRiverView.swift`

5. **Summary bar view**
   - Sits below the river with 40pt breathing room above the group list
   - Big numbers (SF Mono Bold 20pt): total, used, free — with labels below in 11pt secondary
   - Pressure indicator: dot + text label (never color-only for accessibility)
   - Compressed + swap as secondary stats under "USED" (only when non-trivial)
   - File: `TotalRecall/Views/SummaryBarView.swift`

6. **Inspection window container**
   - Composes: river → summary bar → (group list | detail panel) → status bar
   - Default size 780×560pt, `.windowStyle(.hiddenTitleBar)` for clean chrome
   - Asymmetric split: group list 60% / detail panel 40%
   - No borders or dividers — zones separated by background color shifts and spacing
   - File: `TotalRecall/Views/InspectionWindowView.swift`

7. **Smart group list view**
   - Search/filter bar at top (⌘F)
   - Sort control (memory, name, swap)
   - `List` with `DisclosureGroup` per smart group, `.listStyle(.inset(alternatesRowBackgrounds: false))`
   - Exited process badge + "Clear ×" button at list bottom
   - File: `TotalRecall/Views/SmartGroupListView.swift`

8. **Smart group row view**
   - 44pt tall. Layout: 8pt accent dot → name (SF Pro Medium 13pt) → right-aligned memory (SF Mono Bold 15pt) → trend indicator
   - Hover: background → `--bg-hover`, 120ms ease-out
   - Expansion: chevron rotates 90° with 200ms spring; children cascade in with 30ms staggered delay
   - File: `TotalRecall/Views/SmartGroupRowView.swift`

9. **Process row view**
   - 32pt tall, indented 24pt. Label (SF Pro Regular 12pt, secondary) + right-aligned memory (SF Mono 12pt)
   - Sub-groups indented 12pt with slightly bolder treatment
   - Exited: 0.4 opacity, italic name, small × badge
   - File: `TotalRecall/Views/ProcessRowView.swift`

10. **Detail panel view**
    - 280pt wide, slides in from right (250ms ease-out, `.transition(.move(edge: .trailing).combined(with: .opacity))`)
    - Hero number in a subtle card (--bg-surface, 12pt radius): SF Mono Bold 28pt, centered
    - Below: process count, non-resident approximation, shared memory info note (ℹ)
    - Memory breakdown section: label left, number right, consistent alignment
    - System services: explanation paragraph in --text-secondary
    - Process detail: PID, truncated path, scrollable command-line args (monospaced 10pt), uptime
    - File: `TotalRecall/Views/DetailPanelView.swift`

7. **Kill actions**
   - Context menu on right-click for groups and processes
   - Process: Quit (SIGTERM), Force Quit (SIGKILL)
   - Group: Quit Parent / Force Quit Parent, Quit All / Force Quit All
   - **PID safety**: before sending signal, re-verify process name + start time match. Abort with "Process has already exited" if stale.
   - **System group restrictions**: disable Quit Parent / Quit All on system services groups and any group rooted at PID 1
   - Confirmation dialog names the target: "Force Quit 'Google Chrome' (47 processes)? Unsaved work will be lost."
   - Handle EPERM gracefully (show error if permission denied)
   - File: `TotalRecall/Views/KillActionMenu.swift` + `TotalRecall/DataLayer/ProcessActions.swift`

8. **Settings view**
   - Refresh interval picker
   - Exited process retention mode (don't show / keep N seconds / keep until cleared)
   - Menu bar display options (what to show in the label)
   - Launch at Login toggle (`SMAppService.mainApp.register()`)
   - Accessible via ⌘, or gear icon in menu dropdown
   - File: `TotalRecall/Views/SettingsView.swift`

9. **Memory formatting utilities**
   - Smart unit formatting: `formatMemory(bytes:)` → "420 MB", "4.2 GB"
   - Right-aligned monospaced text helper
   - **Use `.contentTransition(.numericText())` for memory value changes** — built-in SwiftUI rolling-digit animation, replaces custom cross-fade. Zero concurrent opacity animations, minimal overhead.
   - All other animations use SwiftUI defaults (`.animation(.default, value:)`) — no custom springs, cascades, or cross-fades except the pressure dot pulse
   - File: `TotalRecall/Utilities/Formatting.swift`

**Success criteria:**
- App launches as menu bar item, no Dock icon
- Clicking menu bar shows stats + "Open Total Recall" button
- Inspection window shows real-time process groups, expandable, with memory numbers matching Activity Monitor ±5%
- Can force-quit a process from the context menu
- Exited process retention works in all 3 modes

**Estimated files:** 10-12 Swift files

---

#### Phase 4: Polish, Testing & Distribution

**Goal**: App is tested, signed, notarized, and distributable.

**Tasks:**

1. **Integration tests with real data**
   - Verify `ProcessMonitor` polling on a real system
   - Benchmark: 500+ process refresh should complete in < 100ms
   - Verify memory numbers match Activity Monitor for known processes
   - File: `TotalRecallTests/IntegrationTests.swift`

2. **Profile engine regression tests**
   - Expand fixture set: capture snapshots from systems running Chrome with multiple profiles, Claude Code sessions, Docker containers
   - Test each profile in isolation and through the full registry
   - Test RSHRD deduplication produces reasonable numbers
   - File: `TotalRecallTests/ProfileTests/` (one file per profile)

3. **Edge case handling**
   - Processes that die between `listAllPIDs` and `getProcessInfo` (ESRCH)
   - Processes with empty/denied command-line args
   - System processes with restricted data → "limited info" indicator
   - PID reuse (a new process gets the same PID as a recently exited one)
   - Very short-lived processes in retention mode
   - Groups that shrink to 0 active processes (all exited)
   - File: `TotalRecallTests/EdgeCaseTests.swift`

4. **Code signing & notarization**
   - Developer ID Application certificate
   - Hardened Runtime enabled
   - Notarize with `notarytool`
   - Create DMG with `create-dmg`
   - File: `scripts/build-and-notarize.sh`

5. **Auto-updates with Sparkle**
   - Add Sparkle 2.x via SPM
   - Generate EdDSA signing keys
   - `SUFeedURL` in Info.plist
   - Update check in Settings view
   - File: update `Package.swift` or Xcode SPM dependencies

6. **CLAUDE.md and README**
   - Build instructions, architecture overview, how to run tests
   - How to capture new test fixtures
   - Files: `CLAUDE.md`, `README.md`

**Success criteria:**
- All tests pass
- App is signed and notarized
- DMG installs cleanly on a fresh Mac
- Sparkle update check works
- README documents build and test workflow

**Estimated files:** 5-8 files + scripts

---

## File Summary

### New files to create (estimated ~25)

```
TotalRecall/
├── TotalRecall.xcodeproj/
├── TotalRecall/
│   ├── TotalRecallApp.swift              # App entry point, MenuBarExtra + Window
│   ├── AppState.swift                     # @Observable main state, trend computation
│   ├── Info.plist                         # LSUIElement, bundle config
│   ├── TotalRecall.entitlements           # No sandbox, hardened runtime (minimal)
│   │
│   ├── Models/
│   │   ├── ProcessSnapshot.swift          # Core data model (Codable, Sendable) + ProcessIdentity
│   │   ├── SystemMemoryInfo.swift         # System-wide memory stats
│   │   └── ProcessGroup.swift             # Grouped process model with stableIdentifier
│   │
│   ├── DataLayer/
│   │   ├── SystemProbe.swift              # libproc/sysctl/Mach wrappers
│   │   ├── RedactionFilter.swift          # Masks secrets in command-line args
│   │   ├── ProcessMonitor.swift           # Actor: polling + classification + caching
│   │   ├── ProcessActions.swift           # Kill with PID verification + denylist + audit log
│   │   └── SnapshotCapture.swift          # #if DEBUG only
│   │
│   ├── Profiles/
│   │   ├── ProcessClassifier.swift        # Protocol + ClassificationResult
│   │   ├── ClassifierRegistry.swift       # Ordered classification + RSHRD dedup
│   │   ├── CommandLineParser.swift        # Shared arg parsing utility
│   │   ├── ChromeClassifier.swift
│   │   ├── ElectronClassifier.swift
│   │   ├── SystemServicesClassifier.swift
│   │   └── GenericClassifier.swift
│   │
│   ├── Theme/
│   │   └── TotalRecallTheme.swift         # Pre-computed sRGB + OKLCH converter + typography
│   │
│   ├── Views/
│   │   ├── InspectionWindowView.swift     # Main window: river + list + detail composition
│   │   ├── WindowVisibilityTracker.swift  # AppKit bridge for two-tier refresh
│   │   ├── MemoryRiverView.swift          # HStack of colored Rectangles (hero element)
│   │   ├── SummaryBarView.swift           # Stats below the river
│   │   ├── GroupListView.swift            # List + DisclosureGroup
│   │   ├── GroupRowView.swift             # Single group row (dot + name + number + trend)
│   │   ├── ProcessRowView.swift           # Individual process row
│   │   ├── DetailPanelView.swift          # Sliding detail panel
│   │   └── SettingsView.swift             # Preferences (refresh interval, retention, launch at login)
│   │
│   └── Utilities/
│       └── Formatting.swift               # Memory formatting + .numericText() helpers
│
├── TotalRecallTests/
│   ├── Fixtures/
│   │   └── FixtureBuilder.swift           # Synthetic fixture construction (no real data)
│   ├── ClassifierTests.swift              # Classifier engine + per-classifier assertions
│   ├── RedactionFilterTests.swift         # Secret masking coverage
│   ├── MemoryAggregationTests.swift       # RSHRD dedup, formatting
│   └── ProcessActionsTests.swift          # PID verification, denylist
│
├── tools/
│   └── benchmark-collection.swift         # Already exists — API timing benchmark
│
├── docs/
│   ├── PRD.md
│   └── RESEARCH.md
│
├── CLAUDE.md
└── README.md
```

## Dependencies & Prerequisites

- **Xcode 17+** (for macOS 26 SDK)
- **Apple Developer Program** enrollment (for Developer ID signing + notarization)
- **No third-party dependencies for MVP** (consider `MenuBarExtraAccess` if programmatic panel control needed)
- Sparkle deferred to post-MVP

## Risk Analysis & Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| `proc_*` APIs restricted for system processes | Some groups show "limited info" | Detect and display gracefully; document which data requires elevated access |
| Swap approximation (`footprint - resident`) is misleading | Users misinterpret "swap" numbers | Label as "Non-Resident Memory" with tooltip explaining it includes compressed |
| RSHRD deduplication heuristic inaccurate for some groups | Group totals seem wrong vs Activity Monitor | Label as "Estimated" with info button explaining methodology |
| 500+ process refresh takes too long | UI feels laggy | Benchmark early (Phase 1); cache aggressively; defer expensive calls |
| App Profile detection wrong (false positives/negatives) | Processes in wrong groups | Fixture-based tests catch regressions; GenericProfile as safe fallback |
| Chrome/VS Code/Claude Code change their process structure | Profiles break silently | Version-specific detection where possible; log unrecognized patterns |
| SwiftUI `MenuBarExtra` limitations | Can't achieve desired UX | Fall back to `NSStatusItem` AppKit interop if needed |

## Success Metrics

- User with 400+ processes understands top memory consumer within 5 seconds of opening
- Chrome users see per-profile breakdown without inspecting individual helpers
- Claude Code users identify which workspace is the memory hog
- No process shown as just `node`, `python3`, or a version string
- Memory numbers match Activity Monitor ±5%
- Cold launch to first data display < 2 seconds
- Refresh cycle < 100ms for 500 processes

## References

### Internal
- PRD: `docs/PRD.md`
- Framework research: `docs/RESEARCH.md`

### External
- [Activity Monitor Anatomy](https://www.bazhenov.me/posts/activity-monitor-anatomy/) — how Apple implements process monitoring
- [TrueTree](https://github.com/themittenmac/TrueTree) — responsible PID concept and implementation
- [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) — MenuBarExtra programmatic control
- [Apple: phys_footprint](https://developer.apple.com/documentation/kernel/task_vm_info_data_t/1553210-phys_footprint)
- [Mike Ash: Process Memory Statistics](https://www.mikeash.com/pyblog/friday-qa-2009-06-19-mac-os-x-process-memory-statistics.html)
- [Peter Steinberger: Settings from Menu Bar](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Sparkle Documentation](https://sparkle-project.org/documentation/)
- [Apple: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [create-dmg](https://github.com/create-dmg/create-dmg)
