import TotalRecallCore
import SwiftUI

/// A tiny 100% stacked horizontal bar showing the memory composition of a process or group.
/// Segments: resident (in RAM) vs non-resident (compressed/swapped).
struct MemoryBarView: View {
    let resident: UInt64
    let nonResident: UInt64

    private var total: UInt64 { resident + nonResident }

    // The ends of the shared memory-state ramp. The Memory River places each
    // group somewhere along that same ramp, so this bar's blue and amber are
    // literally the endpoints of the gradient a river band is sampled from —
    // one palette, one source of truth, rather than two that look alike.
    private static let residentColor = Theme.memoryResident
    private static let nonResidentColor = Theme.memoryCompressed

    var body: some View {
        let residentFraction = total > 0 ? CGFloat(resident) / CGFloat(total) : 1.0

        HStack(spacing: 0.5) {
            // Resident segment
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Self.residentColor)
                .frame(width: max(1, residentFraction * 40))

            // Non-resident segment (only show if > 0)
            if nonResident > 0 {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.nonResidentColor)
            }
        }
        .frame(width: 40, height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .contentShape(Rectangle())
        .help(tooltip)
    }

    private var tooltip: String {
        guard total > 0 else { return "No memory data" }
        let resPct = Int(Double(resident) * 100 / Double(total))
        return "In RAM: \(MemoryFormatter.format(bytes: resident)) (\(resPct)%) · Compressed/Swapped: \(MemoryFormatter.format(bytes: nonResident)) (\(100 - resPct)%)"
    }
}

/// Convenience initializer from a ProcessSnapshot.
extension MemoryBarView {
    init(process: ProcessSnapshot) {
        let nr = process.physFootprint > process.residentSize
            ? process.physFootprint - process.residentSize : 0
        self.init(resident: process.residentSize, nonResident: nr)
    }

    init(group: ProcessGroup) {
        self.init(resident: group.residentMemory, nonResident: group.rawNonResidentMemory)
    }
}
