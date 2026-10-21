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
///
/// Groups too narrow to draw to scale fold into a single "small groups"
/// segment after the last drawn group (see `RiverFolding`). Only the river
/// folds — the group list keeps a row for every group, and hovering the
/// segment highlights all of its members there.
struct MemoryRiverView: View {
    let groups: [ProcessGroup]
    let systemMemory: SystemMemoryInfo
    @Binding var hoveredGroupID: String?
    @Binding var selectedGroupID: String?
    /// Groups the list should highlight because the small-groups segment is
    /// hovered — its members, or empty. Only written when that changes, so
    /// folding during a window resize doesn't rebuild the list.
    @Binding var highlightedGroupIDs: Set<String>

    /// The folded set from the previous pass, fed back into `RiverFolding`
    /// for hysteresis.
    @State private var foldedGroupIDs: Set<String> = []

    /// Depth currently reserved below the midline, snapped to
    /// `Theme.riverDepthQuantum`. Carried across refreshes so the bar's height
    /// only moves when the deepest stub crosses a step, rather than drifting
    /// with every poll and setting the whole window below it breathing.
    @State private var depthStep: CGFloat = 0

    /// Measured width of the bar. Folding needs it, and so does the reserved
    /// height (the small-groups stub can be the deepest), which is computed
    /// outside the `GeometryReader`. `0` until the first layout pass; the bar
    /// draws no segments until then rather than flashing them unfolded.
    @State private var barWidth: CGFloat = 0

    /// Synthetic ID used in `hoveredGroupID` to represent the Free segment.
    /// No real group will ever have this ID, so cross-view highlighting (group
    /// list rows checking `hoveredGroupID == group.id`) is unaffected.
    private static let freeRegionID = "__memory_river_free__"
    private static let otherRegionID = "__memory_river_other__"
    /// Synthetic ID for the small-groups segment.
    private static let smallGroupsRegionID = "__memory_river_small_groups__"

    /// Folded set for the current groups and bar width, with the previous set
    /// as hysteresis state.
    private var folded: Set<String> {
        RiverFolding.foldedIDs(
            ids: groups.map(\.id),
            residents: groups.map(\.residentMemory),
            totalPhysical: systemMemory.totalPhysical,
            barWidth: Double(barWidth),
            gap: Double(Theme.riverSegmentGap),
            // Other and Free. Counting both even when one is absent folds a
            // hair early, never late.
            extraSegments: 2,
            unfoldWidth: Double(Theme.riverMinSegmentWidth),
            foldWidth: Double(Theme.riverMinSegmentWidth - Theme.riverFoldDeadband),
            previouslyFolded: foldedGroupIDs
        )
    }

    /// What the bar draws: each unfolded group as its own segment, then the
    /// folded groups as one aggregate, in display order.
    private struct Segments {
        let drawn: [ProcessGroup]
        let folded: [ProcessGroup]

        var smallResident: UInt64 { folded.reduce(0) { $0 + $1.residentMemory } }
        var smallNonResident: UInt64 { folded.reduce(0) { $0 + $1.rawNonResidentMemory } }
        var residents: [UInt64] { drawn.map(\.residentMemory) + (folded.isEmpty ? [] : [smallResident]) }
        var nonResidents: [UInt64] {
            drawn.map(\.rawNonResidentMemory) + (folded.isEmpty ? [] : [smallNonResident])
        }
    }

    private var segments: Segments {
        let folded = folded
        return Segments(
            drawn: groups.filter { !folded.contains($0.id) },
            folded: groups.filter { folded.contains($0.id) }
        )
    }

    /// Bytes shown as free at the right end of the bar. Mirrors
    /// `systemMemory.available` so it matches the summary stats below.
    private var freeBytes: UInt64 {
        min(systemMemory.totalPhysical, systemMemory.available)
    }

    /// Resolves the currently hovered region to a readout string. Returns the
    /// empty string when nothing in the river is hovered.
    private func hoverReadout(_ segments: Segments) -> String {
        guard let id = hoveredGroupID else { return "" }
        if id == Self.freeRegionID { return freeReadoutText }
        if id == Self.otherRegionID { return otherReadoutText }
        if id == Self.smallGroupsRegionID {
            // Every member can unfold while the pointer rests on the segment,
            // removing it before `onHover(false)` fires — same as a vanished
            // group, show nothing rather than "0 small groups".
            return segments.folded.isEmpty ? "" : smallGroupsReadoutText(segments)
        }
        if let group = groups.first(where: { $0.id == id }) {
            return readoutText(for: group)
        }
        return ""
    }

    var body: some View {
        let segments = segments
        let highlighted: Set<String> = hoveredGroupID == Self.smallGroupsRegionID
            ? Set(segments.folded.map(\.id))
            : []

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: Theme.riverAxisLabelGap) {
                axisLabels
                riverBar(segments)
            }
            readoutRow(hoverReadout(segments))
                .padding(.leading, Theme.riverAxisLabelWidth + Theme.riverAxisLabelGap)
        }
        .onChange(of: segments.folded.map(\.id), initial: true) { _, ids in
            foldedGroupIDs = Set(ids)
        }
        .onChange(of: highlighted, initial: true) { _, ids in
            highlightedGroupIDs = ids
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

    /// Stub depths and the bar's reserved height. Computed outside the
    /// `GeometryReader` — the frame height would otherwise depend on a value
    /// only available inside it. Folding makes the segments depend on width,
    /// so this reads `barWidth` from the previous layout pass instead.
    private func depths(for segments: Segments) -> RiverDepths {
        RiverLayout.computeDepths(
            residents: segments.residents,
            nonResidents: segments.nonResidents,
            bandHeight: Double(Theme.riverHeight),
            depthCap: Double(Theme.riverMaxDepth),
            hiddenFloor: Theme.memoryHiddenFloor,
            currentStep: Double(depthStep),
            quantum: Double(Theme.riverDepthQuantum),
            shrinkDeadband: Double(Theme.riverShrinkDeadband)
        )
    }

    private func riverBar(_ segments: Segments) -> some View {
        let depths = depths(for: segments)
        let reserved = CGFloat(depths.reserved)
        let smallIndex = segments.drawn.count

        return GeometryReader { geo in
            let layout = RiverLayout.compute(
                footprints: segments.residents,
                freeBytes: freeBytes,
                totalPhysical: systemMemory.totalPhysical,
                totalWidth: Double(geo.size.width),
                minSegmentWidth: Double(Theme.riverMinSegmentWidth),
                gap: Double(Theme.riverSegmentGap)
            )
            HStack(alignment: .top, spacing: Theme.riverSegmentGap) {
                if barWidth > 0 {
                    ForEach(Array(segments.drawn.enumerated()), id: \.element.id) { index, group in
                        segmentView(
                            id: group.id,
                            label: labelText(for: group),
                            readout: readoutText(for: group),
                            width: CGFloat(layout.processWidths[index]),
                            depth: CGFloat(depths.depths[index]),
                            isClipped: depths.clipped[index],
                            onTap: { selectedGroupID = group.id }
                        )
                    }
                    if let first = segments.folded.first {
                        // Clicking lands on a real row — the first folded group in
                        // display order — rather than a synthetic combined group.
                        segmentView(
                            id: Self.smallGroupsRegionID,
                            label: smallGroupsLabel(count: segments.folded.count),
                            readout: smallGroupsReadoutText(segments),
                            width: CGFloat(layout.processWidths[smallIndex]),
                            depth: CGFloat(depths.depths[smallIndex]),
                            isClipped: depths.clipped[smallIndex],
                            onTap: { selectedGroupID = first.id }
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
        }
        .frame(height: reserved)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
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
    private func readoutRow(_ hoverReadout: String) -> some View {
        ZStack(alignment: .leading) {
            MemoryKeyView()
                .opacity(hoverReadout.isEmpty ? 1 : 0)
                // Opacity alone doesn't remove a view from the accessibility
                // tree, so without this VoiceOver reads the key and the
                // readout back to back on every hover.
                .accessibilityHidden(!hoverReadout.isEmpty)
            Text(hoverReadout.isEmpty ? " " : hoverReadout)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(hoverReadout.isEmpty ? 0 : 1)
                .accessibilityHidden(hoverReadout.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.1), value: hoverReadout)
    }

    /// One column: the group's slice of the fixed upper band, with its own stub
    /// hanging below the midline. Built as a column rather than as two stacked
    /// bands so hover, tap, hit region, and accessibility label each cover a top
    /// and its own stub as a single unit.
    private func segmentView(
        id: String,
        label: String,
        readout: String,
        width segmentWidth: CGFloat,
        depth: CGFloat,
        isClipped: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredGroupID == id
        let residentTone = isHovered ? Theme.brighten(Theme.memoryResident) : Theme.memoryResident
        let hiddenTone = isHovered ? Theme.brighten(Theme.memoryCompressed) : Theme.memoryCompressed

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(residentTone)
                    .frame(height: Theme.riverHeight)
                    .clipShape(topPieceShape(hasStub: depth > 0))
                    .overlay(
                        Text(label)
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
                updateHover(toID: id, hovering: hovering)
            }
            .onTapGesture(perform: onTap)
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
        let countSuffix = group.processCount > 1 ? " (\(group.processCount) processes)" : ""
        return "\(group.name)\(countSuffix)"
            + memorySuffix(resident: group.residentMemory, nonResident: group.rawNonResidentMemory)
    }

    /// " — 3.1 GB in RAM (9.7% of total) · 1.2 GB compressed", shared by every
    /// segment that stands for groups so their readouts can't drift apart.
    private func memorySuffix(resident: UInt64, nonResident: UInt64) -> String {
        var text = " — \(MemoryFormatter.format(bytes: resident)) in RAM"
        if let percent = percentOfTotal(resident) {
            text += " (\(percent) of total)"
        }
        if nonResident > 0 {
            text += " · \(MemoryFormatter.format(bytes: nonResident)) compressed"
        }
        return text
    }

    private func smallGroupsLabel(count: Int) -> String {
        "\(count) small groups"
    }

    /// "12 small groups — 410 MB in RAM (1.3% of total) · 1.1 GB compressed ·
    /// Journal, Podcasts, terraform-provider-random…". Names come in display
    /// order, so the first is the one a click selects.
    private func smallGroupsReadoutText(_ segments: Segments) -> String {
        let folded = segments.folded
        var text = smallGroupsLabel(count: folded.count)
            + memorySuffix(resident: segments.smallResident, nonResident: segments.smallNonResident)
        let shown = folded.prefix(Self.smallGroupsNamedCount).map(\.name)
        if !shown.isEmpty {
            text += " · " + shown.joined(separator: ", ")
            if folded.count > shown.count { text += "…" }
        }
        return text
    }

    private static let smallGroupsNamedCount = 3

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
