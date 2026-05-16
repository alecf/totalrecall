import TotalRecallCore
import SwiftUI

/// The hero element: a horizontal stacked bar showing memory occupancy against
/// the machine's total physical RAM. The trailing "Free" segment matches the
/// summary's available figure; the remaining width is divided among process
/// groups proportional to their footprints. A readout row beneath the bar
/// reveals the hovered segment's name, size, and share of total RAM.
struct MemoryRiverView: View {
    let groups: [ProcessGroup]
    let systemMemory: SystemMemoryInfo
    @Binding var hoveredGroupID: String?
    @Binding var selectedGroupID: String?

    /// Synthetic ID used in `hoveredGroupID` to represent the Free segment.
    /// No real group will ever have this ID, so cross-view highlighting (group
    /// list rows checking `hoveredGroupID == group.id`) is unaffected.
    private static let freeRegionID = "__memory_river_free__"

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

    /// Resolves the currently hovered region to a readout string. Returns the
    /// empty string when nothing in the river is hovered.
    private var hoverReadout: String {
        guard let id = hoveredGroupID else { return "" }
        if id == Self.freeRegionID { return freeReadoutText }
        if let group = groups.first(where: { $0.id == id }) {
            return readoutText(for: group)
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            riverBar
            readoutRow
        }
    }

    private var riverBar: some View {
        GeometryReader { geo in
            HStack(spacing: Theme.riverSegmentGap) {
                ForEach(groups) { group in
                    segmentView(for: group, in: geo)
                }
                if freeBytes > 0 {
                    freeSegmentView(in: geo)
                }
            }
        }
        .frame(height: Theme.riverHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.riverCornerRadius))
    }

    /// Reserves a single line of height beneath the bar; opacity toggles so the
    /// layout never jumps as the readout appears or vanishes.
    private var readoutRow: some View {
        Text(hoverReadout.isEmpty ? " " : hoverReadout)
            .font(Theme.secondaryFont)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hoverReadout.isEmpty ? 0 : 1)
            .animation(.easeInOut(duration: 0.1), value: hoverReadout)
    }

    private func segmentView(for group: ProcessGroup, in geo: GeometryProxy) -> some View {
        let fraction = segmentFraction(for: group, totalWidth: geo.size.width)
        let isHovered = hoveredGroupID == group.id
        let accentColor = Theme.accentColor(for: group.classifierName)
        let displayedColor = isHovered ? Theme.brighten(accentColor) : accentColor
        let segmentWidth = max(Theme.riverMinSegmentWidth, fraction * geo.size.width)
        let readout = readoutText(for: group)

        return RoundedRectangle(cornerRadius: 2)
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
            .contentShape(Rectangle())
            .onHover { hovering in
                updateHover(toID: group.id, hovering: hovering)
            }
            .onTapGesture {
                selectedGroupID = group.id
            }
            .accessibilityLabel(readout)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: fraction)
    }

    private func freeSegmentView(in geo: GeometryProxy) -> some View {
        let freeFraction = 1 - usedFraction
        let freeWidth = max(Theme.riverMinSegmentWidth, freeFraction * geo.size.width)
        let freeLabel = "Free \(MemoryFormatter.format(bytes: freeBytes))"
        let readout = freeReadoutText

        return RoundedRectangle(cornerRadius: 2)
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
            .contentShape(Rectangle())
            .onHover { hovering in
                updateHover(toID: Self.freeRegionID, hovering: hovering)
            }
            .accessibilityLabel(readout)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: freeFraction)
    }

    /// Set or clear `hoveredGroupID` without clobbering a hover that has already
    /// transferred to an adjacent segment. SwiftUI fires `onHover(true)` on the
    /// new segment before `onHover(false)` on the old one, so the leaving
    /// segment must only clear the binding if it still owns it.
    private func updateHover(toID id: String, hovering: Bool) {
        if hovering {
            hoveredGroupID = id
        } else if hoveredGroupID == id {
            hoveredGroupID = nil
        }
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
    /// total physical RAM isn't known yet so the readout never says "0% of total".
    private func readoutText(for group: ProcessGroup) -> String {
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

    private var freeReadoutText: String {
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
