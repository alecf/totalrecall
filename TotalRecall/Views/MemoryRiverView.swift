import TotalRecallCore
import SwiftUI

/// The hero element: a horizontal stacked bar showing memory occupancy against
/// the machine's total physical RAM. Process groups come first, sized by
/// resident memory scaled to fit app memory, then measured system segments —
/// Other (app memory no group accounts for), Kernel, Compressor, and
/// Available — from `RiverAccounting`. With `estimatePoolShare`, the
/// Compressor segment is shared out into the groups' widths instead. A readout row beneath the bar reveals the hovered segment's name,
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
    /// Share the compressor pool out to the groups as an estimate, instead of
    /// drawing it as its own segment (`RiverAccounting`).
    let estimatePoolShare: Bool

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

    /// Synthetic ID used in `hoveredGroupID` to represent the Available segment.
    /// No real group will ever have this ID, so cross-view highlighting (group
    /// list rows checking `hoveredGroupID == group.id`) is unaffected.
    private static let freeRegionID = "__memory_river_free__"
    private static let otherRegionID = "__memory_river_other__"
    private static let kernelRegionID = "__memory_river_kernel__"
    private static let compressorRegionID = "__memory_river_compressor__"
    /// Synthetic ID for the small-groups segment.
    private static let smallGroupsRegionID = "__memory_river_small_groups__"

    /// How RAM divides between the groups and the measured system segments,
    /// including the factor groups are scaled by to fit app memory.
    private var accounting: RiverAccounting {
        func total(_ bytes: (ProcessGroup) -> UInt64) -> UInt64 {
            groups.reduce(UInt64(0)) { partial, group in
                let (sum, overflow) = partial.addingReportingOverflow(bytes(group))
                return overflow ? UInt64.max : sum
            }
        }
        return RiverAccounting.compute(
            groupResident: total(\.proportionalResidentMemory),
            groupNonResident: total(\.rawNonResidentMemory),
            estimatePoolShare: estimatePoolShare,
            system: systemMemory
        )
    }

    /// Folded set for the current groups and bar width, with the previous set
    /// as hysteresis state. Judged on scaled widths — what the bar draws.
    private func folded(_ accounting: RiverAccounting) -> Set<String> {
        RiverFolding.foldedIDs(
            ids: groups.map(\.id),
            residents: groups.map {
                accounting.scaled(accounting.bandBytes(resident: $0.proportionalResidentMemory,
                                                       nonResident: $0.rawNonResidentMemory))
            },
            totalPhysical: systemMemory.totalPhysical,
            barWidth: Double(barWidth),
            gap: Double(Theme.riverSegmentGap),
            extraSegments: accounting.systemSegments.filter { $0 > 0 }.count,
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
        let accounting: RiverAccounting

        var smallResident: UInt64 { folded.reduce(0) { $0 + $1.proportionalResidentMemory } }
        var smallNonResident: UInt64 { folded.reduce(0) { $0 + $1.rawNonResidentMemory } }
        /// In-RAM bytes before scaling — proportional resident memory plus any
        /// estimated pool share — for stub depths, a ratio, so scale-free.
        var residents: [UInt64] {
            drawn.map { accounting.bandBytes(resident: $0.proportionalResidentMemory, nonResident: $0.rawNonResidentMemory) }
                + (folded.isEmpty ? [] : [accounting.bandBytes(resident: smallResident, nonResident: smallNonResident)])
        }
        /// In-RAM bytes scaled to fit app memory, for widths.
        var widthBytes: [UInt64] { residents.map(accounting.scaled) }
        /// What each stub draws: its compressed memory, or with the pool
        /// shared out, the estimated part in swap (`RiverAccounting.stubBytes`).
        var nonResidents: [UInt64] {
            (drawn.map(\.rawNonResidentMemory) + (folded.isEmpty ? [] : [smallNonResident])).map(accounting.stubBytes)
        }
    }

    private var segments: Segments {
        let accounting = accounting
        let folded = folded(accounting)
        return Segments(
            drawn: groups.filter { !folded.contains($0.id) },
            folded: groups.filter { folded.contains($0.id) },
            accounting: accounting
        )
    }

    /// A measured segment after the groups. Upper band only: none of these
    /// has anything compressed or swapped out of it.
    private struct SystemSegment {
        let id: String
        let name: String
        let bytes: UInt64
        let fill: Color
        let readout: String
    }

    /// Other, Kernel, Compressor, Available — in `RiverAccounting.systemSegments`
    /// order, so they line up with `RiverLayout.systemWidths`.
    private func systemSegments(_ accounting: RiverAccounting) -> [SystemSegment] {
        [
            SystemSegment(
                id: Self.otherRegionID, name: "Other", bytes: accounting.other,
                fill: Theme.riverOther, readout: otherReadoutText(accounting.other)
            ),
            SystemSegment(
                id: Self.kernelRegionID, name: "Kernel", bytes: accounting.kernel,
                fill: Theme.riverOther, readout: kernelReadoutText(accounting.kernel)
            ),
            SystemSegment(
                id: Self.compressorRegionID, name: "Compressor", bytes: accounting.compressor,
                fill: Theme.riverOther, readout: compressorReadoutText(accounting.compressor)
            ),
            SystemSegment(
                id: Self.freeRegionID, name: "Available", bytes: accounting.available,
                fill: Theme.riverFree, readout: availableReadoutText(accounting.available)
            ),
        ]
    }

    /// Resolves the currently hovered region to a readout string. Returns the
    /// empty string when nothing in the river is hovered.
    private func hoverReadout(_ segments: Segments) -> String {
        guard let id = hoveredGroupID else { return "" }
        if let system = systemSegments(segments.accounting).first(where: { $0.id == id }) {
            return system.bytes > 0 ? system.readout : ""
        }
        if id == Self.smallGroupsRegionID {
            // Every member can unfold while the pointer rests on the segment,
            // removing it before `onHover(false)` fires — same as a vanished
            // group, show nothing rather than "0 small groups".
            return segments.folded.isEmpty ? "" : smallGroupsReadoutText(segments)
        }
        if let group = groups.first(where: { $0.id == id }) {
            return readoutText(for: group, accounting: segments.accounting)
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
                axisLabels(swappedOnly: segments.accounting.stubsShowSwap)
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
    ///
    /// With the pool shared out, the stubs hold only the estimated swapped
    /// part, and the lower label says so.
    private func axisLabels(swappedOnly: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            axisLabel(Theme.residentLabel, tone: Theme.memoryResident)
                .frame(height: Theme.riverHeight)
            axisLabel(swappedOnly ? Theme.swappedLabel : Theme.nonResidentLabel, tone: Theme.memoryCompressed)
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
                footprints: segments.widthBytes,
                systemSegments: segments.accounting.systemSegments,
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
                            readout: readoutText(for: group, accounting: segments.accounting),
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
                    ForEach(Array(systemSegments(segments.accounting).enumerated()), id: \.element.id) { index, system in
                        if layout.systemWidths[index] > 0 {
                            systemSegmentView(system, width: CGFloat(layout.systemWidths[index]))
                        }
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

    private func systemSegmentView(_ system: SystemSegment, width: CGFloat) -> some View {
        let size = MemoryFormatter.format(bytes: system.bytes)
        return RoundedRectangle(cornerRadius: 2)
            .fill(system.fill)
            .frame(width: width, height: Theme.riverHeight)
            .overlay(
                // Drop the name before truncating the figure.
                ViewThatFits(in: .horizontal) {
                    systemLabel("\(system.name) \(size)")
                    systemLabel(size)
                }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(width >= Theme.riverLabelMinSegmentWidth ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                updateHover(toID: system.id, hovering: hovering)
            }
            .accessibilityLabel(system.readout)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: width)
    }

    private func systemLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.riverLabelFont)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
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

    /// "Chrome (34 processes) — 3.1 GB in RAM (9.7% of total) · 1.2 GB
    /// compressed · 4.0 GB shared". The process count appears when there is
    /// more than one; the percentage is omitted until total RAM is known, so
    /// the readout never says "0% of total".
    ///
    /// "In RAM" is the group's proportional share (summed PSS) — what the
    /// segment's width shows. The rest of its resident size is pages other
    /// groups map too (system libraries, the dyld cache), charged to them in
    /// part, so it trails as its own "shared" figure. The compressed figure is what
    /// sets the stub's depth.
    private func readoutText(for group: ProcessGroup, accounting: RiverAccounting) -> String {
        let countSuffix = group.processCount > 1 ? " (\(group.processCount) processes)" : ""
        let proportional = group.proportionalResidentMemory
        var text = "\(group.name)\(countSuffix)"
            + memorySuffix(resident: proportional, nonResident: group.rawNonResidentMemory, accounting: accounting)
        let shared = group.residentMemory > proportional ? group.residentMemory - proportional : 0
        if shared >= Self.sharedReadoutFloor {
            text += " · \(MemoryFormatter.format(bytes: shared)) shared"
        }
        if let rate = Theme.visibleSwapinRate(group) {
            text += " · reading \(MemoryFormatter.format(bytesPerSecond: rate)) from swap"
        }
        return text
    }

    /// Below this, a group's shared figure is noise and stays out of its readout.
    private static let sharedReadoutFloor: UInt64 = 1024 * 1024

    /// " — 3.1 GB in RAM (9.7% of total) · 1.2 GB compressed", shared by every
    /// segment that stands for groups so their readouts can't drift apart.
    /// With the pool shared out, the estimated share joins the in-RAM figure
    /// with a "~": " — 3.1 GB in RAM + ~0.3 GB in the compressor (10.6% of
    /// total) · 1.2 GB compressed, ~0.6 GB swapped" — the stub draws the
    /// swapped part.
    private func memorySuffix(resident: UInt64, nonResident: UInt64, accounting: RiverAccounting) -> String {
        var text = " — \(MemoryFormatter.format(bytes: resident)) in RAM"
        let poolShare = accounting.poolShare(nonResident)
        if poolShare > 0 {
            text += " + ~\(MemoryFormatter.format(bytes: poolShare)) in the compressor"
        }
        if let percent = percentOfTotal(accounting.bandBytes(resident: resident, nonResident: nonResident)) {
            text += " (\(percent) of total)"
        }
        if nonResident > 0 {
            text += " · \(MemoryFormatter.format(bytes: nonResident)) compressed"
            let swapped = accounting.stubBytes(nonResident)
            if accounting.stubsShowSwap && swapped > 0 {
                text += ", ~\(MemoryFormatter.format(bytes: swapped)) swapped"
            }
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
            + memorySuffix(resident: segments.smallResident, nonResident: segments.smallNonResident,
                           accounting: segments.accounting)
        let shown = folded.prefix(Self.smallGroupsNamedCount).map(\.name)
        if !shown.isEmpty {
            text += " · " + shown.joined(separator: ", ")
            if folded.count > shown.count { text += "…" }
        }
        return text
    }

    private static let smallGroupsNamedCount = 3

    /// "Available — 7.0 GB (21.9% of total) · 6.9 GB cached files". Not
    /// "Free": truly free pages are usually near zero, because macOS fills
    /// spare RAM with file cache it reclaims on demand.
    ///
    /// The system readouts are each kept short enough to fit the readout row
    /// at the window's minimum width (~488 pt).
    private func availableReadoutText(_ bytes: UInt64) -> String {
        var text = "Available — \(sizeAndShare(bytes))"
        let cached = min(systemMemory.cachedFiles, bytes)
        if cached > 0 {
            text += " · \(MemoryFormatter.format(bytes: cached)) cached files"
        }
        return text
    }

    /// "Kernel — 4.5 GB (14.1% of total) · wired, never compressed or swapped".
    private func kernelReadoutText(_ bytes: UInt64) -> String {
        "Kernel — \(sizeAndShare(bytes)) · wired, never compressed or swapped"
    }

    /// "Compressor — 12.2 GB (38.1% of total) holding 24.9 GB compressed ·
    /// 12.0 GB in swap". The physical RAM compressed pages occupy, against what they'd
    /// take uncompressed, then the compressed segments written out to disk.
    /// Together they are where every stub's memory lives; which of the two
    /// holds any one app's pages is something the kernel doesn't track.
    private func compressorReadoutText(_ bytes: UInt64) -> String {
        var text = "Compressor — \(sizeAndShare(bytes))"
        if systemMemory.compressorStored > 0 {
            text += " holding \(MemoryFormatter.format(bytes: systemMemory.compressorStored)) compressed"
        }
        if systemMemory.swapUsed > 0 {
            text += " · \(MemoryFormatter.format(bytes: systemMemory.swapUsed)) in swap"
        }
        return text
    }

    /// "Other — 1.2 GB (3.8% of total) of app memory not in any group" — app
    /// memory the groups don't reach, such as processes Total Recall can't
    /// inspect.
    private func otherReadoutText(_ bytes: UInt64) -> String {
        "Other — \(sizeAndShare(bytes)) of app memory not in any group"
    }

    private func sizeAndShare(_ bytes: UInt64) -> String {
        let size = MemoryFormatter.format(bytes: bytes)
        guard let percent = percentOfTotal(bytes) else { return size }
        return "\(size) (\(percent) of total)"
    }

    private func percentOfTotal(_ bytes: UInt64) -> String? {
        guard systemMemory.totalPhysical > 0 else { return nil }
        let fraction = Double(bytes) / Double(systemMemory.totalPhysical) * 100
        return String(format: "%.1f%%", fraction)
    }
}
