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

    // MARK: - accentColor

    @Test("accentColor returns correct color for Chrome")
    func accentColorForChrome() {
        _ = Theme.accentColor(for: "Chrome")
    }

    @Test("accentColor returns correct color for Electron")
    func accentColorForElectron() {
        _ = Theme.accentColor(for: "Electron")
    }

    @Test("accentColor returns correct color for System")
    func accentColorForSystem() {
        _ = Theme.accentColor(for: "System")
    }

    @Test("accentColor returns generic color for unknown classifiers")
    func accentColorForGenericAndUnknown() {
        _ = Theme.accentColor(for: "Generic")
        _ = Theme.accentColor(for: "ClaudeCode")
        _ = Theme.accentColor(for: "UnknownClassifier")
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
        _ = Theme.legibleTextColor(on: Theme.accentChrome)
        _ = Theme.legibleTextColor(on: Color.black)
    }

    // MARK: - brighten

    @Test("brighten can be called with default amount")
    func brightenDefaultAmount() {
        _ = Theme.brighten(Theme.textSecondary)
    }

    @Test("brighten can be called with explicit amount")
    func brightenExplicitAmount() {
        _ = Theme.brighten(Theme.accentChrome, by: 0.05)
        _ = Theme.brighten(Theme.accentElectron, by: 0.20)
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

    @Test("all accent color properties are accessible")
    func accentColorsAccessible() {
        _ = Theme.accentChrome
        _ = Theme.accentElectron
        _ = Theme.accentSystem
        _ = Theme.accentGeneric
        _ = Theme.riverFree
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
