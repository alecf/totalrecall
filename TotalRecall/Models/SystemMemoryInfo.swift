import Foundation

public enum MemoryPressure: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

public struct SystemMemoryInfo: Codable, Sendable {
    public let totalPhysical: UInt64
    public let used: UInt64
    public let free: UInt64
    public let active: UInt64
    public let inactive: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let memoryPressure: MemoryPressure

    public let swapTotal: UInt64
    public let swapUsed: UInt64

    public var available: UInt64 { free + inactive }

    public static let empty = SystemMemoryInfo(
        totalPhysical: 0, used: 0, free: 0, active: 0,
        inactive: 0, wired: 0, compressed: 0,
        memoryPressure: .normal, swapTotal: 0, swapUsed: 0
    )
}
