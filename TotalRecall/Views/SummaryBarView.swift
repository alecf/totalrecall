import TotalRecallCore
import SwiftUI

/// Stats displayed below the Memory River: total, used, free, pressure, compressed, swap.
struct SummaryBarView: View {
    let systemMemory: SystemMemoryInfo

    var body: some View {
        HStack(alignment: .top) {
            // Total
            statBlock(
                value: MemoryFormatter.formatCompact(bytes: systemMemory.totalPhysical),
                unit: "GB",
                label: "total"
            )

            Spacer()

            // Used
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(MemoryFormatter.formatCompact(bytes: systemMemory.used))
                        .font(Theme.numberFontLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("USED")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                if systemMemory.compressed > 0 {
                    Text("compressed: \(MemoryFormatter.format(bytes: systemMemory.compressed))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textMuted)
                }
                if systemMemory.swapUsed > 1024 * 1024 {
                    Text("swap: \(MemoryFormatter.format(bytes: systemMemory.swapUsed))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.swapWarn)
                }
            }

            Spacer()

            // Free
            statBlock(
                value: MemoryFormatter.formatCompact(bytes: systemMemory.available),
                unit: "GB",
                label: "free"
            )

            Spacer()

            // Pressure
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.pressureColor(for: systemMemory.memoryPressure))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text("pressure")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    Text(systemMemory.memoryPressure.rawValue.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.pressureColor(for: systemMemory.memoryPressure))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func statBlock(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.numberFontLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
