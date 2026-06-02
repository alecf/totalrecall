import Foundation

/// Pixel widths for the Memory River bar's segments, computed so they always
/// fit within the available width.
///
/// The bar lays process group segments left-to-right followed by a trailing
/// "Free" segment. Because each process segment has a minimum width for
/// visibility, a machine with many groups would, under naive proportional
/// sizing, produce segments whose minimum widths sum past the bar's width —
/// pushing the trailing free segment off the right edge where it is clipped
/// away. To prevent that, the free region is reserved its proportional share
/// of total physical RAM *first*, and the process groups are fitted into the
/// remaining budget (scaled down uniformly when their minimum widths don't
/// fit). The free segment therefore stays visible no matter how many process
/// groups exist.
public struct RiverLayout: Equatable {
    /// Width of each process group segment, in the order footprints were given.
    public let processWidths: [Double]
    /// Width of the trailing free segment; `0` when no free region is shown.
    public let freeWidth: Double

    public init(processWidths: [Double], freeWidth: Double) {
        self.processWidths = processWidths
        self.freeWidth = freeWidth
    }

    /// - Parameters:
    ///   - footprints: Per-group memory footprints, in display order.
    ///   - freeBytes: Bytes to render as the trailing free segment.
    ///   - totalPhysical: Total physical RAM. `0` before the first system
    ///     snapshot arrives — in that case the free segment is suppressed and
    ///     process groups fill the full width by share.
    ///   - totalWidth: Total pixel width available for the bar.
    ///   - minSegmentWidth: Minimum width a process segment prefers, abandoned
    ///     (scaled below) only when groups can't otherwise fit.
    ///   - gap: Pixel gap rendered between adjacent segments.
    public static func compute(
        footprints: [UInt64],
        freeBytes: UInt64,
        totalPhysical: UInt64,
        totalWidth: Double,
        minSegmentWidth: Double,
        gap: Double
    ) -> RiverLayout {
        guard totalWidth > 0, !footprints.isEmpty else {
            return RiverLayout(processWidths: footprints.map { _ in 0 }, freeWidth: 0)
        }

        let showFree = freeBytes > 0 && totalPhysical > 0
        let segmentCount = footprints.count + (showFree ? 1 : 0)
        let gapsTotal = Double(max(0, segmentCount - 1)) * gap
        let content = max(0, totalWidth - gapsTotal)

        // Reserve the free segment's true proportional share up front so it is
        // never squeezed out by the process segments' minimum widths.
        let freeWidth: Double
        if showFree {
            let freeFraction = min(1, Double(freeBytes) / Double(totalPhysical))
            freeWidth = min(content, freeFraction * content)
        } else {
            freeWidth = 0
        }

        let processBudget = max(0, content - freeWidth)
        let totalFootprint = footprints.reduce(0.0) { $0 + Double($1) }

        // Ideal proportional widths within the process budget.
        var widths: [Double] = footprints.map { footprint in
            let share = totalFootprint > 0
                ? Double(footprint) / totalFootprint
                : 1 / Double(footprints.count)
            return share * processBudget
        }

        // Prefer the minimum width for visibility...
        widths = widths.map { max(minSegmentWidth, $0) }

        // ...but if the minimums overflow the budget (too many groups to all
        // fit at min width), scale every process segment down uniformly so the
        // process portion fits exactly. The free segment is untouched.
        let widthsTotal = widths.reduce(0, +)
        if widthsTotal > processBudget, widthsTotal > 0 {
            let scale = processBudget / widthsTotal
            widths = widths.map { $0 * scale }
        }

        return RiverLayout(processWidths: widths, freeWidth: freeWidth)
    }
}
