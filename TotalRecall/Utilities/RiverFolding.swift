import Foundation

/// Decides which groups are too small to draw to scale in the Memory River.
///
/// Every segment has a minimum width so it stays hoverable, but a group whose
/// resident memory works out to a fraction of a pixel would be inflated many
/// times over to reach it — and on a busy machine dozens of those slivers
/// crowd out the Free segment entirely. Groups below the cutoff are folded
/// into one "small groups" segment instead, so everything left in the bar is
/// drawn at its true width.
///
/// The cutoff is in pixels, not bytes: the bar maps `totalPhysical` onto
/// `barWidth`, so a group is drawable when its share of that width reaches the
/// minimum segment width. The same 100 MB group is 6 px on an 8 GB machine
/// and 1.5 px on a 32 GB one, and only the latter is folded — no byte count
/// tuned on one machine size has to hold for every other.
public enum RiverFolding {
    /// Fewer members than this and nothing folds: an aggregate of one group is
    /// the same inflated sliver it replaced, minus the group's name.
    public static let minimumMembers = 2

    /// - Parameters:
    ///   - ids: Group identifiers, in display order.
    ///   - residents: Resident bytes for each group, same order.
    ///   - totalPhysical: Total physical RAM. `0` before the first system
    ///     snapshot — nothing folds until the scale is known.
    ///   - barWidth: Pixel width of the bar. `0` before it has been measured.
    ///   - gap: Gap between adjacent segments. `RiverLayout` scales bytes onto
    ///     the width left after gaps, so the cutoff has to as well — measured
    ///     against the full width, a group that passes can still land under
    ///     the minimum and get inflated.
    ///   - extraSegments: Segments drawn besides the groups (Other, Free),
    ///     counted for their gaps.
    ///   - unfoldWidth: A folded group is drawn again once its to-scale width
    ///     reaches this.
    ///   - foldWidth: A drawn group folds once its to-scale width falls below
    ///     this. Lower than `unfoldWidth`, so a group sitting at the boundary
    ///     can't hop in and out of the bar on every refresh.
    ///   - previouslyFolded: The set returned last time, for hysteresis.
    /// - Returns: IDs of the groups to fold.
    public static func foldedIDs(
        ids: [String],
        residents: [UInt64],
        totalPhysical: UInt64,
        barWidth: Double,
        gap: Double = 0,
        extraSegments: Int = 0,
        unfoldWidth: Double,
        foldWidth: Double,
        previouslyFolded: Set<String>
    ) -> Set<String> {
        guard totalPhysical > 0, barWidth > 0 else { return [] }

        // The gap total depends on how many segments survive, which depends on
        // the gap total. Iterate from the previous set to a fixed point so the
        // set returned is consistent with the width it was judged against.
        var current = previouslyFolded.intersection(ids)
        for _ in 0..<4 {
            let segmentCount = ids.count - current.count + (current.isEmpty ? 0 : 1) + extraSegments
            let content = max(0, barWidth - Double(max(0, segmentCount - 1)) * gap)
            let pixelsPerByte = content / Double(totalPhysical)

            var next: Set<String> = []
            for (id, resident) in zip(ids, residents) {
                let width = Double(resident) * pixelsPerByte
                let threshold = current.contains(id) ? unfoldWidth : foldWidth
                if width < threshold {
                    next.insert(id)
                }
            }
            if next.count < minimumMembers { next = [] }
            if next == current { break }
            current = next
        }
        return current
    }
}
