import TotalRecallCore
import SwiftUI

/// A single collapsed group row: colored dot + name + memory number + trend indicator.
struct GroupRowView: View {
    let group: ProcessGroup
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            if let icon = group.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Theme.iconSize, height: Theme.iconSize)
            }

            // Name
            GroupNameText(group: group)

            if let subGroups = group.subGroups, !subGroups.isEmpty {
                Text("(\(subGroups.count))")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            // Process count for multi-process groups
            if group.processCount > 1 {
                Text("\(group.processCount) processes")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 80, alignment: .trailing)
            } else {
                Spacer()
                    .frame(width: 80)
            }

            // Memory composition bar
            MemoryBarView(group: group)

            // Memory — the hero number
            // Fixed width so columns align across rows. 64pt fits "1024 MB" / "128 GB" in numberFont.
            Text(MemoryFormatter.format(bytes: group.deduplicatedFootprint))
                .font(Theme.numberFont)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: Theme.memoryColumnWidth, alignment: .trailing)

            // Trend
            trendView(group.trend)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func trendView(_ trend: Trend) -> some View {
        let (symbol, color) = trendDisplay(trend)
        Text(symbol)
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: 16)
    }

    private func trendDisplay(_ trend: Trend) -> (String, Color) {
        switch trend {
        case .up: return ("▲", Theme.trendUp)
        case .down: return ("▼", Theme.trendDown)
        case .stable: return ("─", Theme.textMuted)
        case .unknown: return ("─", Theme.textMuted.opacity(0.5))
        }
    }

}

struct GroupNameText: View {
    let group: ProcessGroup
    var baseFont: Font = Theme.labelFont
    var contextFont: Font = Theme.processFont

    var body: some View {
        HStack(spacing: 0) {
            Text(baseName)
                .font(baseFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if let context {
                Text(" - \(context)")
                    .font(contextFont)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .lineLimit(1)
    }

    private var baseName: String {
        guard let context else { return group.name }
        return String(group.name.dropLast(" - \(context)".count))
    }

    private var context: String? {
        guard let explanation = group.explanation else { return nil }
        let suffix = " - \(explanation)"
        guard group.name.hasSuffix(suffix) else { return nil }
        return explanation
    }
}
