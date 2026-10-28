import Foundation

/// How the Memory River divides physical RAM between process groups and the
/// system segments after them.
///
/// The system side is measured, not inferred: Kernel is wired memory,
/// Compressor is the physical compressor pool, and Available is free pages
/// plus cached files — all straight from the kernel's page counts, which
/// partition RAM (see `SystemMemoryInfo`). What's left is app memory, and the
/// groups share it.
///
/// Except that cached files include every file page an app has mapped —
/// system libraries, app code, memory-mapped files — and those pages are also
/// in the apps' proportional resident memory. macOS can drop them, but apps
/// would fault them straight back in, so the river doesn't call them
/// available: the part the region walks find mapped (`mappedFiles`) moves out
/// of Available and into the app region, where the groups already draw it.
/// What's left of Available is free pages plus file cache no walked process
/// maps — read cache, files from closed apps, and anything mapped only by
/// processes Total Recall can't inspect.
///
/// Per-group resident sizes don't add up to app memory. Each group counts the
/// shared pages it maps (system libraries, the dyld shared cache), so the same
/// physical pages appear in many groups, and resident sizes include file-backed
/// pages the kernel files under cached files. When the groups overshoot the app
/// region they are scaled down uniformly to fit, so every group keeps its size
/// relative to every other and the bar still adds up to total RAM. When they
/// fall short — processes Total Recall can't inspect — the shortfall is drawn
/// as Other: app memory no group accounts for.
///
/// Optionally the compressor pool is shared out to the groups instead of
/// standing as its own segment (`estimatePoolShare`). Each group is charged
/// pool RAM in proportion to its compressed memory, at one machine-wide rate:
/// the pool's physical size over the groups' summed compressed memory. That
/// rate folds together how well pages compress and how much compressed memory
/// is still in RAM rather than swap, neither of which the kernel reports per
/// process — so the totals are exact and each group's share is an estimate. It
/// overcharges idle groups, whose compressed pages are mostly on disk, and
/// undercharges active ones.
///
/// Carried through, the same estimate splits each group's compressed memory:
/// the fraction the pool still holds is `compressorStored` over the groups'
/// summed compressed memory, and the rest has been written to swap — capped
/// by swap actually in use (`swapUsed`, at the pool's compression ratio), so
/// per-process figures that overshoot the pool never conjure swap that isn't
/// there. With the
/// pool's share already in the band, the stub holds only that remainder
/// (`stubBytes`), at its uncompressed size, so it stays comparable with the
/// compressed figures elsewhere and memory in the compressor is drawn once.
public struct RiverAccounting: Equatable, Sendable {
    /// Factor applied to every group's resident bytes for its width. `1` when
    /// the groups fit the app region as they are.
    public let groupScale: Double
    /// App memory not accounted for by any group.
    public let other: UInt64
    /// Wired memory: the kernel, drivers, and GPU allocations.
    public let kernel: UInt64
    /// Physical RAM the compressor pool occupies.
    public let compressor: UInt64
    /// Free pages plus cached files, less the file pages walked processes map.
    public let available: UInt64
    /// Cached files moved out of Available because walked processes map them.
    public let mappedFiles: UInt64
    /// The cached files left in Available: the ones no walked process maps.
    public let unmappedCachedFiles: UInt64
    /// Bytes of compressor pool charged to a group per byte of its compressed
    /// memory. `0` when the pool is drawn as its own segment.
    public let poolRate: Double
    /// Fraction of a group's compressed memory estimated to be in swap rather
    /// than the pool, or `nil` when stubs hold all of it: the pool is its own
    /// segment, or how much it holds is unknown.
    public let swappedFraction: Double?

    public init(groupScale: Double, other: UInt64, kernel: UInt64, compressor: UInt64, available: UInt64,
                mappedFiles: UInt64 = 0, unmappedCachedFiles: UInt64 = 0,
                poolRate: Double = 0, swappedFraction: Double? = nil) {
        self.groupScale = groupScale
        self.other = other
        self.kernel = kernel
        self.compressor = compressor
        self.available = available
        self.mappedFiles = mappedFiles
        self.unmappedCachedFiles = unmappedCachedFiles
        self.poolRate = poolRate
        self.swappedFraction = swappedFraction
    }

    /// Whether stubs hold only the estimated swapped part, so the river should
    /// call them "Swapped".
    public var stubsShowSwap: Bool { swappedFraction != nil }

    /// What a group's stub draws: all its compressed memory, or with the pool
    /// shared out, the estimated part in swap, at uncompressed size.
    public func stubBytes(_ nonResident: UInt64) -> UInt64 {
        guard let swappedFraction else { return nonResident }
        return UInt64(Double(nonResident) * swappedFraction)
    }

    /// Estimated compressor-pool RAM held by memory with `nonResident` bytes
    /// compressed. Rounded down, so the groups' shares never exceed the pool.
    public func poolShare(_ nonResident: UInt64) -> UInt64 {
        poolRate > 0 ? UInt64(Double(nonResident) * poolRate) : 0
    }

    /// What a group holds in RAM, before scaling: its proportional resident
    /// memory plus its estimated share of the pool.
    public func bandBytes(resident: UInt64, nonResident: UInt64) -> UInt64 {
        Self.saturatingSum(resident, poolShare(nonResident))
    }

    private static func saturatingSum(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? .max : sum
    }

    /// The system segments in bar order: Other, Kernel, Compressor, Available.
    public var systemSegments: [UInt64] { [other, kernel, compressor, available] }

    /// - Parameters:
    ///   - groupResident: Sum of every group's resident bytes.
    ///   - groupNonResident: Sum of every group's compressed memory, the base
    ///     the pool is shared out over.
    ///   - mappedFiles: File-backed memory the walked processes map, from the
    ///     same refresh as the groups.
    ///   - estimatePoolShare: Share the pool out to the groups instead of
    ///     drawing it as its own segment.
    ///   - system: The latest system snapshot.
    public static func compute(
        groupResident: UInt64,
        groupNonResident: UInt64 = 0,
        mappedFiles: UInt64 = 0,
        estimatePoolShare: Bool = false,
        system: SystemMemoryInfo
    ) -> RiverAccounting {
        let total = system.totalPhysical
        // No page counts yet (or the host query failed): there is nothing
        // measured to draw, so the groups stand at their own size.
        guard total > 0, system.used > 0 else {
            return RiverAccounting(
                groupScale: 1,
                other: 0,
                kernel: 0,
                compressor: 0,
                available: total > groupResident ? total - groupResident : 0
            )
        }

        let kernel = min(system.wired, total)
        let pool = min(system.compressed, total - kernel)
        let cachedAndFree = min(system.available, total - kernel - pool)
        let movedFiles = min(mappedFiles, system.cachedFiles, cachedAndFree)
        let available = cachedAndFree - movedFiles
        let unmappedCachedFiles = min(system.cachedFiles - movedFiles, available)

        // Shared out, the pool joins the app region and the groups' bands;
        // with nothing compressed to charge it to, it stays a segment.
        let shared = estimatePoolShare && groupNonResident > 0 && pool > 0
        let poolRate = shared ? Double(pool) / Double(groupNonResident) : 0
        // Unknown pool contents can't be split, so stubs keep everything.
        var swappedFraction: Double?
        if shared && system.compressorStored > 0 {
            let sum = Double(groupNonResident)
            let stored = Double(system.compressorStored)
            let inSwap = Double(system.swapUsed) * stored / Double(pool)
            swappedFraction = max(0, min(1 - stored / sum, inSwap / sum))
        }
        let compressor = shared ? 0 : pool
        let appRegion = total - kernel - compressor - available
        let groupBand = shared ? saturatingSum(groupResident, pool) : groupResident

        let scale: Double
        let other: UInt64
        if groupBand > appRegion {
            scale = Double(appRegion) / Double(groupBand)
            other = 0
        } else {
            scale = 1
            other = appRegion - groupBand
        }
        return RiverAccounting(
            groupScale: scale,
            other: other,
            kernel: kernel,
            compressor: compressor,
            available: available,
            mappedFiles: movedFiles,
            unmappedCachedFiles: unmappedCachedFiles,
            poolRate: poolRate,
            swappedFraction: swappedFraction
        )
    }

    /// `bytes` scaled for width. Rounded down, so scaled groups never exceed
    /// the app region.
    public func scaled(_ bytes: UInt64) -> UInt64 {
        groupScale >= 1 ? bytes : UInt64(Double(bytes) * groupScale)
    }
}
