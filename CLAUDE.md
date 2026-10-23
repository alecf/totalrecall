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
  → SystemProbe (libproc/sysctl/Mach wrappers)
  → ProportionalShareCache (budgeted VM-region walks → per-process PSS share)
  → ClassifierRegistry (6 classifiers: Chrome, Electron, ClaudeCode, Simulator, System, Generic)
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
    left gutter naming the two halves "In RAM" / "Compressed"; groups sized
    by proportional resident memory (PSS) scaled to fit app memory, those
    too narrow to draw to scale folded into one "small groups" segment, then
    measured system segments from RiverAccounting — "Other" (app memory in
    no group), "Kernel" (wired), "Compressor" (the pool), "Available" — and
    a MemoryKeyView beneath it whenever nothing is hovered)
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
- **Memory River encodes memory by area** — the bar splits at a midline. Above it, a fixed-height band (`Theme.riverHeight`) every segment fills in `Theme.memoryResident`, with width as the segment's bytes against total physical RAM (for a group, its proportional resident memory scaled by `RiverAccounting.groupScale`). Below it, each group segment hangs its own `Theme.memoryCompressed` stub of depth `riverHeight × nonResident / PSS` (`RiverLayout.computeDepths`, gated by the 100 MB `Theme.memoryHiddenFloor` so idle daemons stay quiet — the floor applies to whatever a segment holds, so the small-groups segment is gated on its members' *summed* non-resident memory, not each one's). Because width is already the group's in-RAM bytes, and the scale is one factor shared by every group, that depth makes each rectangle's **area** the memory it holds, on one constant that is the same for every segment — equal areas anywhere in the bar are equal memory, and a wide flat stub equals a narrow deep one. **Do not encode the swapped share as a fraction of segment height**: the horizontal axis is the RAM scale, so a vertical fraction of a fixed-height band is a second quantity on no scale at all and can't be compared between segments
- **Groups too narrow to draw to scale fold into one "small groups" segment** — a group is drawn only when its to-scale width, `scaled PSS / totalPhysical × barWidth`, reaches `Theme.riverMinSegmentWidth` (3 pt); everything below folds into a single segment after the last drawn group and before the system segments (`RiverFolding.foldedIDs`). Inflating every sub-pixel group to the minimum width broke the bar on a busy machine: a 9 MB helper is ~0.15 px on 32 GB, so dozens of them each grew ~20×, their slivers and gaps ate ~200 pt and pushed Available off the end, and each one's small compressed share fell under `memoryHiddenFloor`, so they read as "all in RAM" while the detail panel showed them mostly compressed. The folded segment is a segment like any other: width is the members' summed PSS at the same scale as every group, and it hangs a stub from their summed non-resident memory, so the area encoding holds for the aggregate and their compressed memory is drawn rather than hidden. Folded groups are mostly idle daemons running several times more compressed than resident, so that stub usually clips at `riverMaxDepth` and holds the bar at full height. **That is intended, not a bug to cap**: it's the truth about those groups, the fade already says "continues past here", and a busy machine's large apps hold the bar at full height anyway. It uses the same two colors. It is not "Other" — Other is app memory no group accounts for; small groups are real groups. **The cutoff is in pixels, not bytes or a percentage of RAM**, because what can be drawn is the only thing that matters: it scales with installed RAM and window width with no new constant (at ~500 pt it falls at ~48 MB on 8 GB, ~190 MB on 32 GB, ~1.5 GB on 256 GB). **Don't replace it with a byte threshold or a "smallest groups summing to <5%" rule** — both are arbitrary numbers that look right on one machine and match nothing on another. The tradeoff is deliberate: on a 256 GB machine a 1 GB app folds, because it really is a 2 px sliver. The cutoff is measured against the width `RiverLayout` actually lays bytes onto — the bar minus its inter-segment gaps — so a group that passes isn't then inflated to the minimum anyway; since the gap total depends on how many groups fold, `foldedIDs` iterates to a fixed point. A fold needs at least two members (`RiverFolding.minimumMembers`): an aggregate of one is the same inflated sliver it replaced, minus the group's name. Folding uses hysteresis carried across refreshes — a drawn group folds below `riverMinSegmentWidth - Theme.riverFoldDeadband` (2 pt) and a folded one unfolds only at 3 pt — so a group at the boundary doesn't hop in and out on every 5s refresh or window resize. Nothing folds until total physical RAM is known, and the bar draws no segments until it has been measured, rather than flashing every sliver unfolded for a frame on each window open. The list is told the members only while the segment is hovered (`highlightedGroupIDs`), not on every fold change, so groups crossing the cutoff during a window resize don't rebuild the NSOutlineView-backed list. **Folding is a river-only concern: never merge the members' rows in the group list.** Every group keeps its own row; hovering the segment highlights all of them, the readout gives the count, in-RAM and compressed totals, share of RAM, and the first few names, and clicking selects the first folded group in display order so you land on a real row and its normal detail panel, not a synthetic combined group
- **The river's two halves are named in a left gutter** — a static "In RAM" centered in the band and "Compressed" anchored to the midline, in a fixed `Theme.riverAxisLabelWidth` column so the bar's left edge doesn't move with the text. **Each is drawn in the tone of the half it names**, which is what makes the gutter a key and not just an axis: the word sits against the band it describes, so nothing has to be carried back to a legend elsewhere. Both tones are OKLab L=0.61 on a near-black ground and clear 5:1, brighter than the `textSecondary` grey they replaced. The lower one says "Compressed" rather than "Swapped" even though the quantity it names (each process's proportional compressed memory, below) includes compressed pages that have been swapped to disk, and the two cannot be split per process — the compressor is the half macOS reaches first, and it's the word Activity Monitor uses for the same memory
- **River groups are sized by proportional resident memory (PSS), not resident size** — resident size counts each shared page (dyld shared cache, system libraries) once per process mapping it, so summed over groups it overcounts badly (≈19 GB of "apps" against ≈12 GB of real app memory on a 32 GB machine). Private pages alone undercount the other way: they drop memory a group shares with itself — Chrome's renderers and GPU process, a VM's guest RAM mapping — which is most of what those apps hold. PSS is private pages plus each shared object's resident pages split evenly across the processes mapping it, so the sum counts each physical page once and self-shared memory stays in its group. It's measured by walking each process's VM regions (`SystemProbe.walkResidentPages`, `PROC_PIDREGIONINFO`); mapper counts come from the cached walks, because `pri_ref_count` undercounts. Walking everything costs ~2 s of CPU on a busy machine, so `ProportionalShareCache` budgets it: 100 ms per 5 s refresh (2% of a core), 500 ms per refresh during warm-up (largest processes first) until every process has been measured once, and processes younger than a 15 s cooloff are never walked. After warm-up, never-measured processes (newest first) are interleaved with the stalest measured ones so neither starves. The same walk counts compressed pages for the compressed figure (below). Each process's share (PSS ÷ resident at its walk) is applied to its current resident size until the next walk; unmeasured or unreadable processes use the resident-weighted default share. The group readout gives PSS as "in RAM" and the remainder of resident size as "shared"
- **The vocabulary is centralized in `Theme`** — `residentLabel`, `nonResidentLabel`, `nonResidentLabelLong`, and the two glosses. The gutter, the key, the detail-panel rows, and the `MemoryBarView` tooltip all read from those, so the naming decision above is now one edit rather than three that can drift. `ThemeTests` asserts `nonResidentLabelLong` merely *extends* `nonResidentLabel`, so the short and long forms can never become different words. The site copy is still a separate surface — change it in the same PR
- **The key is always on screen, and it costs no layout** — `MemoryKeyView` (swatch + term + gloss, both tones) lives in the row beneath the river that the hover readout already reserves. Idle it shows the key; hovering a segment cross-fades to that segment's readout, which answers the same question with real numbers. This exists because it had to: shown the app cold, people did not work out that the two colors were the difference between memory an app holds in RAM and memory macOS has taken back — and that difference is the entire product. **Don't demote it to a tooltip, a menu item, or a Settings toggle.** The same swatch keys the detail panel's "In RAM" / "Compressed / swapped" rows and the summary bar's compressed figure. `MemoryBarView` deliberately carries no legend of its own — the river's key is one screen-level key for a two-color palette, and repeating it per row would be noise. The glossed row measures ~523 pt but the window's own `minWidth: 600` leaves this row ~488 pt, so `MemoryKeyView` wraps its two layouts in `ViewThatFits` and drops to bare terms (~202 pt) when dragged narrow. **Lose the glosses, never truncate**: truncation eats the second entry's *term*, which is the half that does the keying
- **The river's height is dynamic and quantized** — the deepest stub sets it, snapped to `Theme.riverDepthQuantum` with a `Theme.riverShrinkDeadband` hysteresis, so a stub hovering at a boundary can't toggle the whole window's layout on every 5s refresh. Stub depths themselves stay continuous; only the container snaps. Depth caps at `Theme.riverMaxDepth`, so the bar never exceeds `riverHeight + riverMaxDepth`; a capped stub fades out over its last few pixels to say "continues past here"
- **The depth cap sits above the band height, and how stubs scale is an open question** — `riverMaxDepth` (48) against `riverHeight` (32) clips a stub once `nonResident / PSS > 1.5`; a clipped stub is 60% of the bar's height. Against PSS widths that ratio runs from under 1× to tens of ×, so on a heavily compressed machine the cap clips most large groups and the fade stops distinguishing them. The cap and the depth scale are due to be revisited together; don't tune one constant in isolation
- **Used and Available follow Activity Monitor, and partition physical RAM** — `SystemMemoryInfo.used` is app memory (internal pages minus purgeable) + wired + the compressor pool (`SystemMemoryInfo.usedBytes`); `available` is `totalPhysical - used`, which is truly free pages plus cached files (file-backed and purgeable pages macOS drops on demand, `cachedFiles`). **Don't add `inactive` back into available**: inactive pages include app memory that is still resident and still in each process's resident size. The river draws its system side from the same page counts (`RiverAccounting.compute`): Kernel is `wired` (never compressed or swapped), Compressor is the pool's physical size, Available is `available`, and what remains is the app region the groups share. Groups are scaled by `groupScale = min(1, appRegion / Σ group PSS)`; when they fall short, the shortfall is "Other" — app memory no group accounts for, such as processes Total Recall can't inspect. **Don't call it "free"** in the river or summary bar — truly free pages sit near zero because macOS fills spare RAM with file cache, so the river's trailing segment and the summary stat both say "Available", and the hover readout says how much of it is cached files. `available` is `0`, not all of RAM, when the host query fails. `compressed` is the pool's physical size (the figure inside `used`); `compressorStored` is the uncompressed size it holds, so the summary bar reads "compressed: 21.9 GB in 10.4 GB of RAM", falling back to the pool figure alone when the row is too narrow
- **Compressed memory per process is shared the way PSS shares resident memory** — the same region walk that measures PSS reads each region's `pri_pages_swapped_out` (pages in the compressor pager), so `ProportionalShareCache` gives each walked process its private compressed pages plus an even split of each shared object's compressed pages across the processes mapping it (`ProcessSnapshot.proportionalCompressedSize`). Summed over every process, each compressed page counts once, by the same rule as the blue band, and on a dev machine the total lands within 0.2% of the summed kernel counts. Copy-on-write regions don't split their compressed pages, so those are charged to the object; resident and compressed mapper counts are kept separately. **It is not clamped to the footprint**: a share of another process's shared compressed object is real memory this process maps, exactly as with resident PSS, and some helpers carry more of it than their footprint. Between walks (~100 s apart once warm) the figure moves by however much the kernel's own count for the process has changed since the walk — added, not applied as a ratio, because a process whose own count was near zero at its walk can still carry a large shared share, and a ratio would multiply it. The kernel's count is `task_vm_info.compressed`, read every refresh by `SystemProbe.getCompressionInfo` via `task_name_for_pid` + `task_info(TASK_VM_INFO)` (~12 ms for every process, no budget); a task *name* port is enough, and macOS hands one out for any same-user process without root or entitlements (~570 of ~830 processes on a dev machine). **Don't use the kernel's count directly**: it charges a process for compressed pages its regions don't hold — a VM reports ~11 GB against ~6 GB in its regions and a ~7 GB footprint. Before a process's first walk, `ProcessSnapshot.nonResidentMemory` uses that count clamped to `physFootprint`, which includes every compressed page the process owns; other users' processes (root daemons, WindowServer) can't be walked or counted and fall back to `physFootprint - residentSize`, which undercounts whenever resident size includes shared pages footprint leaves out. A group's non-resident memory is the sum of its processes' figures (`ProcessGroup.rawNonResidentMemory`), and the detail panel drops the "~" only when every process reported the kernel's count (`isNonResidentExact`). The count includes pages in compressor segments that have been written to swap: macOS compresses first and swaps whole segments mixing many processes' pages, so the in-RAM vs on-disk split **cannot be known per process from user space** — the region walk's `pages_swapped_out` means "in the compressor", `mach_vm_page_query` likewise, and the root-only routes (libsysmon, jetsam snapshots, `task_for_pid`) return the same number. **Don't estimate the split with system-wide ratios**: swap evicts the oldest segments first, so idle daemons are mostly on disk and active apps mostly in the pool, and a uniform ratio hides exactly that. For the same reason the per-process sum exceeds `compressorStored`, which counts only segments still in RAM. What *is* exact per process is swap activity: `task_vm_info.ledger_swapins` (lifetime bytes read back from swap), differenced between refreshes by `SwapActivityTracker`, gives each process's swap-in rate, and groups sum it. Above `Theme.swapActivityFloor` (1 MB/s) it shows as an amber "↓ 9 MB/s" `SwapActivityBadge` on the group row, "· reading X/s from swap" in the river readout, and a "Reading from swap" row in the detail panel. The Compressor readout carries the system-wide split instead: "Compressor — 14.3 GB (45% of total) holding 29.5 GB compressed · 12.7 GB in swap"
- **Swap gets no swatch in the summary bar.** macOS reports the compressor pool and swap separately system-wide, but the per-process figure the river draws cannot be split between them — so keying swap with its own chip would teach a color the bar never shows. It keeps `Theme.swapWarn` as a signal, not as a third member of the palette — the swap-activity badge is that signal: text in `swapWarn` that says an app is waiting on disk right now, never a fill or a swatch
- **Only two colors ever appear.** **Do not reintroduce a gradient between them**: at 258° and 62° they are near-complementary, so every interpolation path crosses the neutral axis and the midpoints come out muddy grey (chroma 0.021) — that is geometry, not a tuning problem. The clip fade is not an exception: it ramps `memoryCompressed` to transparent, so the hue never moves. `MemoryBarView` uses the same two constants, so the river and the row bars are one palette. Row bars keep their horizontal resident|compressed split via `Theme.hiddenFraction` — their width isn't tied to the RAM scale, so the area argument doesn't reach them, and a variable stub would fight the fixed `groupRowHeight`
- **Simulator processes group per booted device, not as system daemons** — a booted Xcode Simulator runs 150+ host processes under a per-device `launchd_sim`, from binaries inside the runtime's `RuntimeRoot` (and a few at plain `/usr/libexec` paths). `SimulatorClassifier` claims every descendant of a `launchd_sim` by walking `parentPid`, names the group from the device's `device.plist`, and gives each app installed on the device its **own top-level group** ("Ultralight (iPhone 17 Pro)"), not a sub-group: the app is the developer's code under test and the device is overhead, so they need to sit side by side in the river. iOS bundles keep their icon in `Assets.car`, which NSWorkspace can't render, so the app icon is read from the `CFBundleIconFiles` PNG Xcode copies into the bundle. App groups are keyed by bundle ID (so a Debug and a Staging build that share a display name stay apart), and those lookups are memoized across refreshes. **Only app groups are bulk-killable** (`SimulatorClassifier.isAppGroup`): SIGKILLing a device's daemons or CoreSimulatorService wedges the simulator instead of shutting it down — that's `simctl shutdown`'s job. It must run **before** `SystemServicesClassifier`, or the `/usr/libexec` children land in System. The simulator is not a VM: Virtualization.framework guests run inside one opaque `com.apple.Virtualization.VirtualMachine` process and have no host-visible children to group
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
  PR per ecosystem; majors come individually. Every ecosystem has a
  7-day `cooldown`: a release must be a week old before Dependabot proposes
  it, which gives a compromised or yanked version time to be caught upstream.
  Security updates bypass the cooldown. Swift bumps are titled `build:`
  so a Sparkle change shows up in the release changelog; the other two are
  `chore:`, which `cliff.toml` skips. Dependabot PRs run with a read-only
  token, so CI posts no coverage comment on them.
- **The site lints with Biome, not ESLint** — `site/biome.json` enables the
  linter only (recommended rules plus the React domain). The formatter and
  assist are off because the site has no house style to enforce: turning
  them on would rewrite every file. With no `typescript-eslint` peer range
  to satisfy, TypeScript majors reach the site like any other dependency.
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
- `DataLayer/` — SystemProbe (incl. `getVMRegions` for per-process VM map walking and `getCompressionInfo` for the kernel's per-process compressed count and swap-in counter), ProcessMonitor, RedactionFilter, ProcessActions, SnapshotCapture
- `Profiles/` — ProcessClassifier protocol, ClassifierRegistry, 6 classifiers, CommandLineParser
- `Theme/` — TotalRecallTheme (colors, fonts, spacing)
- `Utilities/` — Formatting, GroupDiagnostics, GroupSelection, RiverLayout, RiverFolding, RiverAccounting, ProportionalShareCache, SwapActivityTracker, InstanceMerger, TrendCalculator, SparklineLayout

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
