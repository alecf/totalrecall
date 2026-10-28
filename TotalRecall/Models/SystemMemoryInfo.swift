import Foundation

public enum MemoryPressure: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

/// System-wide page accounting from `host_statistics64`.
///
/// `used` and `available` follow Activity Monitor: used is app memory + wired
/// + compressor pool (`usedBytes`), and available is everything else — truly
/// free pages plus cached files macOS can drop on demand. The two partition
/// physical RAM. `inactive` is part of neither: inactive pages include app
/// memory that is still resident, so it is not available.
///
/// Per-process resident sizes don't partition with these. They count shared
/// pages once per process and include file-backed pages the kernel files under
/// cached files, so summing groups against `used` overlaps — `RiverAccounting`
/// reconciles the two for the river.
public struct SystemMemoryInfo: Codable, Sendable {
    public let totalPhysical: UInt64
    /// App memory + wired + compressor pool.
    public let used: UInt64
    /// Truly free pages. Usually near zero — macOS fills spare RAM with cache.
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let wired: UInt64
    /// Physical RAM the compressor pool occupies.
    public let compressed: UInt64
    public let memoryPressure: MemoryPressure

    public let swapTotal: UInt64
    public let swapUsed: UInt64

    /// Uncompressed size of everything held in the compressor pool — what the
    /// apps think they have, against `compressed`, what it actually costs.
    public let compressorStored: UInt64

    /// File-backed and purgeable pages macOS can drop without writing anything
    /// out (Activity Monitor's "Cached Files").
    public let cachedFiles: UInt64

    /// Memory macOS can hand to an app without compressing or swapping:
    /// everything not `used`. `0` when there are no page counts (`used` is
    /// `0` only when the host query failed), rather than all of RAM.
    public var available: UInt64 {
        guard used > 0, totalPhysical > used else { return 0 }
        return totalPhysical - used
    }

    /// Activity Monitor's "Memory Used": app memory (anonymous pages less
    /// purgeable) + wired + compressor pool, clamped to physical RAM. Not
    /// active + wired + compressed — active includes file cache, and inactive
    /// app memory is still in use.
    public static func usedBytes(
        internal internalBytes: UInt64,
        purgeable: UInt64,
        wired: UInt64,
        compressed: UInt64,
        totalPhysical: UInt64
    ) -> UInt64 {
        let appMemory = internalBytes > purgeable ? internalBytes - purgeable : 0
        return min(totalPhysical, appMemory + wired + compressed)
    }

    /// Activity Monitor's "Cached Files": file-backed plus purgeable pages.
    public static func cachedFileBytes(external: UInt64, purgeable: UInt64) -> UInt64 {
        external + purgeable
    }

    public static let empty = SystemMemoryInfo(
        totalPhysical: 0, used: 0, free: 0, active: 0,
        inactive: 0, wired: 0, compressed: 0,
        memoryPressure: .normal, swapTotal: 0, swapUsed: 0,
        compressorStored: 0, cachedFiles: 0
    )
}
