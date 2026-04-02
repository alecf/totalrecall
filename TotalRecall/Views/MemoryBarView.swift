import TotalRecallCore
import SwiftUI

/// A tiny 100% stacked horizontal bar showing the memory composition of a process or group.
/// Segments: resident (in RAM) vs non-resident (compressed/swapped).
struct MemoryBarView: View {
    let resident: UInt64
    let nonResident: UInt64

    private var total: UInt64 { resident + nonResident }

    // Use theme-consistent colors:
    // Resident (in RAM) = a calm blue, similar to the river palette
    // Non-resident (compressed/swapped) = amber/warm, suggesting pressure
    private static let residentColor = Color(red: 0.337, green: 0.494, blue: 0.727)  // muted blue
    private static let nonResidentColor = Color(red: 0.82, green: 0.52, blue: 0.22)  // warm amber

    var body: some View {
        GeometryReader { geo in
            let residentFraction = total > 0 ? CGFloat(resident) / CGFloat(total) : 1.0

            HStack(spacing: 0.5) {
                // Resident segment
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.residentColor)
                    .frame(width: max(1, residentFraction * geo.size.width))

                // Non-resident segment (only show if > 0)
                if nonResident > 0 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Self.nonResidentColor)
                }
            }
        }
        .frame(width: 40, height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 2))
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
        let allProcs = Self.collectAll(from: group)
        let totalResident = allProcs.reduce(0 as UInt64) { $0 + $1.residentSize }
        let totalFootprint = allProcs.reduce(0 as UInt64) { $0 + $1.physFootprint }
        let totalNR = totalFootprint > totalResident ? totalFootprint - totalResident : 0
        self.init(resident: totalResident, nonResident: totalNR)
    }

    private static func collectAll(from group: ProcessGroup) -> [ProcessSnapshot] {
        var all = group.processes
        if let subs = group.subGroups {
            for sub in subs { all.append(contentsOf: collectAll(from: sub)) }
        }
        return all
    }
}
