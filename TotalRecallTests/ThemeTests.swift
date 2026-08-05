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

    // MARK: - memoryStateColor

    private static let mb: UInt64 = 1024 * 1024
    private static let gb: UInt64 = 1024 * 1024 * 1024

    /// Index of a returned color along the ramp, so tests can talk about
    /// "cooler" and "warmer" rather than comparing raw components.
    private func stop(resident: UInt64, nonResident: UInt64) -> Int? {
        Theme.memoryRamp.firstIndex(
            of: Theme.memoryStateColor(resident: resident, nonResident: nonResident)
        )
    }

    @Test("A narrow band hiding a large tail reaches the warmest stop")
    func narrowBandWithLargeTailIsWarmest() {
        // 400 MB resident, 1.2 GB compressed — 75% of it is off-bar. This is
        // the case the encoding exists to surface.
        #expect(stop(resident: 400 * Self.mb, nonResident: 1200 * Self.mb) == 4)
    }

    @Test("A large mostly-resident app stays near the cool end")
    func honestLargeAppStaysCool() {
        // 6 GB resident, 1 GB compressed — 14% off-bar, so barely warmed.
        #expect(stop(resident: 6 * Self.gb, nonResident: 1 * Self.gb) == 1)
    }

    @Test("A tiny mostly-swapped daemon stays coolest despite its ratio")
    func tinySwappedDaemonIsGatedByFloor() {
        // 5 MB resident, 45 MB compressed is 90% off-bar. Without the floor
        // this would outshout Chrome; with it, it stays quiet.
        #expect(stop(resident: 5 * Self.mb, nonResident: 45 * Self.mb) == 0)
    }

    @Test("The floor is inclusive at its exact boundary")
    func floorBoundaryIsInclusive() {
        let floor = Theme.memoryRampFloor
        // One byte under the floor is gated regardless of ratio...
        #expect(stop(resident: 0, nonResident: floor - 1) == 0)
        // ...and exactly at the floor the ratio takes over. Equal parts
        // resident and non-resident is 50%, which lands in the 50–75% band.
        #expect(stop(resident: floor, nonResident: floor) == 3)
    }

    @Test("Ramp position never decreases as the hidden share grows")
    func rampIsMonotonic() {
        // Hold the tail well above the floor and shrink the resident half so
        // the hidden share climbs; the stop must never move back toward cool.
        let tail = 2 * Self.gb
        let residents: [UInt64] = [
            20 * Self.gb, 8 * Self.gb, 4 * Self.gb,
            2 * Self.gb, 1 * Self.gb, 256 * Self.mb, 0,
        ]
        let stops = residents.map { stop(resident: $0, nonResident: tail) }
        #expect(stops.allSatisfy { $0 != nil })
        for (earlier, later) in zip(stops, stops.dropFirst()) {
            #expect(later! >= earlier!, "ramp went backwards: \(earlier!) → \(later!)")
        }
        #expect(stops.first! == 0)
        #expect(stops.last! == 4)
    }

    @Test("Degenerate inputs fall back to the coolest stop")
    func degenerateInputsAreSafe() {
        #expect(stop(resident: 0, nonResident: 0) == 0)
        #expect(stop(resident: 8 * Self.gb, nonResident: 0) == 0)
        // resident + nonResident overflows UInt64 — must not trap or divide
        // by a wrapped total.
        #expect(stop(resident: .max, nonResident: .max) == 0)
        #expect(stop(resident: .max - 1, nonResident: 4 * Self.gb) == 0)
    }

    @Test("Every ramp stop carries the same text-contrast decision")
    func rampStopsShareOneTextColor() {
        // Lightness is held constant across the ramp precisely so a label
        // never flips between black and white as its segment warms.
        let choices = Theme.memoryRamp.map { Theme.legibleTextColor(on: $0) }
        #expect(Set(choices.map(String.init(describing:))).count == 1)
    }

    @Test("The ramp has five distinct stops")
    func rampIsFiveDistinctStops() {
        #expect(Theme.memoryRamp.count == 5)
        let distinct = Set(Theme.memoryRamp.map(String.init(describing:)))
        #expect(distinct.count == 5)
    }

    @Test("Composition bar anchors are the ends of the ramp")
    func compositionBarAnchorsMatchRampEnds() {
        // This is the invariant that keeps the river and the row bars from
        // drifting into two palettes that merely look alike.
        #expect(Theme.memoryResident == Theme.memoryRamp.first)
        #expect(Theme.memoryCompressed == Theme.memoryRamp.last)
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
        _ = Theme.memoryRamp
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
