import Foundation

/// Per-segment depths for the Memory River's lower band, plus the height the
/// whole bar should reserve.
///
/// Width already encodes resident bytes, so a stub of depth
/// `bandHeight × nonResident / resident` makes the stub's *area* encode
/// non-resident bytes on the same scale: with `k` as the horizontal
/// bytes-per-pixel, every segment's area works out to `k × bandHeight` per
/// byte. Equal areas are equal memory across the whole bar, not just within
/// one segment.
public struct RiverDepths: Equatable {
    /// Depth of each segment's stub, in the order groups were given.
    public let depths: [Double]
    /// `true` where the ratio exceeded the cap and the stub was drawn short.
    public let clipped: [Bool]
    /// Height the bar should reserve: band height plus the quantized step.
    public let reserved: Double

    public init(depths: [Double], clipped: [Bool], reserved: Double) {
        self.depths = depths
        self.clipped = clipped
        self.reserved = reserved
    }
}

/// Pixel widths for the Memory River bar's segments, computed so they always
/// fit within the available width.
///
/// The bar lays process group segments left-to-right followed by unattributed
/// memory and a trailing "Free" segment. When total physical RAM is known,
/// process segments start at their true share of total RAM so the visible bar
/// matches the hover readout. Minimum widths borrow from unattributed/free
/// space first; process widths are compressed only when the process segments
/// themselves cannot fit in the bar.
public struct RiverLayout: Equatable {
    /// Width of each process group segment, in the order footprints were given.
    public let processWidths: [Double]
    /// Width of memory not attributed to a process group.
    public let otherWidth: Double
    /// Width of the trailing free segment; `0` when no free region is shown.
    public let freeWidth: Double

    public init(processWidths: [Double], otherWidth: Double = 0, freeWidth: Double) {
        self.processWidths = processWidths
        self.otherWidth = otherWidth
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

        if totalPhysical == 0 {
            return computeRelativeProcessLayout(
                footprints: footprints,
                totalWidth: totalWidth,
                minSegmentWidth: minSegmentWidth,
                gap: gap
            )
        }

        let withoutOther = computeKnownTotalLayout(
            footprints: footprints,
            freeBytes: freeBytes,
            totalPhysical: totalPhysical,
            totalWidth: totalWidth,
            minSegmentWidth: minSegmentWidth,
            gap: gap,
            includeOtherSegment: false
        )

        let usedWidth = withoutOther.processWidths.reduce(0, +) + withoutOther.freeWidth
        let segmentCount = footprints.count + (withoutOther.freeWidth > 0 ? 1 : 0)
        let gapsTotal = Double(max(0, segmentCount - 1)) * gap
        let content = max(0, totalWidth - gapsTotal)

        guard content - usedWidth > 0.5 else { return withoutOther }

        return computeKnownTotalLayout(
            footprints: footprints,
            freeBytes: freeBytes,
            totalPhysical: totalPhysical,
            totalWidth: totalWidth,
            minSegmentWidth: minSegmentWidth,
            gap: gap,
            includeOtherSegment: true
        )
    }

    private static func computeKnownTotalLayout(
        footprints: [UInt64],
        freeBytes: UInt64,
        totalPhysical: UInt64,
        totalWidth: Double,
        minSegmentWidth: Double,
        gap: Double,
        includeOtherSegment: Bool
    ) -> RiverLayout {
        let showFree = freeBytes > 0
        let segmentCount = footprints.count + (includeOtherSegment ? 1 : 0) + (showFree ? 1 : 0)
        let gapsTotal = Double(max(0, segmentCount - 1)) * gap
        let content = max(0, totalWidth - gapsTotal)

        let minWidths = footprints.map { $0 > 0 ? minSegmentWidth : 0 }
        var widths = footprints.enumerated().map { index, footprint in
            let ideal = Double(footprint) / Double(totalPhysical) * content
            return max(minWidths[index], ideal)
        }
        var processTotal = widths.reduce(0, +)

        let freeFraction = min(1, Double(freeBytes) / Double(totalPhysical))
        let idealFreeWidth = showFree ? freeFraction * content : 0

        if processTotal > content {
            widths = fitProcessWidths(widths, minimums: minWidths, budget: content)
            processTotal = widths.reduce(0, +)
            return RiverLayout(processWidths: widths, otherWidth: 0, freeWidth: max(0, content - processTotal))
        }

        let freeWidth = min(idealFreeWidth, max(0, content - processTotal))
        let otherWidth = includeOtherSegment ? max(0, content - processTotal - freeWidth) : 0
        return RiverLayout(processWidths: widths, otherWidth: otherWidth, freeWidth: freeWidth)
    }

    private static func computeRelativeProcessLayout(
        footprints: [UInt64],
        totalWidth: Double,
        minSegmentWidth: Double,
        gap: Double
    ) -> RiverLayout {
        let segmentCount = footprints.count
        let gapsTotal = Double(max(0, segmentCount - 1)) * gap
        let content = max(0, totalWidth - gapsTotal)
        let totalFootprint = footprints.reduce(0.0) { $0 + Double($1) }

        var widths: [Double] = footprints.map { footprint in
            let share = totalFootprint > 0
                ? Double(footprint) / totalFootprint
                : 1 / Double(footprints.count)
            return share * content
        }

        let minWidths = footprints.map { $0 > 0 ? minSegmentWidth : 0 }
        widths = widths.enumerated().map { index, width in max(minWidths[index], width) }
        widths = fitProcessWidths(widths, minimums: minWidths, budget: content)

        return RiverLayout(processWidths: widths, otherWidth: 0, freeWidth: 0)
    }

    /// - Parameters:
    ///   - residents: Per-group resident bytes, in display order.
    ///   - nonResidents: Per-group compressed/swapped bytes, same order.
    ///   - bandHeight: Height of the fixed upper band, and the cap on stub depth.
    ///   - hiddenFloor: Groups below this many non-resident bytes get no stub,
    ///     so idle daemons don't sprout a full-depth spike out of nothing.
    ///   - currentStep: The step height currently reserved, for hysteresis.
    ///   - quantum: Step size the reserved height snaps to.
    ///   - shrinkDeadband: How far below its lower boundary the deepest stub
    ///     must fall before the reserved height steps down.
    public static func computeDepths(
        residents: [UInt64],
        nonResidents: [UInt64],
        bandHeight: Double,
        hiddenFloor: UInt64,
        currentStep: Double,
        quantum: Double,
        shrinkDeadband: Double
    ) -> RiverDepths {
        var depths: [Double] = []
        var clipped: [Bool] = []
        depths.reserveCapacity(residents.count)
        clipped.reserveCapacity(residents.count)

        for (index, resident) in residents.enumerated() {
            let nonResident = index < nonResidents.count ? nonResidents[index] : 0
            guard nonResident >= hiddenFloor else {
                depths.append(0)
                clipped.append(false)
                continue
            }
            // A group with no resident memory has an unbounded ratio; it pins
            // to the cap like any other overflowing segment.
            guard resident > 0 else {
                depths.append(bandHeight)
                clipped.append(true)
                continue
            }
            let ratio = Double(nonResident) / Double(resident)
            depths.append(min(1, ratio) * bandHeight)
            clipped.append(ratio > 1)
        }

        let maxDepth = depths.max() ?? 0
        let step = quantizedStep(
            maxDepth: maxDepth,
            currentStep: currentStep,
            quantum: quantum,
            shrinkDeadband: shrinkDeadband
        )
        return RiverDepths(depths: depths, clipped: clipped, reserved: bandHeight + step)
    }

    /// Snap the reserved depth to a multiple of `quantum`, with hysteresis so a
    /// stub hovering at a boundary doesn't toggle the bar's height on every
    /// refresh. Growth is immediate; shrinking must clear the deadband below
    /// the current step's lower boundary.
    private static func quantizedStep(
        maxDepth: Double,
        currentStep: Double,
        quantum: Double,
        shrinkDeadband: Double
    ) -> Double {
        guard quantum > 0 else { return maxDepth }
        let target = (maxDepth / quantum).rounded(.up) * quantum
        if target > currentStep { return target }
        let lowerBoundary = currentStep - quantum
        if maxDepth < lowerBoundary - shrinkDeadband { return target }
        return currentStep
    }

    private static func fitProcessWidths(_ widths: [Double], minimums: [Double], budget: Double) -> [Double] {
        let widthsTotal = widths.reduce(0, +)
        guard widthsTotal > budget, widthsTotal > 0 else { return widths }

        let minTotal = minimums.reduce(0, +)
        guard minTotal > 0 else {
            let scale = budget / widthsTotal
            return widths.map { $0 * scale }
        }
        guard minTotal < budget, minTotal > 0 else {
            let scale = minTotal > 0 ? budget / minTotal : 0
            return minimums.map { $0 * scale }
        }

        let flexibleTotal = zip(widths, minimums).reduce(0) { total, pair in
            total + max(0, pair.0 - pair.1)
        }
        guard flexibleTotal > 0 else { return minimums }

        let flexibleScale = (budget - minTotal) / flexibleTotal
        return zip(widths, minimums).map { width, minimum in
            minimum + max(0, width - minimum) * flexibleScale
        }
    }
}
