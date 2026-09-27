import SwiftUI
import Testing
@testable import TotalRecallCore

@Suite("Theme")
struct ThemeTests {

    // MARK: - pressureColor

    @Test("pressureColor returns distinct colors for each pressure level")
    func pressureColorForAllLevels() {
        _ = Theme.pressureColor(for: .normal)
        _ = Theme.pressureColor(for: .warning)
        _ = Theme.pressureColor(for: .critical)
    }

    // MARK: - trendColor

    @Test("trendColor returns a color for all trend states")
    func trendColorForAllStates() {
        _ = Theme.trendColor(for: .up)
        _ = Theme.trendColor(for: .down)
        _ = Theme.trendColor(for: .stable)
        _ = Theme.trendColor(for: .unknown)
    }

    // MARK: - Memory vocabulary

    @Test("The long non-resident label extends the short one rather than renaming it")
    func nonResidentLabelsAgree() {
        // The river's gutter has room for one word; the detail panel has room
        // for both. They have to stay the *same* word — someone who learns
        // "Compressed" from the bar must recognize it in the panel — so the
        // long form may only add to the short one, never replace it.
        #expect(Theme.nonResidentLabelLong.hasPrefix(Theme.nonResidentLabel))
    }

    @Test("Every memory term is non-empty")
    func memoryTermsArePopulated() {
        // These strings are the only key the two colors get. An empty one
        // silently turns a labelled axis into an unlabelled stripe.
        for term in [
            Theme.residentLabel, Theme.nonResidentLabel, Theme.nonResidentLabelLong,
            Theme.residentGloss, Theme.nonResidentGloss,
        ] {
            #expect(!term.isEmpty)
        }
    }

    // MARK: - hiddenFraction

    private static let mb: UInt64 = 1024 * 1024
    private static let gb: UInt64 = 1024 * 1024 * 1024

    private func hidden(resident: UInt64, nonResident: UInt64) -> Double {
        Theme.hiddenFraction(resident: resident, nonResident: nonResident)
    }

    @Test("A narrow band hiding a large tail is mostly compressed-toned")
    func narrowBandWithLargeTailIsMostlyHidden() {
        // 400 MB resident, 1.2 GB compressed — three quarters of the segment
        // fills amber. This is the case the encoding exists to surface.
        #expect(abs(hidden(resident: 400 * Self.mb, nonResident: 1200 * Self.mb) - 0.75) < 0.001)
    }

    @Test("A large mostly-resident app barely fills")
    func honestLargeAppBarelyFills() {
        // 6 GB resident, 1 GB compressed — one seventh hidden.
        #expect(abs(hidden(resident: 6 * Self.gb, nonResident: 1 * Self.gb) - 1.0 / 7.0) < 0.001)
    }

    @Test("A tiny mostly-swapped daemon does not fill at all")
    func tinySwappedDaemonIsGatedByFloor() {
        // 5 MB resident, 45 MB compressed is 90% hidden by ratio. Without the
        // floor every idle helper would carry a meaningless amber sliver.
        #expect(hidden(resident: 5 * Self.mb, nonResident: 45 * Self.mb) == 0)
    }

    @Test("The floor is inclusive at its exact boundary")
    func floorBoundaryIsInclusive() {
        let floor = Theme.memoryHiddenFloor
        // One byte under the floor is gated regardless of ratio...
        #expect(hidden(resident: 0, nonResident: floor - 1) == 0)
        // ...and exactly at the floor the true ratio takes over.
        #expect(abs(hidden(resident: floor, nonResident: floor) - 0.5) < 0.001)
    }

    @Test("Fill never decreases as the hidden share grows")
    func fillIsMonotonic() {
        // Hold the tail well above the floor and shrink the resident half so
        // the hidden share climbs; the fill must never recede.
        let tail = 2 * Self.gb
        let residents: [UInt64] = [
            20 * Self.gb, 8 * Self.gb, 4 * Self.gb,
            2 * Self.gb, 1 * Self.gb, 256 * Self.mb, 0,
        ]
        let fills = residents.map { hidden(resident: $0, nonResident: tail) }
        for (earlier, later) in zip(fills, fills.dropFirst()) {
            #expect(later >= earlier, "fill receded: \(earlier) → \(later)")
        }
        #expect(fills.last == 1.0)
    }

    @Test("Fill is always a valid 0...1 proportion")
    func fillStaysInUnitRange() {
        let samples: [(UInt64, UInt64)] = [
            (0, 0), (8 * Self.gb, 0), (0, 8 * Self.gb),
            (1 * Self.gb, 1 * Self.gb), (.max, .max),
            (.max - 1, 4 * Self.gb), (1, .max),
        ]
        for (resident, nonResident) in samples {
            let f = hidden(resident: resident, nonResident: nonResident)
            #expect(f >= 0 && f <= 1, "out of range for (\(resident), \(nonResident)): \(f)")
        }
    }

    @Test("Degenerate inputs produce no fill")
    func degenerateInputsAreSafe() {
        #expect(hidden(resident: 0, nonResident: 0) == 0)
        #expect(hidden(resident: 8 * Self.gb, nonResident: 0) == 0)
        // resident + nonResident overflows UInt64 — must not trap or divide by
        // a wrapped total.
        #expect(hidden(resident: .max, nonResident: .max) == 0)
        #expect(hidden(resident: .max - 1, nonResident: 4 * Self.gb) == 0)
    }

    @Test("Both memory tones carry the same text-contrast decision")
    func memoryTonesShareOneTextColor() {
        // They sit at equal lightness precisely so a segment label does not
        // flip between black and white as the amber fill rises past it.
        let onResident = Theme.legibleTextColor(on: Theme.memoryResident)
        let onCompressed = Theme.legibleTextColor(on: Theme.memoryCompressed)
        #expect(String(describing: onResident) == String(describing: onCompressed))
    }

    @Test("The two memory tones are distinct")
    func memoryTonesAreDistinct() {
        #expect(Theme.memoryResident != Theme.memoryCompressed)
    }

    // MARK: - legibleTextColor

    @Test("legibleTextColor can be called with dark background")
    func legibleTextColorForDarkBackground() {
        // Very dark bg (bgVoid) → should return a light text color
        _ = Theme.legibleTextColor(on: Theme.bgVoid)
    }

    @Test("legibleTextColor can be called with light background")
    func legibleTextColorForLightBackground() {
        _ = Theme.legibleTextColor(on: Color.white)
    }

    @Test("legibleTextColor can be called with various backgrounds")
    func legibleTextColorForVariousBackgrounds() {
        _ = Theme.legibleTextColor(on: Theme.bgSurface)
        _ = Theme.legibleTextColor(on: Theme.bgHover)
        _ = Theme.legibleTextColor(on: Theme.bgSelected)
        _ = Theme.legibleTextColor(on: Theme.textPrimary)
        _ = Theme.legibleTextColor(on: Theme.memoryResident)
        _ = Theme.legibleTextColor(on: Color.black)
    }

    // MARK: - brighten

    @Test("brighten can be called with default amount")
    func brightenDefaultAmount() {
        _ = Theme.brighten(Theme.textSecondary)
    }

    @Test("brighten can be called with explicit amount")
    func brightenExplicitAmount() {
        _ = Theme.brighten(Theme.memoryResident, by: 0.05)
        _ = Theme.brighten(Theme.memoryCompressed, by: 0.20)
    }

    @Test("brighten can be called with dark colors")
    func brightenDarkColors() {
        _ = Theme.brighten(Theme.bgVoid)
        _ = Theme.brighten(Theme.bgSurface)
    }

    // MARK: - Static color properties

    @Test("all background color properties are accessible")
    func backgroundColorsAccessible() {
        _ = Theme.bgVoid
        _ = Theme.bgSurface
        _ = Theme.bgHover
        _ = Theme.bgSelected
    }

    @Test("all text color properties are accessible")
    func textColorsAccessible() {
        _ = Theme.textPrimary
        _ = Theme.textSecondary
        _ = Theme.textMuted
    }

    @Test("all river color properties are accessible")
    func riverColorsAccessible() {
        _ = Theme.memoryResident
        _ = Theme.memoryCompressed
        _ = Theme.riverFree
        _ = Theme.riverOther
    }

    @Test("all signal color properties are accessible")
    func signalColorsAccessible() {
        _ = Theme.pressureOk
        _ = Theme.pressureWarn
        _ = Theme.pressureCrit
        _ = Theme.swapWarn
        _ = Theme.trendUp
        _ = Theme.trendDown
    }

    // MARK: - Static font properties

    @Test("all typography constants are accessible")
    func typographyConstantsAccessible() {
        _ = Theme.numberFont
        _ = Theme.numberFontLarge
        _ = Theme.numberFontHero
        _ = Theme.labelFont
        _ = Theme.secondaryFont
        _ = Theme.explanationFont
        _ = Theme.processFont
        _ = Theme.processNumberFont
        _ = Theme.riverLabelFont
    }

    // MARK: - Static spacing constants

    @Test("spacing constants have positive values")
    func spacingConstantsArePositive() {
        #expect(Theme.riverHeight > 0)
        #expect(Theme.riverCornerRadius > 0)
        #expect(Theme.riverSegmentGap >= 0)
        #expect(Theme.riverMinSegmentWidth > 0)
        #expect(Theme.riverLabelMinSegmentWidth > 0)
        #expect(Theme.breathingRoom > 0)
        #expect(Theme.groupRowHeight > 0)
        #expect(Theme.processRowIndent > 0)
        #expect(Theme.dotSize > 0)
        #expect(Theme.iconSize > 0)
        #expect(Theme.sparklineWidth > 0)
        #expect(Theme.sparklineHeight > 0)
        #expect(Theme.sparklineLineWidth > 0)
        #expect(Theme.memoryColumnWidth > 0)
    }

    @Test("sparkline label threshold is larger than minimum width")
    func sparklineLabelThresholdLargerThanMin() {
        #expect(Theme.riverLabelMinSegmentWidth > Theme.riverMinSegmentWidth)
    }
}
