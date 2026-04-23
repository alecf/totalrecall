# Total Recall — Development Guide

## Build

```bash
swift build                    # Debug build
swift build --target TotalRecall        # App only
swift build --target TotalRecallDiag    # CLI diagnostic tool only
swift build --target TotalRecallCore    # Core library only
swift test                     # Run all tests
swift run TotalRecall          # Run the app (menu bar only, no Dock icon)
swift run TotalRecallDiag      # Run the CLI diagnostic tool
```

Requires: Xcode 17+ with macOS 26 SDK. Swift 6.2 strict concurrency.

## Package structure

Three targets sharing `TotalRecallCore`:
- **TotalRecallCore** — library: models, data layer, classifiers, theme, utilities
- **TotalRecall** — executable: SwiftUI app (AppState, Views, MenuBarExtra)
- **TotalRecallDiag** — executable: CLI diagnostic tool for classifier iteration

## Architecture

```
ProcessMonitor (actor, background)
  → SystemProbe (libproc/sysctl wrappers)
  → ClassifierRegistry (5 classifiers: Chrome, Electron, ClaudeCode, System, Generic)
  → Returns [ProcessGroup] + SystemMemoryInfo

AppState (@MainActor @Observable)
  → Receives classified groups
  → Computes trends (6-snapshot rolling window, ±5% threshold)
  → Instance merging (toggle between merged/separate views)
  → Sort by footprint or resident memory
  → Drives SwiftUI views

Views (SwiftUI)
  → MenuBarExtra(.menu) + Window
  → MemoryRiverView (proportional stacked bar)
  → GroupListView + DetailPanelView
  → MemoryBarView (per-process resident vs compressed/swapped)
```

## Key Design Decisions

- **ProcessClassifier protocol** uses single `classify([ProcessSnapshot])` (not claims+group) for context-aware process ownership
- **ProcessGroup.stableIdentifier** persists across snapshots for correct trending
- **RedactionFilter** only applied when serializing to disk (SnapshotCapture), NOT in live UI — users need to see their own process args
- **PID verification** via ProcessIdentity (pid + path + startTime) before kill actions
- **Two-tier refresh**: full (5s) when window visible, system-only (60s) when hidden
- **OKLCH colors** pre-computed as sRGB constants, all at equal lightness for accessibility
- **Icon resolution**: use `NSRunningApplication(processIdentifier:).icon` first, fall back to `.app` bundle path. Plain `Image(nsImage:)` renders correctly — do NOT use CGImage conversion, NSViewRepresentable, or renderingMode(.original)
- **Volta shim resolution**: shared in CommandLineParser, used by ClaudeCodeClassifier and ProcessRowView

## Testing

Tests use **synthetic fixtures** (FixtureBuilder) — never capture real process data to files (secrets in args).

```bash
swift test                           # All tests
swift test --filter Chrome           # Chrome classifier tests only
swift test --filter Redaction        # RedactionFilter tests only
```

## Adding a New Classifier

1. Create `TotalRecall/Profiles/FooClassifier.swift` implementing `ProcessClassifier`
2. Make all types `public`
3. Add it to `ClassifierRegistry.default` array (order matters — earlier = higher priority)
4. Add fixtures to `FixtureBuilder` and tests to `ClassifierTests`
5. Use `CommandLineParser` for shared arg parsing (volta resolution, runtime tool identification)

## Iterating on classifier quality

Use the diagnostic CLI to inspect classification output:

```bash
swift run TotalRecallDiag
```

Check for: duplicate app names at top level, missing icons, opaque process names, system processes not in the System group.

## Git & Release Conventions

- **Conventional commits** required on PR titles: `feat:`, `fix:`, `docs:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `style:`
- **Squash merge only** — PR title becomes the commit message on `main`
- **Releasing**: `gh workflow run release.yml` — git-cliff auto-calculates semver from commits (`feat:` → minor, `fix:` → patch, `feat!:` → major), generates grouped changelog, builds `.app` bundle + DMG, publishes GitHub Release
- **Ad-hoc signed only, not notarized** — release workflow runs `codesign --force --deep --sign -` on the bundle. First-launch flow: double-click → Done, then System Settings → Privacy & Security → Open Anyway. Right-click → Open no longer bypasses Gatekeeper on macOS 15+ (Sequoia/Tahoe)
- **App bundle template** lives in `Distribution/Info.plist` (version stamped by CI)
- **Changelog config** in `cliff.toml`

## File Organization

- `Models/` — ProcessSnapshot, ProcessGroup, SystemMemoryInfo (all Sendable + Codable)
- `DataLayer/` — SystemProbe, ProcessMonitor, RedactionFilter, ProcessActions, SnapshotCapture
- `Profiles/` — ProcessClassifier protocol, ClassifierRegistry, 5 classifiers, CommandLineParser
- `Theme/` — TotalRecallTheme (colors, fonts, spacing)
- `Views/` — All SwiftUI views
- `Utilities/` — Formatting, GroupDiagnostics
