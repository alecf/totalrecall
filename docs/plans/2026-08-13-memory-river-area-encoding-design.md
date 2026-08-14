# Memory River: area-encoded resident and swapped memory

## The problem

The river's horizontal axis is resident bytes measured against total physical
RAM. Compressed and swapped memory has no room on that axis, so it is drawn as
a fill rising up the inside of each segment — a second quantity encoded as a
vertical fraction of a bar whose height means nothing. The two encodings share
a rectangle but not a scale, and the vertical one cannot be compared between
segments.

## The encoding

The river has a top band and a bottom band meeting at a midline.

**Top band** — fixed height `H`, every segment filling it. Width remains
resident bytes scaled against total physical RAM. The horizontal axis is
unchanged.

**Bottom band** — each segment hangs its own stub below the midline:

```
depth_i = H × (nonResident_i / resident_i)
```

Area is memory, and the constant is global. With `k` as the horizontal
bytes-per-pixel, a segment's width is `resident_i × k` and its top area is
`resident_i × k × H`, so area per byte is `k × H` for every segment. Setting
the stub's area to `nonResident_i × k × H` gives the depth above. A wide flat
stub and a narrow deep one of equal area hold equal memory — across segments,
not merely within one.

Two known departures from exact area:

- Segments below `riverMinSegmentWidth` (3 px) have inflated width and so
  inflated area. Their depth ratio stays locally honest. A 3 px sliver does not
  repay correcting.
- `Theme.memoryHiddenFloor` (100 MB) gates the stub to zero. The floor already
  existed to keep idle daemons from tinting; it matters more under area
  encoding, where a 40 MB daemon holding 90 MB of swap would otherwise sprout a
  full-depth spike out of nothing.

**Free** and **Other** are top-band only. Neither has swap data.

## The clamp

`nonResident / resident` is unbounded — a 40 MB daemon with 600 MB swapped
wants a stub 15× the top band. Depth clamps to a separate cap, `C`, capping the
river at `H + C`.

`C` is deliberately larger than `H`: 48 against a band of 32. The cap bites at
`nonResident / resident > C / H`, so those numbers put the clip threshold at
1.5 rather than the 1.0 that pinning `C = H` would give.

That gap is not arbitrary. Measured against live process data on a busy
machine, 12 of the 15 groups holding stubs clipped at a threshold of 1.0, and
only 8 at 1.5. Browsers and Electron shells sit right in that window — Chrome
at 1.46, Firefox at 1.45 — so a threshold of 1.0 made the fade the rule rather
than the exception, which is the opposite of what a "continues past here" mark
is for.

The ratios are bimodal: a tight cluster just past 1.0, then a cliff to
background daemons running 2.8× to 23×. A threshold of 1.5 clears the whole
lower cluster and sits at the knee — pushing to 2.0 would rescue one more group
and cost 16 px of permanent bar height. Nothing short of an absurd cap reaches
`lghub` at 23.5×, and for a process that really is 23× more swapped than
resident, the fade is telling the truth.

The tradeoff this locks in: a clipped stub is now 48 of the bar's 80 px, so 60%
of its height rather than 50%. Fewer segments fade, but the ones that still do
read as more orange-dominant against the shorter band.

A clamped segment is drawn short, and that must be visible rather than silent.
Its bottom 8 px ramps to transparent through a `.mask(LinearGradient)`; the
fill stays a flat `memoryCompressed` and opacity alone does the work.
Unclipped stubs keep a hard flat edge, so hard-versus-soft is the signal.

The ramp is a single-hue alpha fade, not an interpolation between
`memoryResident` and `memoryCompressed`. The prohibition on gradients in this
bar covers the latter: at 258° and 62° the two hues are near-complementary,
every path between them crosses the neutral axis, and the midpoints come out
muddy grey. An alpha ramp never leaves 62°.

Hovering a clamped segment already discloses the true figure — the readout
prints `· 4.2 GB compressed` today.

## Dynamic height

Container height is `H + maxDepth`, and `maxDepth` moves on every 5 s refresh,
which would set the whole window below the river breathing. Quantize the
container while leaving the segments continuous:

```
reserved = H + ceil(maxDepth / quantum) × quantum      // quantum = 12
```

Five heights: 32, 44, 56, 68, 80. Individual depths stay continuous and keep
the existing spring animation, so the data still reads smoothly.

Quantization alone flickers at a boundary: `maxDepth` oscillating around 24.0
toggles the container between 72 and 84 on alternating refreshes. Growth is
immediate; shrinking must clear a deadband below the *lower boundary of the
current step*, which is `currentStep - quantum`.

```
target = ceil(maxDepth / quantum) × quantum

grow:   target > currentStep                        → adopt target at once
shrink: maxDepth < (currentStep - quantum) - 4      → adopt target
else:                                               → hold currentStep
```

Measuring the deadband against the current step itself rather than its lower
boundary would never fire: a container at step 36 with `maxDepth` at 19 would
recompute `target` as 24 and sit there, because 19 still rounds up past 12.

A container at step 36 spans `maxDepth` in `(24, 36]`. It holds that height
until `maxDepth` drops below 20, then falls to 24. The current step is the sole
piece of carried state, held in `@State` on `MemoryRiverView` and passed into
the layout function.

## View structure

One `HStack` of per-segment columns, each column a `VStack(spacing: 0)`:

```
column_i = [ top rect,  height H,        fill memoryResident   ]
           [ stub,      height depth_i,  fill memoryCompressed ]  ← top-aligned
             within a spacer of height (reserved − H)
```

Columns rather than two stacked bands: hover, tap, `contentShape`, and the
accessibility label then each cover a top and its own stub as one unit, giving
one hit region and one accessibility element per group.

The whole-river `RoundedRectangle(cornerRadius: 8)` clip becomes an
`UnevenRoundedRectangle` — radius 8 on the top two corners, 0 on the bottom —
applied to the full-height container so the ragged bottom passes through
untouched. Per-segment radius 2 stays on top pieces; stubs keep radius 2 on
their bottom corners.

Labels sit vertically centered in the top band. The compressed fill no longer
rises through the text, so `legibleTextColor(on: residentTone)` becomes simply
correct rather than a compromise between two states.

`MemoryBarView` is unchanged. Its width is not tied to the RAM scale, so the
area argument does not reach it, and a variable stub would fight the fixed
44 px `groupRowHeight`. The two views still share the same two-color palette.

## Files

**`TotalRecall/Utilities/RiverLayout.swift`** — depth computation beside the
existing width math, pure and free of view types:

```swift
public struct RiverDepths: Equatable {
    public let depths: [Double]      // per segment, 0...C
    public let clipped: [Bool]       // true where the ratio exceeded the cap
    public let reserved: Double      // quantized container height
}

public static func computeDepths(
    residents: [UInt64], nonResidents: [UInt64],
    bandHeight: Double, depthCap: Double, hiddenFloor: UInt64,
    currentStep: Double, quantum: Double, shrinkDeadband: Double
) -> RiverDepths
```

**`TotalRecall/Theme/TotalRecallTheme.swift`** — `hiddenFraction` returns
`nonResident / (resident + nonResident)`, the wrong ratio for the river but the
right one for `MemoryBarView`, which still uses it. It stays untouched: the
river's ratio lives inside `computeDepths`, which takes the floor as a
parameter rather than reaching into the theme, so no sibling helper is needed.
Add `riverMaxDepth`, `riverDepthQuantum`, `riverShrinkDeadband`, and drop
`riverHeight` from 48 to 32.

**`TotalRecall/Views/MemoryRiverView.swift`** — column restructure, `@State`
for the current step, the fade mask.

**`TotalRecallTests/RiverLayoutTests.swift`** — area equivalence between a
wide-flat and a narrow-deep segment; a ratio of 1.0 still renders in full;
ratios past `C / H` clamp and set `clipped`, and one exactly at it does not;
sub-floor `nonResident` yields depth 0; quantization rounds up; hysteresis
holds the step until the deadband clears; zero-resident groups do not divide by
zero.

**Docs** — the architecture block and the Memory River design-decision bullet
in `CLAUDE.md` describe the vertical-fill encoding, as may `README.md` and the
`site/` feature copy. All three need rewriting to the area encoding.
