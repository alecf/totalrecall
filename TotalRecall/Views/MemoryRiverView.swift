import TotalRecallCore
import SwiftUI

/// The hero element: a horizontal stacked bar showing memory occupancy against
/// the machine's total physical RAM. Process groups are sized by resident
/// memory, with an "Other" segment for used memory that is not attributed to a
/// process group and a trailing "Free" segment when available memory has room
/// to render. A readout row beneath the bar reveals the hovered segment's name,
/// size, and share of total RAM.
struct MemoryRiverView: View {
    let groups: [ProcessGroup]
    let systemMemory: SystemMemoryInfo
    @Binding var hoveredGroupID: String?
    @Binding var selectedGroupID: String?

    /// Synthetic ID used in `hoveredGroupID` to represent the Free segment.
    /// No real group will ever have this ID, so cross-view highlighting (group
    /// list rows checking `hoveredGroupID == group.id`) is unaffected.
    private static let freeRegionID = "__memory_river_free__"
    private static let otherRegionID = "__memory_river_other__"

    /// Bytes shown as free at the right end of the bar. Mirrors
    /// `systemMemory.available` so it matches the summary stats below.
    private var freeBytes: UInt64 {
        min(systemMemory.totalPhysical, systemMemory.available)
    }

    /// Resolves the currently hovered region to a readout string. Returns the
    /// empty string when nothing in the river is hovered.
    private var hoverReadout: String {
        guard let id = hoveredGroupID else { return "" }
        if id == Self.freeRegionID { return freeReadoutText }
        if id == Self.otherRegionID { return otherReadoutText }
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
            let layout = RiverLayout.compute(
                footprints: groups.map(\.residentMemory),
                freeBytes: freeBytes,
                totalPhysical: systemMemory.totalPhysical,
                totalWidth: Double(geo.size.width),
                minSegmentWidth: Double(Theme.riverMinSegmentWidth),
                gap: Double(Theme.riverSegmentGap)
            )
            HStack(spacing: Theme.riverSegmentGap) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    segmentView(for: group, width: CGFloat(layout.processWidths[index]))
                }
                if layout.otherWidth > 0 {
                    otherSegmentView(width: CGFloat(layout.otherWidth))
                }
                if layout.freeWidth > 0 {
                    freeSegmentView(width: CGFloat(layout.freeWidth))
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

    private func segmentView(for group: ProcessGroup, width segmentWidth: CGFloat) -> some View {
        let isHovered = hoveredGroupID == group.id
        let residentTone = isHovered ? Theme.brighten(Theme.memoryResident) : Theme.memoryResident
        let hiddenTone = isHovered ? Theme.brighten(Theme.memoryCompressed) : Theme.memoryCompressed
        // Width is resident bytes, so the compressed/swapped tail has nowhere
        // to go horizontally without breaking the bar's scale. It rises up the
        // segment instead: the band reads as an app partly submerged out of RAM.
        let hiddenHeight = Theme.riverHeight * CGFloat(Theme.hiddenFraction(for: group))
        let readout = readoutText(for: group)

        return Rectangle()
            .fill(residentTone)
            .frame(width: segmentWidth)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(hiddenTone)
                    .frame(height: hiddenHeight)
                    .animation(.spring(duration: 0.4, bounce: 0.2), value: hiddenHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                Text(labelText(for: group))
                    .font(Theme.riverLabelFont)
                    // Both tones sit at the same lightness, so one choice stays
                    // legible whether the fill has risen past the label or not.
                    .foregroundStyle(Theme.legibleTextColor(on: residentTone))
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
            .animation(.spring(duration: 0.4, bounce: 0.2), value: segmentWidth)
    }

    private func freeSegmentView(width freeWidth: CGFloat) -> some View {
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
            .animation(.spring(duration: 0.4, bounce: 0.2), value: freeWidth)
    }

    private func otherSegmentView(width otherWidth: CGFloat) -> some View {
        let otherLabel = "Other \(MemoryFormatter.format(bytes: otherBytes))"
        let readout = otherReadoutText

        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.riverOther)
            .frame(width: otherWidth)
            .overlay(
                Text(otherLabel)
                    .font(Theme.riverLabelFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(otherWidth >= Theme.riverLabelMinSegmentWidth ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                updateHover(toID: Self.otherRegionID, hovering: hovering)
            }
            .accessibilityLabel(readout)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: otherWidth)
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

    /// "Chrome — 3.1 GB in RAM (9.7% of total)" or, when the process count is meaningful,
    /// "Chrome (34 processes) — 3.1 GB in RAM (9.7% of total)". Percentage is omitted when
    /// total physical RAM isn't known yet so the readout never says "0% of total".
    ///
    /// A trailing "· 1.2 GB compressed" appears whenever the group holds
    /// non-resident memory. That figure is what drives how far the amber fill
    /// rises up the segment, so hovering a mostly-amber band explains why it is
    /// amber — the encoding teaches itself instead of needing a legend.
    private func readoutText(for group: ProcessGroup) -> String {
        let resident = group.residentMemory
        let size = MemoryFormatter.format(bytes: resident)
        let countSuffix: String
        if group.processCount > 1 {
            countSuffix = " (\(group.processCount) processes)"
        } else {
            countSuffix = ""
        }
        let hiddenSuffix: String
        if group.rawNonResidentMemory > 0 {
            let hidden = MemoryFormatter.format(bytes: group.rawNonResidentMemory)
            hiddenSuffix = " · \(hidden) compressed"
        } else {
            hiddenSuffix = ""
        }
        guard let percent = percentOfTotal(resident) else {
            return "\(group.name)\(countSuffix) — \(size) in RAM\(hiddenSuffix)"
        }
        return "\(group.name)\(countSuffix) — \(size) in RAM (\(percent) of total)\(hiddenSuffix)"
    }

    private var freeReadoutText: String {
        let size = MemoryFormatter.format(bytes: freeBytes)
        guard let percent = percentOfTotal(freeBytes) else {
            return "Free — \(size)"
        }
        return "Free — \(size) (\(percent) of total)"
    }

    private var otherReadoutText: String {
        let size = MemoryFormatter.format(bytes: otherBytes)
        guard let percent = percentOfTotal(otherBytes) else {
            return "Other — \(size)"
        }
        return "Other — \(size) (\(percent) of total)"
    }

    private var otherBytes: UInt64 {
        guard systemMemory.totalPhysical > 0 else { return 0 }
        let attributed = groups.reduce(UInt64(0)) { partial, group in
            partial.addingReportingOverflow(group.residentMemory).overflow
                ? UInt64.max
                : partial + group.residentMemory
        }
        guard attributed < systemMemory.totalPhysical else { return 0 }
        let remaining = systemMemory.totalPhysical - attributed
        return remaining > freeBytes ? remaining - freeBytes : 0
    }

    private func percentOfTotal(_ bytes: UInt64) -> String? {
        guard systemMemory.totalPhysical > 0 else { return nil }
        let fraction = Double(bytes) / Double(systemMemory.totalPhysical) * 100
        return String(format: "%.1f%%", fraction)
    }
}
