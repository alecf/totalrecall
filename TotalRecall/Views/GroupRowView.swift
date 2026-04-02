import TotalRecallCore
import SwiftUI

/// A single collapsed group row: colored dot + name + memory number + trend indicator.
struct GroupRowView: View {
    let group: ProcessGroup
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Accent dot
            Circle()
                .fill(Theme.accentColor(for: group.classifierName))
                .frame(width: Theme.dotSize, height: Theme.dotSize)

            // Icon
            if let icon = group.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Theme.iconSize, height: Theme.iconSize)
            }

            // Name
            Text(group.name)
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if let subGroups = group.subGroups, !subGroups.isEmpty {
                Text("(\(subGroups.count))")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
            }

            Spacer()

            // Memory — the hero number
            Text(MemoryFormatter.format(bytes: group.deduplicatedFootprint))
                .font(Theme.numberFont)
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())

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
