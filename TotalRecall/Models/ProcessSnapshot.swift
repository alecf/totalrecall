import Foundation

/// Identity tuple used for PID-reuse verification before kill actions
/// and for cache invalidation when a PID is recycled.
public struct ProcessIdentity: Equatable, Hashable, Codable, Sendable {
    public let pid: Int32
    public let executablePath: String
    public let startTimeSec: UInt64
    public let startTimeUsec: UInt64
}

/// A point-in-time capture of a single process's metadata and memory metrics.
/// Shared across: data collection, exited process retention, and test fixtures.
public struct ProcessSnapshot: Identifiable, Codable, Sendable {
    public var id: Int32 { pid }

    // Identity
    public let pid: Int32
    public let name: String
    public let path: String
    public let commandLineArgs: [String]  // Redacted at capture time by RedactionFilter
    public let parentPid: Int32
    public let responsiblePid: Int32
    public let bundleIdentifier: String?
    public let workingDirectory: String?

    // Memory metrics
    public let physFootprint: UInt64       // phys_footprint — the canonical metric
    public let residentSize: UInt64        // ri_resident_size
    public let sharedMemory: UInt64        // RSHRD — real shared memory

    // Timing
    public let startTimeSec: UInt64        // pbi_start_tvsec
    public let startTimeUsec: UInt64       // pbi_start_tvusec
    public let firstSeen: Date
    public let lastSeen: Date
    public let exitedAt: Date?

    // Data quality
    public let isPartialData: Bool         // True if some fields couldn't be read (permission denied)

    /// Proportional resident bytes (PSS): private pages plus an even split of
    /// each shared page among the processes mapping it, estimated from a
    /// cached VM-map walk (`ProportionalShareCache`). `nil` in fixtures and
    /// anywhere the monitor didn't supply it; read `proportionalResident`.
    public var proportionalResidentSize: UInt64? = nil

    /// Proportional resident bytes, or the whole resident size when unknown.
    public var proportionalResident: UInt64 { min(proportionalResidentSize ?? residentSize, residentSize) }

    public var processIdentity: ProcessIdentity {
        ProcessIdentity(
            pid: pid,
            executablePath: path,
            startTimeSec: startTimeSec,
            startTimeUsec: startTimeUsec
        )
    }

    /// The kernel's count of this process's compressed bytes, at uncompressed
    /// size, including those in segments swapped to disk
    /// (`SystemProbe.getCompressionInfo`). `nil` for other users' processes,
    /// in fixtures, and anywhere the monitor didn't supply it.
    public var compressedSize: UInt64? = nil

    /// Bytes per second this process read back from swap over the last
    /// refresh. `nil` until two refreshes have measured it, and for processes
    /// whose counter can't be read.
    public var swapinRate: Double? = nil

    /// Proportional compressed bytes: private compressed pages plus an even
    /// split of each shared object's compressed pages among the processes
    /// mapping it, from the same cached walk as `proportionalResidentSize`.
    /// `nil` until the process has been walked, and wherever the kernel's
    /// count is unavailable.
    public var proportionalCompressedSize: UInt64? = nil

    /// Non-resident memory (compressed + swapped). The two halves can't be
    /// split per process — label it "compressed / swapped" in UI. In order of
    /// preference:
    ///
    /// 1. The proportional compressed count, which shares compressed pages
    ///    the way PSS shares resident ones, so summed over processes each
    ///    page counts once.
    /// 2. Before the first walk, the kernel's count clamped to the footprint.
    ///    The kernel counts compressed pages it has charged to this process's
    ///    address space, which for a VM is well above both the pages its
    ///    regions hold and its footprint (~11 GB against ~6 GB and ~7 GB);
    ///    the footprint includes every compressed page the process owns.
    /// 3. For other users' processes, `physFootprint - residentSize`, which
    ///    undercounts whenever resident size includes shared pages footprint
    ///    leaves out.
    public var nonResidentMemory: UInt64 {
        if let proportionalCompressedSize { return proportionalCompressedSize }
        if let compressedSize { return min(compressedSize, physFootprint) }
        return physFootprint > residentSize ? physFootprint - residentSize : 0
    }
}
