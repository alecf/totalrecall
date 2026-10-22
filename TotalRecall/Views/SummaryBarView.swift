import TotalRecallCore
import SwiftUI

/// Stats displayed below the Memory River: total, used, available, pressure,
/// compressed, swap. Used and available follow Activity Monitor and add up to
/// total (see `SystemMemoryInfo`).
///
/// The compressed figure is drawn in `Theme.memoryCompressed` behind a swatch,
/// so the number that explains the river's amber stubs is itself amber.
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
                    Text("GB")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                    Text("USED")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                // Swatched and toned to match the river's lower half: this is
                // the system-wide total of the same memory each segment hangs
                // a stub for, so it is worth spending the color to say so.
                if systemMemory.compressed > 0 {
                    HStack(spacing: 5) {
                        MemorySwatch(color: Theme.memoryCompressed)
                        Text(compressedText)
                            .font(Theme.secondaryFont)
                            .foregroundStyle(Theme.memoryCompressed)
                    }
                }
                // Swap keeps `swapWarn` and gets no swatch. macOS reports it
                // separately from the compressor pool, but the per-process
                // figure the river draws cannot be split between the two — so
                // giving swap its own chip here would key a color the bar
                // never shows.
                if systemMemory.swapUsed > 1024 * 1024 {
                    Text("swap: \(MemoryFormatter.format(bytes: systemMemory.swapUsed))")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.swapWarn)
                }
            }

            Spacer()

            // Available — not "free": most of it is cached files macOS drops on
            // demand, and truly free pages are usually near zero.
            statBlock(
                value: MemoryFormatter.formatCompact(bytes: systemMemory.available),
                unit: "GB",
                label: "available"
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

    /// "compressed: 21.9 GB in 10.4 GB of RAM". The first figure is what the
    /// river's stubs add up to (less swap); the second is what it actually
    /// costs, which is the figure inside `used`.
    private var compressedText: String {
        let pool = MemoryFormatter.format(bytes: systemMemory.compressed)
        guard systemMemory.compressorStored > 0 else { return "compressed: \(pool)" }
        let stored = MemoryFormatter.format(bytes: systemMemory.compressorStored)
        return "compressed: \(stored) in \(pool) of RAM"
    }

    private func statBlock(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.numberFontLarge)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(label)
                .font(Theme.secondaryFont)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
