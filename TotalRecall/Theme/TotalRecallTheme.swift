import SwiftUI

/// All colors, typography, and spacing for Total Recall.
/// Single source of truth — no magic values elsewhere.
/// Colors designed in OKLCH for perceptual uniformity (values in comments).
public enum Theme {
    // MARK: - Backgrounds

    public static let bgVoid     = Color(red: 0.051, green: 0.055, blue: 0.071)  // oklch(0.13 0.005 260)
    public static let bgSurface  = Color(red: 0.071, green: 0.075, blue: 0.094)  // oklch(0.16 0.005 260)
    public static let bgHover    = Color(red: 0.098, green: 0.106, blue: 0.129)  // oklch(0.20 0.008 260)
    public static let bgSelected = Color(red: 0.114, green: 0.122, blue: 0.157)  // oklch(0.22 0.015 260)

    // MARK: - Text

    public static let textPrimary   = Color(red: 0.92, green: 0.91, blue: 0.89)  // oklch(0.93 0.005 90)
    public static let textSecondary = Color(red: 0.47, green: 0.48, blue: 0.52)  // oklch(0.55 0.005 260)
    public static let textMuted     = Color(red: 0.40, green: 0.41, blue: 0.44)  // oklch(0.48 0.005 260)

    // MARK: - Memory State

    /// The two tones every memory view is drawn from: what is really in RAM,
    /// and what has been compressed or swapped out of it.
    ///
    /// The Memory River measures resident bytes against total physical RAM, so
    /// an app holding a large compressed or swapped tail occupies a band far
    /// narrower than its real cost. The bar answers that by splitting at a
    /// midline: `memoryResident` fills a fixed-height upper band, and
    /// `memoryCompressed` hangs below it as a stub whose depth is
    /// `nonResident / resident`. Because width is already resident bytes, the
    /// stub's *area* lands on the same scale — a deep stub is an app much
    /// larger than it looks, and two stubs of equal area hold equal memory
    /// wherever they sit in the bar.
    ///
    /// Only these two colors ever appear on screen. An earlier design
    /// interpolated a gradient between them, which failed for a reason worth
    /// recording: at 258° and 62° they sit almost opposite on the hue circle,
    /// and every path between two near-complementary colors crosses the neutral
    /// axis. The blended midpoints came out muddy grey (chroma 0.021) no matter
    /// how they were tuned — that is geometry, not a tuning mistake. Two flat
    /// tones and a geometry sidestep it entirely.
    ///
    /// That prohibition is on interpolating *between* the two hues. Ramping one
    /// of them to transparent is a different operation — the hue never moves —
    /// which is what marks a clipped stub in the river.
    ///
    /// Both sit at OKLab L=0.61, the range the rest of the UI occupies, so they
    /// carry equal visual weight and `legibleTextColor` resolves the same way
    /// for both.
    public static let memoryResident   = Color(red: 0.360, green: 0.518, blue: 0.753)  // oklch(0.61 0.102 258)
    public static let memoryCompressed = Color(red: 0.727, green: 0.434, blue: 0.110)  // oklch(0.61 0.130 62)

    /// The words that name those two tones, defined once. Every view that
    /// draws a swatch, an axis label, a table row, or a tooltip pulls its text
    /// from here, so the vocabulary users learn from the river's gutter is the
    /// same vocabulary the detail panel and the summary stats use.
    ///
    /// `nonResidentLabel` says "Compressed" and not "Swapped" even though the
    /// quantity it names (`physFootprint - residentSize`) conflates the two and
    /// cannot be split per process: the compressor is the half macOS reaches
    /// first, and it is the word Activity Monitor uses for the same memory.
    /// `nonResidentLabelLong` names both, for the places with room to say so.
    public static let residentLabel = "In RAM"
    public static let nonResidentLabel = "Compressed"
    public static let nonResidentLabelLong = "Compressed / swapped"

    /// One-line glosses paired with the labels in `MemoryKeyView`. The whole
    /// point of the app is the gap between what an app is charged for and what
    /// it actually occupies, so the key states that gap in words rather than
    /// leaving two colors to be decoded.
    public static let residentGloss = "really in physical memory"
    public static let nonResidentGloss = "moved out of RAM by macOS"

    /// Below this much non-resident memory a segment gets no stub at all.
    /// macOS swaps idle daemons on purpose, and the depth ratio is
    /// `nonResident / resident` — so a 40 MB helper holding 90 MB of swap would
    /// otherwise sprout a full-depth spike out of nothing. The floor matters
    /// more under area encoding than it did when it only suppressed a tint.
    public static let memoryHiddenFloor: UInt64 = 100 * 1024 * 1024

    /// Fill for the trailing "Free" segment of the Memory River. Dark, low-chroma,
    /// neutral so it reads as "empty bar" rather than as a colored group.
    public static let riverFree     = Color(red: 0.114, green: 0.122, blue: 0.149)  // oklch(0.22 0.005 260)
    public static let riverOther    = Color(red: 0.184, green: 0.176, blue: 0.141)  // oklch(0.28 0.015 90)

    // MARK: - Signals

    public static let pressureOk   = Color(red: 0.204, green: 0.780, blue: 0.349)  // oklch(0.75 0.20 145)
    public static let pressureWarn  = Color(red: 1.000, green: 0.839, blue: 0.039)  // oklch(0.82 0.18 85)
    public static let pressureCrit  = Color(red: 1.000, green: 0.271, blue: 0.227)  // oklch(0.68 0.22 25)
    public static let swapWarn      = Color(red: 1.000, green: 0.624, blue: 0.039)  // oklch(0.76 0.16 65)
    public static let trendUp       = Color(red: 1.000, green: 0.271, blue: 0.227)  // red-tinted (growing = bad)
    public static let trendDown     = Color(red: 0.204, green: 0.780, blue: 0.349)  // green-tinted (shrinking = good)

    // MARK: - Typography

    public static let numberFont = Font.system(size: 15, design: .monospaced).bold()
    public static let numberFontLarge = Font.system(size: 20, design: .monospaced).bold()
    public static let numberFontHero = Font.system(size: 28, design: .monospaced).bold()
    public static let labelFont = Font.system(size: 13, weight: .medium)
    public static let secondaryFont = Font.system(size: 11)
    public static let explanationFont = Font.system(size: 11).italic()
    public static let processFont = Font.system(size: 12)
    public static let processNumberFont = Font.system(size: 12, design: .monospaced)
    public static let riverLabelFont = Font.system(size: 11, weight: .semibold)

    // MARK: - Spacing

    /// Height of the river's fixed upper band, and the scale factor for stub
    /// depth: a stub hangs `riverHeight × nonResident / resident` below the
    /// midline.
    public static let riverHeight: CGFloat = 32
    /// Deepest a stub may hang before it is drawn short and faded.
    ///
    /// Deliberately larger than `riverHeight`. The cap bites at
    /// `nonResident / resident > riverMaxDepth / riverHeight` — 1.5 at these
    /// values, so an app clips only once it has half again more swapped than
    /// resident. Tying the cap to the band height instead put the threshold at
    /// 1.0, and enough real apps (browsers, Docker, Electron shells) sit past
    /// that on a busy machine that the fade stopped reading as an exception.
    /// The bar's ceiling is `riverHeight + riverMaxDepth`.
    public static let riverMaxDepth: CGFloat = 48
    public static let riverCornerRadius: CGFloat = 8

    /// The bar's reserved height snaps to multiples of this, giving five
    /// possible heights (32, 44, 56, 68, 80) instead of a value that drifts on
    /// every 5 s refresh and sets the whole window below it breathing.
    /// Individual stubs stay continuous; only the container snaps.
    public static let riverDepthQuantum: CGFloat = 12
    /// How far below its step's lower boundary the deepest stub must fall
    /// before the container steps down. Without it, a stub hovering at a
    /// boundary toggles the bar's height on alternating refreshes.
    public static let riverShrinkDeadband: CGFloat = 4
    /// Height of the fade that marks a stub clamped at `riverMaxDepth`. An alpha
    /// ramp on `memoryCompressed` alone, never a blend toward `memoryResident`.
    public static let riverClipFadeHeight: CGFloat = 8
    /// Neighbouring segments now sit on one blue→amber ramp rather than
    /// carrying unrelated per-app hues, so adjacent bands can be similar
    /// colors. The gap does the dividing: background showing through reads as
    /// structure and cannot be mistaken for data, whereas alternating the
    /// lightness would inject a second, meaningless signal into an encoding
    /// whose whole premise is that lightness stays constant.
    public static let riverSegmentGap: CGFloat = 2
    public static let riverMinSegmentWidth: CGFloat = 3
    /// Hide segment labels below this width — anything narrower can't fit useful text.
    public static let riverLabelMinSegmentWidth: CGFloat = 32
    /// Left gutter naming the bar's two halves ("In RAM" above the midline,
    /// "Compressed" below). Fixed rather than intrinsic so the bar's left edge
    /// — and the hover readout indented to meet it — sit at the same x whatever
    /// the labels say.
    public static let riverAxisLabelWidth: CGFloat = 72
    public static let riverAxisLabelGap: CGFloat = 8
    public static let breathingRoom: CGFloat = 24
    public static let groupRowHeight: CGFloat = 44
    public static let processRowIndent: CGFloat = 24
    public static let dotSize: CGFloat = 8
    /// Chip drawn beside a memory term to tie the word to the color. Sized and
    /// cornered like a miniature river segment rather than as a dot, so it
    /// reads as a sample of the bar and not as a status light — the pressure
    /// indicator already owns circles.
    public static let keySwatchSize: CGFloat = 9
    public static let keySwatchCornerRadius: CGFloat = 2
    public static let iconSize: CGFloat = 20

    /// Per-row memory-history sparkline. Occupies the column where the static
    /// composition bar used to sit, a touch wider and taller so the shape reads.
    public static let sparklineWidth: CGFloat = 56
    public static let sparklineHeight: CGFloat = 16
    public static let sparklineLineWidth: CGFloat = 1.5

    /// Fixed width for the memory text column so values align across rows.
    /// Fits the widest realistic value ("25.0 GB" = 7 chars) in numberFont (15pt bold monospaced).
    public static let memoryColumnWidth: CGFloat = 80

    // MARK: - Helpers

    public static func pressureColor(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return pressureOk
        case .warning: return pressureWarn
        case .critical: return pressureCrit
        }
    }

    public static func trendColor(for trend: Trend) -> Color {
        switch trend {
        case .up: return trendUp
        case .down: return trendDown
        case .stable: return textMuted
        case .unknown: return textMuted.opacity(0.5)
        }
    }

    /// Share of a footprint that is compressed or swapped, as `0...1` — the
    /// fraction of a river segment's height drawn in `memoryCompressed`.
    /// Returns 0 below `memoryHiddenFloor` so idle daemons stay quiet.
    public static func hiddenFraction(resident: UInt64, nonResident: UInt64) -> Double {
        guard nonResident >= memoryHiddenFloor else { return 0 }
        let (total, overflowed) = resident.addingReportingOverflow(nonResident)
        guard !overflowed, total > 0 else { return 0 }
        return min(1, Double(nonResident) / Double(total))
    }

    public static func hiddenFraction(for group: ProcessGroup) -> Double {
        hiddenFraction(
            resident: group.residentMemory,
            nonResident: group.rawNonResidentMemory
        )
    }

    /// Pick black or white text for maximum contrast against `backgroundColor`.
    /// Uses WCAG relative luminance; 0.179 is the crossover where contrast vs white
    /// equals contrast vs black, so above it black wins and below it white wins.
    public static func legibleTextColor(on backgroundColor: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(backgroundColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        let toLinear: (CGFloat) -> CGFloat = { c in
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b)
        return luminance > 0.179 ? Color.black : Color.white
    }

    /// Brighten a color by increasing RGB proportionally.
    /// Approximation of OKLCH L+delta for hover states.
    public static func brighten(_ color: Color, by amount: CGFloat = 0.12) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor = 1.0 + amount
        return Color(
            red: min(r * factor, 1),
            green: min(g * factor, 1),
            blue: min(b * factor, 1)
        )
    }
}
