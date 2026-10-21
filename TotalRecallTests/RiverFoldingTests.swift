import Testing
@testable import TotalRecallCore

@Suite("Memory River Folding")
struct RiverFoldingTests {
    static let gb: UInt64 = 1_073_741_824
    static let mb: UInt64 = 1_048_576

    /// A second group far below every cutoff, so a fold always has the two
    /// members it needs and each test isolates the group under test (`g0`).
    static let companion = 1 * mb

    func fold(
        residents: [UInt64],
        totalPhysical: UInt64,
        barWidth: Double = 500,
        gap: Double = 0,
        extraSegments: Int = 0,
        previouslyFolded: Set<String> = []
    ) -> Set<String> {
        RiverFolding.foldedIDs(
            ids: residents.indices.map { "g\($0)" },
            residents: residents,
            totalPhysical: totalPhysical,
            barWidth: barWidth,
            gap: gap,
            extraSegments: extraSegments,
            unfoldWidth: 3,
            foldWidth: 2,
            previouslyFolded: previouslyFolded
        )
    }

    /// Whether `g0` folds, alongside a companion that always does.
    func folds(_ resident: UInt64, totalPhysical: UInt64, barWidth: Double = 500, previouslyFolded: Bool = false) -> Bool {
        fold(
            residents: [resident, Self.companion],
            totalPhysical: totalPhysical,
            barWidth: barWidth,
            previouslyFolded: previouslyFolded ? ["g0", "g1"] : []
        ).contains("g0")
    }

    // MARK: - The cutoff scales with RAM, not a fixed byte count

    @Test("A 9 MB group folds on 32 GB")
    func smallGroupFoldsOn32GB() {
        let result = fold(residents: [8 * Self.gb, 9 * Self.mb, Self.companion], totalPhysical: 32 * Self.gb)
        #expect(result == ["g1", "g2"])
    }

    @Test("The same 100 MB group is drawn on 8 GB but folded on 32 GB")
    func cutoffScalesWithRAM() {
        // 500 px: 8 GB → 16 MB/px (100 MB ≈ 6 px), 32 GB → 64 MB/px (≈ 1.5 px).
        #expect(!folds(100 * Self.mb, totalPhysical: 8 * Self.gb))
        #expect(folds(100 * Self.mb, totalPhysical: 32 * Self.gb))
    }

    @Test("On 256 GB a 1 GB group is too narrow to draw")
    func largeMachineFoldsGigabyteGroup() {
        // 256 GB / 500 px = 512 MB/px, so 1 GB is 2 px — under the 3 px cutoff.
        #expect(folds(1 * Self.gb, totalPhysical: 256 * Self.gb))
        #expect(!folds(4 * Self.gb, totalPhysical: 256 * Self.gb))
    }

    @Test("A wider bar draws groups a narrow one folds")
    func cutoffScalesWithWidth() {
        // 100 MB: 1.6 px across 500, 5 px across 1600.
        #expect(folds(100 * Self.mb, totalPhysical: 32 * Self.gb, barWidth: 500))
        #expect(!folds(100 * Self.mb, totalPhysical: 32 * Self.gb, barWidth: 1600))
    }

    // MARK: - Gaps

    @Test("The cutoff is measured against the width left after gaps")
    func gapsShrinkTheScale() {
        // 140 MB is 2.1 px across the full 500 px — over the 2 px fold line —
        // but 40 segments with 2 px gaps leave about 422 px, where it is 1.8 px.
        let residents = [140 * Self.mb, Self.companion] + Array(repeating: 500 * Self.mb, count: 38)
        let ignoringGaps = fold(residents: residents, totalPhysical: 32 * Self.gb)
        let withGaps = fold(residents: residents, totalPhysical: 32 * Self.gb, gap: 2, extraSegments: 2)
        #expect(!ignoringGaps.contains("g0"))
        #expect(withGaps.contains("g0"))
    }

    // MARK: - Minimum members

    @Test("A lone small group is drawn, not folded into an aggregate of one")
    func loneGroupDoesNotFold() {
        #expect(fold(residents: [8 * Self.gb, 9 * Self.mb], totalPhysical: 32 * Self.gb).isEmpty)
    }

    @Test("When one of two folded groups grows, the other unfolds with it")
    func aggregateDissolvesBelowTwoMembers() {
        let result = fold(
            residents: [400 * Self.mb, 9 * Self.mb],
            totalPhysical: 32 * Self.gb,
            previouslyFolded: ["g0", "g1"]
        )
        #expect(result.isEmpty)
    }

    // MARK: - Hysteresis

    @Test("A drawn group between the two thresholds stays drawn")
    func drawnGroupHoldsInDeadband() {
        // 32 GB / 500 px = 64 MB/px; 160 MB = 2.5 px.
        #expect(!folds(160 * Self.mb, totalPhysical: 32 * Self.gb))
    }

    @Test("A folded group between the two thresholds stays folded")
    func foldedGroupHoldsInDeadband() {
        #expect(folds(160 * Self.mb, totalPhysical: 32 * Self.gb, previouslyFolded: true))
    }

    @Test("A folded group unfolds once it clears the upper threshold")
    func foldedGroupUnfolds() {
        // 200 MB = 3.1 px.
        let result = fold(
            residents: [200 * Self.mb, Self.companion, Self.companion],
            totalPhysical: 32 * Self.gb,
            previouslyFolded: ["g0", "g1", "g2"]
        )
        #expect(result == ["g1", "g2"])
    }

    @Test("Feeding the result back in changes nothing")
    func foldingIsIdempotent() {
        // The view writes the folded set back and recomputes from it, so a
        // second pass must agree with the first or the bar would oscillate.
        // Covers each side of both thresholds (64 MB/px): 1, 2.5, 3.1, 10 px.
        let residents = [64 * Self.mb, 160 * Self.mb, 200 * Self.mb, 640 * Self.mb, Self.companion]
        for previous in [Set<String>(), ["g1"], ["g0", "g1", "g2", "g3", "g4"]] {
            for gap in [0.0, 2.0] {
                let once = fold(residents: residents, totalPhysical: 32 * Self.gb, gap: gap,
                                extraSegments: 2, previouslyFolded: previous)
                let twice = fold(residents: residents, totalPhysical: 32 * Self.gb, gap: gap,
                                 extraSegments: 2, previouslyFolded: once)
                #expect(once == twice, "previous \(previous), gap \(gap)")
            }
        }
    }

    @Test("Folded IDs for groups that have exited are dropped")
    func exitedGroupsDropOut() {
        let result = fold(
            residents: [9 * Self.mb, Self.companion],
            totalPhysical: 32 * Self.gb,
            previouslyFolded: ["gone"]
        )
        #expect(result == ["g0", "g1"])
    }

    // MARK: - Nothing to measure against

    @Test("Nothing folds before total RAM or the bar width is known")
    func unknownScaleFoldsNothing() {
        let residents = [9 * Self.mb, Self.companion]
        #expect(fold(residents: residents, totalPhysical: 0).isEmpty)
        #expect(fold(residents: residents, totalPhysical: 32 * Self.gb, barWidth: 0).isEmpty)
    }
}
