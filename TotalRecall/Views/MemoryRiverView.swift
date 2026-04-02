import TotalRecallCore
import SwiftUI

/// The hero element: a horizontal stacked bar showing memory proportions per group.
/// Built as an HStack of Rectangles for per-segment hover, click, and accessibility.
struct MemoryRiverView: View {
    let groups: [ProcessGroup]
    @Binding var hoveredGroupID: String?
    @Binding var selectedGroupID: String?

    /// Use the sum of group footprints as the denominator so segments always fill exactly 100%.
    private var totalGroupFootprint: UInt64 {
        groups.reduce(0) { $0 + $1.deduplicatedFootprint }
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: Theme.riverSegmentGap) {
                ForEach(groups) { group in
                    let fraction = segmentFraction(for: group, totalWidth: geo.size.width)
                    let isHovered = hoveredGroupID == group.id
                    let accentColor = Theme.accentColor(for: group.classifierName)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(isHovered ? Theme.brighten(accentColor) : accentColor)
                        .frame(width: max(Theme.riverMinSegmentWidth, fraction * geo.size.width))
                        .onHover { hovering in
                            hoveredGroupID = hovering ? group.id : nil
                        }
                        .onTapGesture {
                            selectedGroupID = group.id
                        }
                        .help("\(group.name): \(MemoryFormatter.format(bytes: group.deduplicatedFootprint))")
                        .accessibilityLabel("\(group.name), \(MemoryFormatter.format(bytes: group.deduplicatedFootprint))")
                        .animation(.spring(duration: 0.4, bounce: 0.2), value: fraction)
                }
            }
        }
        .frame(height: Theme.riverHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.riverCornerRadius))
    }

    private func segmentFraction(for group: ProcessGroup, totalWidth: CGFloat) -> CGFloat {
        guard totalGroupFootprint > 0 else { return 0 }
        let rawFraction = CGFloat(group.deduplicatedFootprint) / CGFloat(totalGroupFootprint)
        let minFraction = Theme.riverMinSegmentWidth / totalWidth
        return max(minFraction, rawFraction)
    }
}
