# Total Recall — Development Guide

## Keeping docs and CLAUDE.md current

When opening a PR, review whether the change affects:

- `README.md` — user-facing features, install flow, requirements, architecture diagram, project structure
- `CLAUDE.md` — build commands, package layout, design decisions, file organization, conventions
- `docs/` — PRD, research notes, setup guides (`sparkle-setup.md`, etc.)
- `site/` — feature copy, install instructions, classifier descriptions, architecture explanations on the marketing site

If a PR changes any of those surfaces, update them in the same PR. Write
everything as if the PR has already merged — describe the state of the
product after the change, not the journey. No "previously…", no "this PR
adds…", no migration notes. Past iterations belong in git history, not
in living docs.

Delete content that no longer matches the code rather than leaving stale
descriptions in place.

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

`Package.resolved` is committed. It pins the exact Sparkle revision that ships
in the DMG, so a release is reproducible from its tag rather than resolving
whatever satisfies `from: "2.6.0"` at build time — and Dependabot's swift
updater reads it. Do not add it back to `.gitignore`.

## Package structure

Three Swift targets sharing `TotalRecallCore`, plus a separate web target:
- **TotalRecallCore** — library: models, data layer, classifiers, theme, utilities
- **TotalRecall** — executable: SwiftUI app (entry point, AppState, Views, MenuBarExtra, Sparkle updater, window-state persistence, `--screenshot` CI hook)
- **TotalRecallDiag** — executable: CLI diagnostic tool for classifier iteration
- **site/** — React + Vite marketing site deployed to GitHub Pages; also hosts the Sparkle `appcast.xml` feed

## Architecture

```
ProcessMonitor (actor, background)
  → SystemProbe (libproc/sysctl wrappers)
  → ClassifierRegistry (5 classifiers: Chrome, Electron, ClaudeCode, System, Generic)
  → Returns [ProcessGroup] + SystemMemoryInfo

AppState (@MainActor @Observable)
  → Receives classified groups
  → Computes trends (6-snapshot window, ±5% threshold) from a 24-snapshot
    (~2 min) per-group footprint history that also feeds the row sparklines
  → Instance merging (toggle between merged/separate views)
  → Sort by footprint or resident memory
  → Drives SwiftUI views

Views (SwiftUI)
  → MenuBarExtra(.menu) + Window
  → MemoryRiverView (proportional stacked bar, split at a midline into a
    fixed resident band and per-segment compressed/swapped stubs, with a
    left gutter naming the two halves "In RAM" / "Compressed" and a
    MemoryKeyView beneath it whenever nothing is hovered)
  → GroupListView + DetailPanelView (Overview tab + Regions tab for single-process groups)
  → VMRegionsView (lazy vmmap-style breakdown: __TEXT/Heap/Anonymous/Stack/File-backed)
  → SparklineView (per-group footprint history, ~2 min)
  → MemoryBarView (per-process resident vs compressed/swapped)
```

## Key Design Decisions

- **ProcessClassifier protocol** uses single `classify([ProcessSnapshot])` (not claims+group) for context-aware process ownership
- **ProcessGroup.stableIdentifier** persists across snapshots for correct trending
- **RedactionFilter** only applied when serializing to disk (SnapshotCapture), NOT in live UI — users need to see their own process args
- **PID verification** via ProcessIdentity (pid + path + startTime) before kill actions
- **Two-tier refresh**: full (5s) when window visible, system-only (60s) when hidden
- **OKLCH colors** pre-computed as sRGB constants, all at equal lightness for accessibility
- **Memory River encodes memory by area** — the bar splits at a midline. Above it, a fixed-height band (`Theme.riverHeight`) every segment fills in `Theme.memoryResident`, with width as resident bytes against total physical RAM. Below it, each segment hangs its own `Theme.memoryCompressed` stub of depth `riverHeight × nonResident / resident` (`RiverLayout.computeDepths`, gated by a 100 MB floor so idle daemons stay quiet). Because width is already resident bytes, that depth makes each rectangle's **area** the memory it holds, on one constant that is the same for every segment — equal areas anywhere in the bar are equal memory, and a wide flat stub equals a narrow deep one. **Do not encode the swapped share as a fraction of segment height**: the horizontal axis is the RAM scale, so a vertical fraction of a fixed-height band is a second quantity on no scale at all and can't be compared between segments
- **The river's two halves are named in a left gutter** — a static "In RAM" centered in the band and "Compressed" anchored to the midline, in a fixed `Theme.riverAxisLabelWidth` column so the bar's left edge doesn't move with the text. **Each is drawn in the tone of the half it names**, which is what makes the gutter a key and not just an axis: the word sits against the band it describes, so nothing has to be carried back to a legend elsewhere. Both tones are OKLab L=0.61 on a near-black ground and clear 5:1, brighter than the `textSecondary` grey they replaced. The lower one says "Compressed" rather than "Swapped" even though the quantity it names (`physFootprint - residentSize`) conflates compressed and swapped pages and cannot be split per process — the compressor is the half macOS reaches first, and it's the word Activity Monitor uses for the same memory
- **The vocabulary is centralized in `Theme`** — `residentLabel`, `nonResidentLabel`, `nonResidentLabelLong`, and the two glosses. The gutter, the key, the detail-panel rows, and the `MemoryBarView` tooltip all read from those, so the naming decision above is now one edit rather than three that can drift. `ThemeTests` asserts `nonResidentLabelLong` merely *extends* `nonResidentLabel`, so the short and long forms can never become different words. The site copy is still a separate surface — change it in the same PR
- **The key is always on screen, and it costs no layout** — `MemoryKeyView` (swatch + term + gloss, both tones) lives in the row beneath the river that the hover readout already reserves. Idle it shows the key; hovering a segment cross-fades to that segment's readout, which answers the same question with real numbers. This exists because it had to: shown the app cold, people did not work out that the two colors were the difference between memory an app holds in RAM and memory macOS has taken back — and that difference is the entire product. **Don't demote it to a tooltip, a menu item, or a Settings toggle.** The same swatch keys the detail panel's "In RAM" / "Compressed / swapped" rows and the summary bar's compressed figure. `MemoryBarView` deliberately carries no legend of its own — the river's key is one screen-level key for a two-color palette, and repeating it per row would be noise
- **The river's height is dynamic and quantized** — the deepest stub sets it, snapped to `Theme.riverDepthQuantum` with a `Theme.riverShrinkDeadband` hysteresis, so a stub hovering at a boundary can't toggle the whole window's layout on every 5s refresh. Stub depths themselves stay continuous; only the container snaps. Depth caps at `Theme.riverMaxDepth`, so the bar never exceeds `riverHeight + riverMaxDepth`; a capped stub fades out over its last few pixels to say "continues past here"
- **The depth cap is deliberately larger than the band height** — `riverMaxDepth` (48) against `riverHeight` (32) puts the clip threshold at `nonResident / resident > 1.5`, not at 1.0. **Do not collapse the two back into one constant.** Measured on a busy machine, 12 of 15 groups with stubs clipped at a threshold of 1.0 and only 8 at 1.5: browsers and Electron shells routinely run 1.0–1.5, so pinning the cap to the band made the fade the rule instead of the exception. The distribution is bimodal — a tight cluster just past 1.0, then a cliff to daemons running 3× to 23× — so 1.5 sits at the knee, and raising it further buys almost nothing while costing bar height. Note the tradeoff this locks in: a clipped stub is now 60% of the bar's height rather than 50%
- **Swap gets no swatch in the summary bar.** macOS reports the compressor pool and swap separately system-wide, but the per-process figure the river draws cannot be split between them — so keying swap with its own chip would teach a color the bar never shows. It keeps `Theme.swapWarn` as a signal, not as a third member of the palette
- **Only two colors ever appear.** **Do not reintroduce a gradient between them**: at 258° and 62° they are near-complementary, so every interpolation path crosses the neutral axis and the midpoints come out muddy grey (chroma 0.021) — that is geometry, not a tuning problem. The clip fade is not an exception: it ramps `memoryCompressed` to transparent, so the hue never moves. `MemoryBarView` uses the same two constants, so the river and the row bars are one palette. Row bars keep their horizontal resident|compressed split via `Theme.hiddenFraction` — their width isn't tied to the RAM scale, so the area argument doesn't reach them, and a variable stub would fight the fixed `groupRowHeight`
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
- **Releasing** (two-phase, PR-gated — nothing reaches `main` or users without a merged PR):
  1. `gh workflow run release.yml` — git-cliff auto-calculates semver from commits (`feat:` → minor, `fix:` → patch, `feat!:` → major), generates the grouped changelog, builds + ad-hoc-signs the `.app` bundle + DMG, EdDSA-signs the DMG, creates a **draft** GitHub Release holding the DMG, and opens a `release/vX.Y.Z` PR that adds the new `appcast.xml` entry.
  2. Trigger CI on that PR (push an empty commit or close+reopen — GitHub doesn't run workflows on bot-opened PRs), then merge it. The merge runs `release-publish.yml`, which flips the draft Release to published (creating the tag at the merge commit); `deploy-site.yml` publishes the updated appcast to GitHub Pages.
- **Don't merge anything else while a release PR is open** — `release.yml` builds, tests, and writes notes for one exact commit, recorded as the draft Release's `targetCommitish`. If main gains a commit before the release PR merges, the resulting tag spans work that is in neither the notes nor the DMG, and since the next release starts from that tag, those commits vanish from every changelog permanently. `release-publish.yml` refuses to publish when the merge commit's `parents[0]` doesn't match the recorded commit; recovery is to delete the draft plus the appcast entry that just landed and re-dispatch. It then pins the tag with `--target "$MERGE_SHA"` rather than `--target main`, so a merge landing mid-job can't move the tag off the commit it just verified. **Don't set `--target main` in either workflow** — the branch name is what allows the drift
- **Release notes come from the unreleased range, never `--latest`** — `release.yml` runs *before* the tag exists (`release-publish.yml` creates it at publish time), so to git-cliff the "latest" release is still the previous one. `--latest` therefore emits the previous release's notes, which is exactly what shipped for every release through 0.9.0 in both the GitHub Release body and the Sparkle appcast. The range is defined once as `CLIFF_RANGE=(--unreleased --tag "${TAG}")` and reused by all three git-cliff runs — markdown notes, HTML appcast notes, and the check that validates them. **Do not inline the flags per invocation**: the version number comes from `--bumped-version`, which is also the unreleased set, and keeping one definition is what stops the version and the notes from describing different commits. A non-empty check can't catch this (wrong notes are still notes), so the step asserts every commit git-cliff selected is actually in `$(git describe --tags --abbrev=0)..HEAD` and fails the run before anything is built or drafted
- **Ad-hoc signed only, not notarized** — release workflow runs `codesign --force --deep --sign -` on the bundle. First-launch flow: double-click → Done, then System Settings → Privacy & Security → Open Anyway. Right-click → Open no longer bypasses Gatekeeper on macOS 15+ (Sequoia/Tahoe)
- **Dependency updates** — Dependabot opens weekly grouped PRs for three
  ecosystems: SPM at the root (Sparkle), npm in `site/`, and the SHA-pinned
  GitHub Actions in `.github/workflows/`. Minor and patch bumps arrive as one
  PR per ecosystem; majors come individually. Swift bumps are titled `build:`
  so a Sparkle change shows up in the release changelog; the other two are
  `chore:`, which `cliff.toml` skips. Dependabot PRs run with a read-only
  token, so CI posts no coverage comment on them. TypeScript majors are on
  Dependabot's ignore list until `typescript-eslint` accepts TypeScript 7 —
  its peer range still caps at `<6.1.0`, and a bump past that makes
  `npm ci` unresolvable.
- **The site is built in CI, not just at deploy time** — `ci.yml`'s `site`
  job runs the same `npm ci` + build as `deploy-site.yml` on every PR, so a
  broken lockfile fails the PR instead of the Pages deploy on `main`. Keep
  the two in sync. `npm run build` against an already-populated
  `node_modules` proves nothing about whether `npm ci` resolves.
- **App bundle template** lives in `Distribution/Info.plist` (version stamped by CI)
- **App icon** — master artwork is `Distribution/AppIcon.svg`, laid out on Apple's
  macOS grid (824×824 shell centered on a 1024 canvas). `Distribution/AppIcon.icns`
  is generated from it by `Distribution/make-icon.sh` and **committed**, so the
  release runner doesn't need librsvg. Edit the SVG → run the script → commit both.
  The web mark — `site/public/favicon.svg` and the `site/src/components/Logo.tsx`
  React component — is the same design with two deliberate differences: the board
  is scaled up to fill the tile (no Dock shadow to reserve margin for) and the
  connector's finger dividers are dropped (sub-pixel at favicon size). Those two
  must stay in sync with each other, and all three change together.
- **Changelog config** in `cliff.toml`

## File Organization

`TotalRecall/` (app target):
- `TotalRecallApp.swift` — `@main` entry point, AppDelegate, MenuBarExtra + Window scenes
- `AppState.swift` — `@MainActor @Observable` state; polling, trend computation, sort/merge toggles
- `Updater.swift` — Sparkle integration
- `WindowPersistence.swift` — UserDefaults keys + AppKit autosave name for inspection window state
- `ScreenshotMode.swift` — `--screenshot <path>` CLI flag used by PR screenshot CI
- `Views/` — All SwiftUI views, including `MemoryKeyView` (the shared `MemorySwatch` chip and the river's key row)

`TotalRecallCore/` (library, sourced from `TotalRecall/` subdirectories):
- `Models/` — ProcessSnapshot, ProcessGroup, SystemMemoryInfo, VMRegion (all Sendable + Codable)
- `DataLayer/` — SystemProbe (incl. `getVMRegions` for per-process VM map walking), ProcessMonitor, RedactionFilter, ProcessActions, SnapshotCapture
- `Profiles/` — ProcessClassifier protocol, ClassifierRegistry, 5 classifiers, CommandLineParser
- `Theme/` — TotalRecallTheme (colors, fonts, spacing)
- `Utilities/` — Formatting, GroupDiagnostics, GroupSelection, RiverLayout, InstanceMerger, TrendCalculator, SparklineLayout

Other top-level directories:
- `TotalRecallDiag/` — CLI diagnostic executable
- `TotalRecallTests/` — XCTest target; `Fixtures/FixtureBuilder.swift` synthesizes test data
- `tools/` — Standalone Swift scripts (`benchmark-collection.swift`, `diagnose-groups.swift`)
- `Distribution/` — App bundle template (`Info.plist`, version stamped by CI at release
  time), app icon master (`AppIcon.svg`), generated-and-committed `AppIcon.icns`, and
  `make-icon.sh` to rebuild the latter
- `docs/` — PRD, research, plans, sparkle-setup, screenshots
- `site/` — Marketing site + `public/appcast.xml`. `site/src/assets/` holds real
  app screenshots pulled from the `pr-screenshots` release (see `site/README.md`),
  never mockups
- `cliff.toml` — git-cliff config for changelog generation; `.github/appcast-body.tera` is the HTML body template for the same commits, rendered into the Sparkle appcast
- `.github/dependabot.yml` — weekly grouped dependency updates for SPM, npm (`site/`), and GitHub Actions
