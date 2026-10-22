import Foundation

public enum MemoryPressure: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

/// System-wide page accounting from `host_statistics64`.
///
/// `used` and `available` follow Activity Monitor: used is app memory + wired
/// + compressor pool, and available is everything else — truly free pages plus
/// cached files macOS can drop on demand. The two partition physical RAM.
/// `inactive` is deliberately not part of either: inactive pages include app
/// memory that is still resident (and still counted in each process's resident
/// size), so treating them as free counted the same pages twice.
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

    /// Anonymous memory apps own, less purgeable pages (Activity Monitor's
    /// "App Memory").
    public let appMemory: UInt64

    /// File-backed and purgeable pages macOS can drop without writing anything
    /// out (Activity Monitor's "Cached Files").
    public let cachedFiles: UInt64

    /// Memory macOS can hand to an app without compressing or swapping:
    /// everything not `used`.
    public var available: UInt64 {
        totalPhysical > used ? totalPhysical - used : 0
    }

    public static let empty = SystemMemoryInfo(
        totalPhysical: 0, used: 0, free: 0, active: 0,
        inactive: 0, wired: 0, compressed: 0,
        memoryPressure: .normal, swapTotal: 0, swapUsed: 0,
        compressorStored: 0, appMemory: 0, cachedFiles: 0
    )
}
