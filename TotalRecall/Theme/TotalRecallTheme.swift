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

    // MARK: - Memory State Ramp

    /// Five-stop ramp expressing how much of a group's physical footprint is
    /// *not* resident — the compressed and swapped pages that the Memory
    /// River cannot show, because its widths measure resident bytes against
    /// total physical RAM. A narrow amber band is an app far larger than it
    /// looks; a wide blue one is an app being honest about its size.
    ///
    /// The stops interpolate in a straight line through OKLab between a cool
    /// blue and a warm amber. Rotating hue would be the obvious construction,
    /// but both arcs are already spoken for: rotating down passes through the
    /// green that `pressureOk` and `trendDown` own, and rotating up passes
    /// through the red that `pressureCrit` and `trendUp` own. Either would
    /// have the river speaking the pressure palette's language. A straight
    /// OKLab line puts its midpoint on a near-neutral taupe instead, which
    /// reads as "partly hidden" without borrowing another palette's meaning.
    ///
    /// Lightness is held at OKLab L=0.61 for every stop — the same range the
    /// rest of the UI occupies — so segments carry equal visual weight and
    /// `legibleTextColor` resolves identically across all five. Labels
    /// therefore never change color as a segment moves along the ramp.
    public static let memoryRamp: [Color] = [
        Color(red: 0.360, green: 0.518, blue: 0.753),  // oklch(0.61 0.102 258)
        Color(red: 0.470, green: 0.512, blue: 0.626),  // oklch(0.61 0.046 269)
        Color(red: 0.563, green: 0.496, blue: 0.493),  // oklch(0.61 0.021 21)
        Color(red: 0.648, green: 0.470, blue: 0.342),  // oklch(0.61 0.073 57)
        Color(red: 0.727, green: 0.434, blue: 0.110),  // oklch(0.61 0.130 62)
    ]

    /// The ends of `memoryRamp`, named for the per-process composition bars
    /// that split one process into resident and non-resident halves. Sharing
    /// these constants is what stops a river band and its row bar from
    /// drifting into two palettes that merely happen to look alike.
    public static var memoryResident: Color { memoryRamp[0] }
    public static var memoryCompressed: Color { memoryRamp[memoryRamp.count - 1] }

    /// Below this much non-resident memory a group stays at the coolest stop
    /// regardless of its ratio. macOS swaps idle daemons on purpose, so
    /// without a floor a 45 MB indexer sitting at 90% swapped would be the
    /// loudest thing on screen while Chrome stayed quiet.
    public static let memoryRampFloor: UInt64 = 100 * 1024 * 1024

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

    public static let riverHeight: CGFloat = 48
    public static let riverCornerRadius: CGFloat = 8
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
    public static let breathingRoom: CGFloat = 24
    public static let groupRowHeight: CGFloat = 44
    public static let processRowIndent: CGFloat = 24
    public static let dotSize: CGFloat = 8
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

    /// Place a resident/non-resident pair on `memoryRamp`. Groups whose
    /// non-resident tail falls below `memoryRampFloor` stay at the coolest
    /// stop whatever their ratio, so only groups hiding a meaningful amount
    /// of memory light up.
    public static func memoryStateColor(resident: UInt64, nonResident: UInt64) -> Color {
        guard nonResident >= memoryRampFloor else { return memoryRamp[0] }
        let (total, overflowed) = resident.addingReportingOverflow(nonResident)
        guard !overflowed, total > 0 else { return memoryRamp[0] }

        switch Double(nonResident) / Double(total) {
        case ..<0.10: return memoryRamp[0]
        case ..<0.30: return memoryRamp[1]
        case ..<0.50: return memoryRamp[2]
        case ..<0.75: return memoryRamp[3]
        default:      return memoryRamp[4]
        }
    }

    public static func memoryStateColor(for group: ProcessGroup) -> Color {
        memoryStateColor(
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
