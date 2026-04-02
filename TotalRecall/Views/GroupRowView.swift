import TotalRecallCore
import SwiftUI

/// A single collapsed group row: colored dot + name + memory number + trend indicator.
struct GroupRowView: View {
    let group: ProcessGroup
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Accent dot — color matches the river segment and indicates the classifier type
            Circle()
                .fill(Theme.accentColor(for: group.classifierName))
                .frame(width: Theme.dotSize, height: Theme.dotSize)
                .help(classifierLabel)

            // Icon — rasterize NSISIconImageRep to a bitmap for SwiftUI compatibility
            if let icon = group.icon {
                Image(nsImage: rasterizeIcon(icon, size: Int(Theme.iconSize * 2)))
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

    private var classifierLabel: String {
        switch group.classifierName {
        case "Chrome": return "Browser (Chrome-based)"
        case "Electron": return "Desktop app (Electron)"
        case "System": return "macOS system service"
        case "Claude Code": return "Claude Code session"
        case "Generic": return "Application"
        default: return group.classifierName
        }
    }

    private func trendDisplay(_ trend: Trend) -> (String, Color) {
        switch trend {
        case .up: return ("▲", Theme.trendUp)
        case .down: return ("▼", Theme.trendDown)
        case .stable: return ("─", Theme.textMuted)
        case .unknown: return ("─", Theme.textMuted.opacity(0.5))
        }
    }

    /// Rasterize an NSImage to a bitmap at the given pixel size.
    /// NSWorkspace icons use NSISIconImageRep which SwiftUI's Image(nsImage:)
    /// may not render correctly — drawing to a bitmap fixes this.
    private func rasterizeIcon(_ icon: NSImage, size: Int) -> NSImage {
        let targetSize = NSSize(width: size, height: size)
        let bitmap = NSImage(size: targetSize)
        bitmap.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: icon.size),
                  operation: .copy, fraction: 1.0)
        bitmap.unlockFocus()
        return bitmap
    }
}
