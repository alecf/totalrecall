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

    // MARK: - Group Accents (all at L=0.72, C=0.15 for equal visual weight)

    public static let accentChrome   = Color(red: 0.337, green: 0.494, blue: 0.827)  // oklch(0.72 0.15 260)
    public static let accentElectron = Color(red: 0.506, green: 0.400, blue: 0.816)  // oklch(0.72 0.15 310)
    public static let accentSystem   = Color(red: 0.820, green: 0.420, blue: 0.220)  // oklch(0.72 0.15 35)
    public static let accentGeneric  = Color(red: 0.45, green: 0.46, blue: 0.50)     // oklch(0.55 0.02 260)

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

    // MARK: - Spacing

    public static let riverHeight: CGFloat = 48
    public static let riverCornerRadius: CGFloat = 8
    public static let riverSegmentGap: CGFloat = 1
    public static let riverMinSegmentWidth: CGFloat = 3
    public static let breathingRoom: CGFloat = 24
    public static let groupRowHeight: CGFloat = 44
    public static let processRowIndent: CGFloat = 24
    public static let dotSize: CGFloat = 8
    public static let iconSize: CGFloat = 20

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

    public static func accentColor(for classifierName: String) -> Color {
        switch classifierName {
        case "Chrome": return accentChrome
        case "Electron": return accentElectron
        case "System": return accentSystem
        default: return accentGeneric
        }
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
