import Testing
@testable import TotalRecallCore

@Suite("Memory River Folding")
struct RiverFoldingTests {
    static let gb: UInt64 = 1_073_741_824
    static let mb: UInt64 = 1_048_576

    func fold(
        residents: [UInt64],
        totalPhysical: UInt64,
        barWidth: Double = 500,
        previouslyFolded: Set<String> = []
    ) -> Set<String> {
        RiverFolding.foldedIDs(
            ids: residents.indices.map { "g\($0)" },
            residents: residents,
            totalPhysical: totalPhysical,
            barWidth: barWidth,
            unfoldWidth: 3,
            foldWidth: 2,
            previouslyFolded: previouslyFolded
        )
    }

    // MARK: - The cutoff scales with RAM, not a fixed byte count

    @Test("A 9 MB group folds on 32 GB")
    func smallGroupFoldsOn32GB() {
        #expect(fold(residents: [8 * Self.gb, 9 * Self.mb], totalPhysical: 32 * Self.gb) == ["g1"])
    }

    @Test("The same 100 MB group is drawn on 8 GB but folded on 32 GB")
    func cutoffScalesWithRAM() {
        // 500 px: 8 GB → 16 MB/px (100 MB ≈ 6 px), 32 GB → 64 MB/px (≈ 1.5 px).
        #expect(fold(residents: [100 * Self.mb], totalPhysical: 8 * Self.gb).isEmpty)
        #expect(fold(residents: [100 * Self.mb], totalPhysical: 32 * Self.gb) == ["g0"])
    }

    @Test("On 256 GB a 1 GB group is too narrow to draw")
    func largeMachineFoldsGigabyteGroup() {
        // 256 GB / 500 px = 512 MB/px, so 1 GB is 2 px — under the 3 px cutoff.
        #expect(fold(residents: [1 * Self.gb], totalPhysical: 256 * Self.gb) == ["g0"])
        #expect(fold(residents: [4 * Self.gb], totalPhysical: 256 * Self.gb).isEmpty)
    }

    @Test("A wider bar draws groups a narrow one folds")
    func cutoffScalesWithWidth() {
        // 100 MB: 1.6 px across 500, 5 px across 1600.
        let residents = [100 * Self.mb]
        #expect(fold(residents: residents, totalPhysical: 32 * Self.gb, barWidth: 500) == ["g0"])
        #expect(fold(residents: residents, totalPhysical: 32 * Self.gb, barWidth: 1600).isEmpty)
    }

    // MARK: - Hysteresis

    @Test("A drawn group between the two thresholds stays drawn")
    func drawnGroupHoldsInDeadband() {
        // 32 GB / 500 px = 64 MB/px; 160 MB = 2.5 px.
        #expect(fold(residents: [160 * Self.mb], totalPhysical: 32 * Self.gb).isEmpty)
    }

    @Test("A folded group between the two thresholds stays folded")
    func foldedGroupHoldsInDeadband() {
        let result = fold(residents: [160 * Self.mb], totalPhysical: 32 * Self.gb, previouslyFolded: ["g0"])
        #expect(result == ["g0"])
    }

    @Test("A folded group unfolds once it clears the upper threshold")
    func foldedGroupUnfolds() {
        // 200 MB = 3.1 px.
        let result = fold(residents: [200 * Self.mb], totalPhysical: 32 * Self.gb, previouslyFolded: ["g0"])
        #expect(result.isEmpty)
    }

    @Test("Feeding the result back in changes nothing")
    func foldingIsIdempotent() {
        // The view writes the folded set back and recomputes from it, so a
        // second pass must agree with the first or the bar would oscillate.
        // Covers each side of both thresholds (64 MB/px): 1, 2.5, 3.1, 10 px.
        let residents = [64 * Self.mb, 160 * Self.mb, 200 * Self.mb, 640 * Self.mb]
        for previous in [Set<String>(), ["g1"], ["g0", "g1", "g2", "g3"]] {
            let once = fold(residents: residents, totalPhysical: 32 * Self.gb, previouslyFolded: previous)
            let twice = fold(residents: residents, totalPhysical: 32 * Self.gb, previouslyFolded: once)
            #expect(once == twice, "previous \(previous)")
        }
    }

    @Test("Folded IDs for groups that have exited are dropped")
    func exitedGroupsDropOut() {
        let result = fold(residents: [9 * Self.mb], totalPhysical: 32 * Self.gb, previouslyFolded: ["gone"])
        #expect(result == ["g0"])
    }

    // MARK: - Nothing to measure against

    @Test("Nothing folds before total RAM or the bar width is known")
    func unknownScaleFoldsNothing() {
        #expect(fold(residents: [9 * Self.mb], totalPhysical: 0).isEmpty)
        #expect(fold(residents: [9 * Self.mb], totalPhysical: 32 * Self.gb, barWidth: 0).isEmpty)
    }
}
