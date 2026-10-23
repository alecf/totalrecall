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
/// Per-group resident sizes don't add up to app memory. Each group counts the
/// shared pages it maps (system libraries, the dyld shared cache), so the same
/// physical pages appear in many groups, and resident sizes include file-backed
/// pages the kernel files under cached files. When the groups overshoot the app
/// region they are scaled down uniformly to fit, so every group keeps its size
/// relative to every other and the bar still adds up to total RAM. When they
/// fall short — processes Total Recall can't inspect — the shortfall is drawn
/// as Other: app memory no group accounts for.
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
    /// Free pages plus cached files.
    public let available: UInt64

    public init(groupScale: Double, other: UInt64, kernel: UInt64, compressor: UInt64, available: UInt64) {
        self.groupScale = groupScale
        self.other = other
        self.kernel = kernel
        self.compressor = compressor
        self.available = available
    }

    /// The system segments in bar order: Other, Kernel, Compressor, Available.
    public var systemSegments: [UInt64] { [other, kernel, compressor, available] }

    /// - Parameters:
    ///   - groupResident: Sum of every group's resident bytes.
    ///   - system: The latest system snapshot.
    public static func compute(groupResident: UInt64, system: SystemMemoryInfo) -> RiverAccounting {
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
        let compressor = min(system.compressed, total - kernel)
        let available = min(system.available, total - kernel - compressor)
        let appRegion = total - kernel - compressor - available

        let scale: Double
        let other: UInt64
        if groupResident > appRegion {
            scale = Double(appRegion) / Double(groupResident)
            other = 0
        } else {
            scale = 1
            other = appRegion - groupResident
        }
        return RiverAccounting(
            groupScale: scale,
            other: other,
            kernel: kernel,
            compressor: compressor,
            available: available
        )
    }

    /// `bytes` scaled for width. Rounded down, so scaled groups never exceed
    /// the app region.
    public func scaled(_ bytes: UInt64) -> UInt64 {
        groupScale >= 1 ? bytes : UInt64(Double(bytes) * groupScale)
    }
}
