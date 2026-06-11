import Testing
@testable import TotalRecallCore

@Suite("Trend Calculator")
struct TrendCalculatorTests {
    private let windowSize = 6

    @Test("Unknown when there is no history")
    func unknownWithNoHistory() {
        let trend = TrendCalculator.computeTrend(currentFootprint: 100, history: [], windowSize: windowSize)
        #expect(trend == .unknown)
    }

    @Test("Unknown with a single history sample")
    func unknownWithSingleSample() {
        let trend = TrendCalculator.computeTrend(currentFootprint: 100, history: [100], windowSize: windowSize)
        #expect(trend == .unknown)
    }

    @Test("Unknown when the oldest sample in the window is zero")
    func unknownWhenOldestSampleIsZero() {
        let trend = TrendCalculator.computeTrend(currentFootprint: 100, history: [0, 50], windowSize: windowSize)
        #expect(trend == .unknown)
    }

    @Test("Stable when the change is within the threshold")
    func stableWithinThreshold() {
        // +4% — below the 5% threshold
        let trend = TrendCalculator.computeTrend(currentFootprint: 104, history: [100, 102], windowSize: windowSize)
        #expect(trend == .stable)
    }

    @Test("Up when growth exceeds the threshold")
    func upWhenGrowthExceedsThreshold() {
        // +10% from the oldest sample in the window
        let trend = TrendCalculator.computeTrend(currentFootprint: 110, history: [100, 105], windowSize: windowSize)
        #expect(trend == .up)
    }

    @Test("Down when shrinkage exceeds the threshold")
    func downWhenShrinkageExceedsThreshold() {
        // -10% from the oldest sample in the window
        let trend = TrendCalculator.computeTrend(currentFootprint: 90, history: [100, 95], windowSize: windowSize)
        #expect(trend == .down)
    }

    @Test("Only the most recent windowSize samples are considered")
    func onlyRecentWindowConsidered() {
        // History has more entries than windowSize; the oldest entry within
        // the trailing window (10) should be used as the baseline, not the
        // very first ever recorded (1000) — which would otherwise dwarf the
        // current footprint and read as a steep decline.
        let history: [UInt64] = [1000, 10, 10, 10, 10, 10, 10]
        let trend = TrendCalculator.computeTrend(currentFootprint: 11, history: history, windowSize: 6)
        #expect(trend == .up)
    }

    @Test("Exactly at the positive threshold is not considered up")
    func exactlyAtPositiveThresholdIsStable() {
        // Exactly +5% change ratio — strictly greater than is required for "up"
        let trend = TrendCalculator.computeTrend(currentFootprint: 105, history: [100, 100], windowSize: windowSize)
        #expect(trend == .stable)
    }
}
