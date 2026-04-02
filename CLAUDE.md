# Total Recall — Development Guide

## Build

```bash
swift build          # Debug build
swift test           # Run all tests (17 currently)
swift run            # Run the app (menu bar only, no Dock icon)
```

Requires: Xcode 17+ with macOS 26 SDK. Swift 6.2 strict concurrency.

## Architecture

```
ProcessMonitor (actor, background)
  → SystemProbe (libproc/sysctl wrappers)
  → ClassifierRegistry (4 classifiers: Chrome, Electron, System, Generic)
  → Returns [ProcessGroup] + SystemMemoryInfo

AppState (@MainActor @Observable)
  → Receives classified groups
  → Computes trends (6-snapshot rolling window)
  → Manages exited process retention
  → Drives SwiftUI views

Views (SwiftUI)
  → MenuBarExtra(.menu) + Window
  → MemoryRiverView (hero: proportional stacked bar)
  → GroupListView + DetailPanelView
```

## Key Design Decisions

- **ProcessClassifier protocol** uses single `classify([ProcessSnapshot])` (not claims+group) for context-aware process ownership
- **ProcessGroup.stableIdentifier** persists across snapshots for correct trending
- **RedactionFilter** masks secrets in command-line args at capture time
- **PID verification** via ProcessIdentity (pid + path + startTime) before kill actions
- **Two-tier refresh**: full (5s) when window visible, system-only (60s) when hidden
- **OKLCH colors** pre-computed as sRGB constants, all at equal lightness for accessibility

## Testing

Tests use **synthetic fixtures** (FixtureBuilder) — never capture real process data to files (secrets in args).

```bash
swift test                    # All tests
swift test --filter Chrome    # Chrome classifier tests only
```

## Adding a New Classifier

1. Create `TotalRecall/Profiles/FooClassifier.swift` implementing `ProcessClassifier`
2. Add it to `ClassifierRegistry.default` (order matters — higher = checked first)
3. Add fixtures to `FixtureBuilder` and tests to `ClassifierTests`

## File Organization

- `Models/` — ProcessSnapshot, ProcessGroup, SystemMemoryInfo (all Sendable + Codable)
- `DataLayer/` — SystemProbe, ProcessMonitor, RedactionFilter, ProcessActions
- `Profiles/` — ProcessClassifier protocol, ClassifierRegistry, 4 classifiers
- `Theme/` — TotalRecallTheme (colors, fonts, spacing)
- `Views/` — All SwiftUI views
- `Utilities/` — Formatting helpers
