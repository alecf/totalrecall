import Foundation

enum MemoryPressure: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

struct SystemMemoryInfo: Codable, Sendable {
    let totalPhysical: UInt64
    let used: UInt64
    let free: UInt64
    let active: UInt64
    let inactive: UInt64
    let wired: UInt64
    let compressed: UInt64
    let memoryPressure: MemoryPressure

    let swapTotal: UInt64
    let swapUsed: UInt64

    var available: UInt64 { free + inactive }

    static let empty = SystemMemoryInfo(
        totalPhysical: 0, used: 0, free: 0, active: 0,
        inactive: 0, wired: 0, compressed: 0,
        memoryPressure: .normal, swapTotal: 0, swapUsed: 0
    )
}
