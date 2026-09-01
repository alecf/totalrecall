import TotalRecallCore
import SwiftUI

/// The hero element: a horizontal stacked bar showing memory occupancy against
/// the machine's total physical RAM. Process groups are sized by resident
/// memory, with an "Other" segment for used memory that is not attributed to a
/// process group and a trailing "Free" segment when available memory has room
/// to render. A readout row beneath the bar reveals the hovered segment's name,
/// size, and share of total RAM.
///
/// The bar splits at a midline. Above it, a fixed-height band every segment
/// fills. Below it, each segment hangs its own stub for the memory that has
/// been compressed or swapped out — deep in proportion to how much of that
/// group is no longer in RAM. Since width is already resident bytes, the stub's
/// area lands on the same scale, so equal areas anywhere in the bar are equal
/// memory. See `RiverLayout.computeDepths`. A left gutter names the two halves
/// so the split reads without hovering anything.
struct MemoryRiverView: View {
    let groups: [ProcessGroup]
    let systemMemory: SystemMemoryInfo
    @Binding var hoveredGroupID: String?
    @Binding var selectedGroupID: String?

    /// Depth currently reserved below the midline, snapped to
    /// `Theme.riverDepthQuantum`. Carried across refreshes so the bar's height
    /// only moves when the deepest stub crosses a step, rather than drifting
    /// with every poll and setting the whole window below it breathing.
    @State private var depthStep: CGFloat = 0

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
            HStack(alignment: .top, spacing: Theme.riverAxisLabelGap) {
                axisLabels
                riverBar
            }
            readoutRow
                .padding(.leading, Theme.riverAxisLabelWidth + Theme.riverAxisLabelGap)
        }
    }

    /// Static names for the bar's two halves, in a left gutter. "In RAM"
    /// centers in the fixed upper band; "Compressed" hangs from the midline —
    /// anchored to the midline rather than centered in the stub region, so it
    /// holds still while the reserved depth steps up and down beneath it.
    ///
    /// Each label is drawn in the tone of the half it names, which makes the
    /// gutter double as the color key: the word sits directly against the band
    /// it describes, so nothing has to be matched back to a legend elsewhere.
    /// Both tones sit at OKLab L=0.61 against a near-black ground, so each
    /// clears 5:1 against the window background — brighter than the muted grey
    /// they replaced, not dimmer.
    ///
    /// The wording comes from `Theme.residentLabel` / `Theme.nonResidentLabel`
    /// so the gutter, the key, the detail panel, and the hover readout can
    /// never drift apart.
    private var axisLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            axisLabel(Theme.residentLabel, tone: Theme.memoryResident)
                .frame(height: Theme.riverHeight)
            axisLabel(Theme.nonResidentLabel, tone: Theme.memoryCompressed)
        }
        // No Spacer below "Compressed" to push it up: a Spacer is greedy, and
        // in a column with no height constraint it swells to the height the
        // window proposes, taking the whole river row with it. The column
        // sizes to its two labels and the HStack's .top alignment does the
        // anchoring instead.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: Theme.riverAxisLabelWidth, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private func axisLabel(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(Theme.secondaryFont)
            .foregroundStyle(tone)
            .fixedSize()
    }

    /// Stub depths and the bar's reserved height. Independent of width, so it
    /// is computed outside the `GeometryReader` — the frame height would
    /// otherwise depend on a value only available inside it.
    private var depths: RiverDepths {
        RiverLayout.computeDepths(
            residents: groups.map(\.residentMemory),
            nonResidents: groups.map(\.rawNonResidentMemory),
            bandHeight: Double(Theme.riverHeight),
            depthCap: Double(Theme.riverMaxDepth),
            hiddenFloor: Theme.memoryHiddenFloor,
            currentStep: Double(depthStep),
            quantum: Double(Theme.riverDepthQuantum),
            shrinkDeadband: Double(Theme.riverShrinkDeadband)
        )
    }

    private var riverBar: some View {
        let depths = depths
        let reserved = CGFloat(depths.reserved)

        return GeometryReader { geo in
            let layout = RiverLayout.compute(
                footprints: groups.map(\.residentMemory),
                freeBytes: freeBytes,
                totalPhysical: systemMemory.totalPhysical,
                totalWidth: Double(geo.size.width),
                minSegmentWidth: Double(Theme.riverMinSegmentWidth),
                gap: Double(Theme.riverSegmentGap)
            )
            HStack(alignment: .top, spacing: Theme.riverSegmentGap) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    segmentView(
                        for: group,
                        width: CGFloat(layout.processWidths[index]),
                        depth: CGFloat(depths.depths[index]),
                        isClipped: depths.clipped[index]
                    )
                }
                if layout.otherWidth > 0 {
                    otherSegmentView(width: CGFloat(layout.otherWidth))
                }
                if layout.freeWidth > 0 {
                    freeSegmentView(width: CGFloat(layout.freeWidth))
                }
            }
        }
        .frame(height: reserved)
        // Top corners only: the lower edge is ragged by design, and a bottom
        // radius would clip the deepest stubs.
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.riverCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Theme.riverCornerRadius
            )
        )
        .animation(.spring(duration: 0.4, bounce: 0.2), value: reserved)
        .onChange(of: reserved, initial: true) {
            depthStep = reserved - Theme.riverHeight
        }
    }

    /// A single line beneath the bar, shared by the key and the hover readout.
    ///
    /// Idle, it carries `MemoryKeyView` — so the two colors are explained on
    /// screen at all times rather than only to whoever thinks to hover. Hover a
    /// segment and the readout takes the line over, answering the same question
    /// with that segment's own numbers ("… 3.1 GB in RAM … · 1.2 GB
    /// compressed"). The two are stacked in a `ZStack` and cross-faded rather
    /// than swapped, so the row's height is the taller of the two at all times
    /// and the whole window below it never jumps.
    private var readoutRow: some View {
        ZStack(alignment: .leading) {
            MemoryKeyView()
                .opacity(hoverReadout.isEmpty ? 1 : 0)
            Text(hoverReadout.isEmpty ? " " : hoverReadout)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(hoverReadout.isEmpty ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.1), value: hoverReadout)
    }

    /// One column: the group's slice of the fixed upper band, with its own stub
    /// hanging below the midline. Built as a column rather than as two stacked
    /// bands so hover, tap, hit region, and accessibility label each cover a top
    /// and its own stub as a single unit.
    private func segmentView(
        for group: ProcessGroup,
        width segmentWidth: CGFloat,
        depth: CGFloat,
        isClipped: Bool
    ) -> some View {
        let isHovered = hoveredGroupID == group.id
        let residentTone = isHovered ? Theme.brighten(Theme.memoryResident) : Theme.memoryResident
        let hiddenTone = isHovered ? Theme.brighten(Theme.memoryCompressed) : Theme.memoryCompressed
        let readout = readoutText(for: group)

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(residentTone)
                    .frame(height: Theme.riverHeight)
                    .clipShape(topPieceShape(hasStub: depth > 0))
                    .overlay(
                        Text(labelText(for: group))
                            .font(Theme.riverLabelFont)
                            // Both tones sit at the same lightness, so one
                            // choice reads against either.
                            .foregroundStyle(Theme.legibleTextColor(on: residentTone))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(segmentWidth >= Theme.riverLabelMinSegmentWidth ? 1 : 0)
                            .allowsHitTesting(false)
                    )
                stubView(tone: hiddenTone, depth: depth, isClipped: isClipped)
            }
            // Hit region stops at the stub's end, so hover isn't triggered by
            // the empty space a shallower segment leaves below it.
            .contentShape(Rectangle())
            .onHover { hovering in
                updateHover(toID: group.id, hovering: hovering)
            }
            .onTapGesture {
                selectedGroupID = group.id
            }
            Spacer(minLength: 0)
        }
        .frame(width: segmentWidth)
        .accessibilityLabel(readout)
        .animation(.spring(duration: 0.4, bounce: 0.2), value: segmentWidth)
    }

    /// The compressed/swapped stub. A stub pinned at the cap fades out over its
    /// last few pixels — the broken-axis convention, saying "continues past
    /// here". The fade is an alpha ramp on one hue, never a blend toward
    /// `memoryResident`: those two are near-complementary and every path
    /// between them muddies through grey.
    @ViewBuilder
    private func stubView(tone: Color, depth: CGFloat, isClipped: Bool) -> some View {
        if depth > 0 {
            Rectangle()
                .fill(tone)
                .frame(height: depth)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 2,
                        bottomTrailingRadius: 2,
                        topTrailingRadius: 0
                    )
                )
                .mask(clipFade(isClipped: isClipped, depth: depth))
                .animation(.spring(duration: 0.4, bounce: 0.2), value: depth)
        }
    }

    @ViewBuilder
    private func clipFade(isClipped: Bool, depth: CGFloat) -> some View {
        if isClipped {
            let solid = max(0, 1 - min(1, Theme.riverClipFadeHeight / depth))
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: solid),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
        }
    }

    /// Square off the bottom corners once a stub continues below, so the two
    /// pieces read as one column rather than a band with a detached tail.
    private func topPieceShape(hasStub: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 2,
            bottomLeadingRadius: hasStub ? 0 : 2,
            bottomTrailingRadius: hasStub ? 0 : 2,
            topTrailingRadius: 2
        )
    }

    private func freeSegmentView(width freeWidth: CGFloat) -> some View {
        let freeLabel = "Free \(MemoryFormatter.format(bytes: freeBytes))"
        let readout = freeReadoutText

        // Upper band only — free RAM has nothing swapped out of it.
        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.riverFree)
            .frame(width: freeWidth, height: Theme.riverHeight)
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

        // Upper band only — unattributed memory carries no per-group swap data.
        return RoundedRectangle(cornerRadius: 2)
            .fill(Theme.riverOther)
            .frame(width: otherWidth, height: Theme.riverHeight)
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
