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
    /// - Parameters:
    ///   - ids: Group identifiers, in display order.
    ///   - residents: Resident bytes for each group, same order.
    ///   - totalPhysical: Total physical RAM. `0` before the first system
    ///     snapshot — nothing folds until the scale is known.
    ///   - barWidth: Pixel width of the bar. `0` before it has been measured.
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
        unfoldWidth: Double,
        foldWidth: Double,
        previouslyFolded: Set<String>
    ) -> Set<String> {
        guard totalPhysical > 0, barWidth > 0 else { return [] }
        let pixelsPerByte = barWidth / Double(totalPhysical)

        var folded: Set<String> = []
        for (id, resident) in zip(ids, residents) {
            let width = Double(resident) * pixelsPerByte
            let threshold = previouslyFolded.contains(id) ? unfoldWidth : foldWidth
            if width < threshold {
                folded.insert(id)
            }
        }
        return folded
    }
}
