# Total Recall

A macOS menu bar app that provides intelligent, grouped views of memory (RAM) usage. Unlike Activity Monitor, Total Recall groups processes by logical application using built-in knowledge of how apps like Chrome, VS Code, Docker, Claude Code, and system services manage their process hierarchies.

## Features

- **Smart process grouping**: Chrome processes grouped by profile, Electron apps by bundle, Claude Code by workspace, system daemons with human-readable explanations
- **Memory River**: proportional stacked bar showing where your RAM is going at a glance
- **Memory composition bars**: per-process breakdown of resident (in RAM) vs compressed/swapped
- **Menu bar presence**: memory pressure indicator + used/total display
- **Trend indicators**: see which apps are growing or shrinking over time
- **Sort by footprint or resident**: understand total impact vs what's actually in RAM
- **Instance merging**: toggle between merged view (all Chrome instances as one) and separate view
- **Safe kill actions**: PID-verified termination with system process protection and audit logging
- **Working directory context**: see which directory Claude Code sessions are running in
- **Process identification**: resolves `node`, `python3`, volta shims to what they're actually running (TypeScript Server, Webpack, MCP Server, etc.)

## Screenshot

*(Coming soon)*

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 17+ (for building from source)
- Apple Silicon or Intel Mac

## Installing

Download the latest `TotalRecall-<version>-arm64.dmg` from [Releases](https://github.com/alecf/totalrecall/releases/latest), open it, and drag **Total Recall** to Applications.

Total Recall is ad-hoc signed but **not notarized** (I don't have a paid Apple Developer account). The first time you launch it, macOS will show:

> *"Apple could not verify 'Total Recall.app' is free of malware..."*

To allow it:

1. Double-click the app → click **Done** on the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the security section — you'll see *"'Total Recall' was blocked..."* with an **Open Anyway** button.
4. Click **Open Anyway** and authenticate.
5. Launch the app again — you'll get one more confirmation dialog; click **Open Anyway**.

You only need to do this once. Alternatively, from Terminal:

```bash
xattr -d com.apple.quarantine "/Applications/Total Recall.app"
```

## Building

```bash
git clone https://github.com/alecf/totalrecall.git
cd totalrecall
swift build
swift run TotalRecall
```

## Running the diagnostic CLI

The diagnostic tool outputs the full classified process tree to the terminal:

```bash
swift run TotalRecallDiag
```

## Running tests

```bash
swift test
```

## Architecture

```
ProcessMonitor (actor, background thread)
  → SystemProbe (libproc/sysctl/Mach API wrappers)
  → ClassifierRegistry → ChromeClassifier, ElectronClassifier,
                          ClaudeCodeClassifier, SystemServicesClassifier,
                          GenericClassifier
  → Returns [ProcessGroup] + SystemMemoryInfo

AppState (@MainActor, @Observable)
  → Receives classified groups, computes trends
  → Drives SwiftUI views

Views (SwiftUI)
  → MenuBarExtra(.menu) — compact menu bar dropdown
  → Window — Memory River, group list, detail panel
```

### Tiered data collection

| Tier | API | Cost (886 PIDs) | Strategy |
|------|-----|-----------------|----------|
| 0 | `proc_listallpids` | 0.17ms | Every cycle |
| 1 | `proc_pid_rusage` | 2.6ms | Every cycle |
| 2 | `proc_pidinfo` + `proc_pidpath` | 2.8ms | Cached per PID |
| 3 | `KERN_PROCARGS2` | 9.2ms | Cached per PID |

Full collection takes ~15ms for 886 processes (0.3% of a 5-second interval).

### Memory model

- **Physical footprint** (`phys_footprint`): the primary metric, same as Activity Monitor's "Memory" column
- **Resident**: pages currently in physical RAM
- **Non-resident**: compressed in-place or swapped to disk (can't distinguish per-process without privileged entitlements)
- **Shared memory**: deduplicated via RSHRD heuristic for group totals

## Project structure

```
TotalRecall/           — App source
  Models/              — ProcessSnapshot, ProcessGroup, SystemMemoryInfo
  DataLayer/           — SystemProbe, ProcessMonitor, RedactionFilter, ProcessActions
  Profiles/            — ProcessClassifier protocol + 5 classifiers
  Theme/               — Colors, typography, spacing
  Views/               — SwiftUI views
  Utilities/           — Formatting, diagnostics
TotalRecallDiag/       — CLI diagnostic tool
TotalRecallTests/      — Tests with synthetic fixtures
tools/                 — Benchmark scripts
docs/                  — PRD, research, plans
```

## Contributing

This project is in early development. Issues and PRs welcome.

## License

MIT
