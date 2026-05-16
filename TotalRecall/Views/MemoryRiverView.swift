import TotalRecallCore
import SwiftUI

/// The hero element: a horizontal stacked bar showing memory occupancy against
/// the machine's total physical RAM. The trailing "Free" segment matches the
/// summary's available figure; the remaining width is divided among process
/// groups proportional to their footprints.
struct MemoryRiverView: View {
    let groups: [ProcessGroup]
    let systemMemory: SystemMemoryInfo
    @Binding var hoveredGroupID: String?
    @Binding var selectedGroupID: String?

    private var totalGroupFootprint: UInt64 {
        groups.reduce(0) { $0 + $1.deduplicatedFootprint }
    }

    /// Bytes shown as free at the right end of the bar. Mirrors
    /// `systemMemory.available` so it matches the summary stats below.
    private var freeBytes: UInt64 {
        min(systemMemory.totalPhysical, systemMemory.available)
    }

    /// Bytes the process segments collectively occupy. The remainder of total
    /// physical RAM after subtracting `freeBytes`.
    private var usedBytes: UInt64 {
        guard systemMemory.totalPhysical > 0 else { return 0 }
        return systemMemory.totalPhysical &- freeBytes
    }

    /// Fraction of the bar's width that the used region occupies. Process
    /// groups are sized proportionally inside this fraction so the bar's
    /// process portion totals exactly `usedBytes / totalPhysical`.
    private var usedFraction: CGFloat {
        guard systemMemory.totalPhysical > 0 else { return 1 }
        return CGFloat(usedBytes) / CGFloat(systemMemory.totalPhysical)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: Theme.riverSegmentGap) {
                ForEach(groups) { group in
                    let fraction = segmentFraction(for: group, totalWidth: geo.size.width)
                    let isHovered = hoveredGroupID == group.id
                    let accentColor = Theme.accentColor(for: group.classifierName)
                    let displayedColor = isHovered ? Theme.brighten(accentColor) : accentColor
                    let segmentWidth = max(Theme.riverMinSegmentWidth, fraction * geo.size.width)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(displayedColor)
                        .frame(width: segmentWidth)
                        .overlay(
                            Text(labelText(for: group))
                                .font(Theme.riverLabelFont)
                                .foregroundStyle(Theme.legibleTextColor(on: displayedColor))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(segmentWidth >= Theme.riverLabelMinSegmentWidth ? 1 : 0)
                                .allowsHitTesting(false)
                        )
                        .onHover { hovering in
                            hoveredGroupID = hovering ? group.id : nil
                        }
                        .onTapGesture {
                            selectedGroupID = group.id
                        }
                        .help(tooltip(for: group))
                        .accessibilityLabel(tooltip(for: group))
                        .animation(.spring(duration: 0.4, bounce: 0.2), value: fraction)
                }

                if freeBytes > 0 {
                    let freeFraction = 1 - usedFraction
                    let freeWidth = max(Theme.riverMinSegmentWidth, freeFraction * geo.size.width)
                    let freeLabel = "Free \(MemoryFormatter.format(bytes: freeBytes))"
                    let freeTooltip = freeTooltipText

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.riverFree)
                        .frame(width: freeWidth)
                        .overlay(
                            Text(freeLabel)
                                .font(Theme.riverLabelFont)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(freeWidth >= Theme.riverLabelMinSegmentWidth ? 1 : 0)
                                .allowsHitTesting(false)
                        )
                        .help(freeTooltip)
                        .accessibilityLabel(freeTooltip)
                        .animation(.spring(duration: 0.4, bounce: 0.2), value: freeFraction)
                }
            }
        }
        .frame(height: Theme.riverHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.riverCornerRadius))
    }

    /// Match the table's "Name (N)" format for grouped apps (e.g. "Claude Code (9)").
    private func labelText(for group: ProcessGroup) -> String {
        if let subGroups = group.subGroups, !subGroups.isEmpty {
            return "\(group.name) (\(subGroups.count))"
        }
        return group.name
    }

    /// "Chrome — 3.1 GB (9.7% of total)" or, when the process count is meaningful,
    /// "Chrome (34 processes) — 3.1 GB (9.7% of total)". Percentage is omitted when
    /// total physical RAM isn't known yet so the tooltip never says "0% of total".
    private func tooltip(for group: ProcessGroup) -> String {
        let size = MemoryFormatter.format(bytes: group.deduplicatedFootprint)
        let countSuffix: String
        if let subGroups = group.subGroups, !subGroups.isEmpty {
            countSuffix = " (\(subGroups.count) processes)"
        } else if group.processes.count > 1 {
            countSuffix = " (\(group.processes.count) processes)"
        } else {
            countSuffix = ""
        }
        guard let percent = percentOfTotal(group.deduplicatedFootprint) else {
            return "\(group.name)\(countSuffix) — \(size)"
        }
        return "\(group.name)\(countSuffix) — \(size) (\(percent) of total)"
    }

    private var freeTooltipText: String {
        let size = MemoryFormatter.format(bytes: freeBytes)
        guard let percent = percentOfTotal(freeBytes) else {
            return "Free — \(size)"
        }
        return "Free — \(size) (\(percent) of total)"
    }

    private func percentOfTotal(_ bytes: UInt64) -> String? {
        guard systemMemory.totalPhysical > 0 else { return nil }
        let fraction = Double(bytes) / Double(systemMemory.totalPhysical) * 100
        return String(format: "%.1f%%", fraction)
    }

    /// Each group's bar fraction is its share of the group total, scaled into the
    /// `usedFraction` slice of the bar. Falls back to the share-of-groups model
    /// before `systemMemory` arrives so the bar still renders during the first
    /// snapshot.
    private func segmentFraction(for group: ProcessGroup, totalWidth: CGFloat) -> CGFloat {
        guard totalGroupFootprint > 0 else { return 0 }
        let shareOfGroups = CGFloat(group.deduplicatedFootprint) / CGFloat(totalGroupFootprint)
        let scale = systemMemory.totalPhysical > 0 ? usedFraction : 1
        let rawFraction = shareOfGroups * scale
        let minFraction = Theme.riverMinSegmentWidth / totalWidth
        return max(minFraction, rawFraction)
    }
}
