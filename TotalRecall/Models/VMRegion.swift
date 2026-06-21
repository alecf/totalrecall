import Foundation

/// Human-readable grouping for a VM region's type.
public enum VMRegionCategory: String, Sendable, CaseIterable {
    case text       = "__TEXT"
    case heap       = "Heap"
    case anonymous  = "Anonymous"
    case stack      = "Stack"
    case fileBacked = "File-backed"
    case other      = "Other"
}

extension VMRegionCategory {
    /// Classify a VM region using its user_tag and protection bits.
    /// user_tag values are from mach/vm_statistics.h (not re-exported by Darwin module).
    ///   1–12: malloc variants (MALLOC, MALLOC_SMALL, MALLOC_LARGE, MALLOC_HUGE, SBRK,
    ///         REALLOC, MALLOC_TINY, MALLOC_MEDIUM, MALLOC_LARGE_REUSABLE, MALLOC_LARGE_REUSED,
    ///         MALLOC_NANO, MALLOC_PROB_GUARD)
    ///   30: VM_MEMORY_STACK
    ///   33: VM_MEMORY_DYLIB (shared libraries / frameworks)
    init(userTag: UInt32, protection: UInt32, hasFilePath: Bool) {
        let isExecutable = (protection & 0x04) != 0  // VM_PROT_EXECUTE = 4

        switch userTag {
        case 1...12:  // malloc heap variants
            self = .heap
        case 30:  // VM_MEMORY_STACK
            self = .stack
        default:
            if isExecutable {
                self = .text
            } else if hasFilePath {
                self = .fileBacked
            } else {
                self = .anonymous
            }
        }
    }
}

/// Aggregated VM memory statistics for one region category of a single process.
public struct VMRegion: Identifiable, Sendable {
    public var id: VMRegionCategory { category }
    public let category: VMRegionCategory
    /// Total virtual size across all regions of this type.
    public let size: UInt64
    /// Estimated resident memory (pages_resident × page_size).
    public let residentSize: UInt64

    public init(category: VMRegionCategory, size: UInt64, residentSize: UInt64) {
        self.category = category
        self.size = size
        self.residentSize = residentSize
    }
}
