import TotalRecallCore
import SwiftUI

/// Shows a breakdown of VM regions for a single process, grouped by category.
/// Loaded lazily when the "Regions" tab is first selected.
struct VMRegionsView: View {
    let pid: pid_t

    @State private var regions: [VMRegion]? = nil
    @State private var isLoading = true
    @State private var accessDenied = false

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Reading VM map…")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
            } else if accessDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.slash")
                        .font(.title2)
                        .foregroundStyle(Theme.textMuted)
                    Text("VM map unavailable")
                        .font(Theme.processFont)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Region data requires the process to be owned by your user account. System processes and processes owned by other users cannot be inspected.")
                        .font(Theme.explanationFont)
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            } else if let regions {
                regionTable(regions)
            }
        }
        .task(id: pid) {
            isLoading = true
            accessDenied = false
            regions = nil

            let targetPID = pid
            let fetched: [VMRegion]? = await Task.detached {
                SystemProbe.getVMRegions(pid: targetPID)
            }.value

            isLoading = false
            if let fetched {
                regions = fetched
            } else {
                accessDenied = true
            }
        }
    }

    private func regionTable(_ regions: [VMRegion]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("Region")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Size")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 68, alignment: .trailing)
                Text("Resident")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.bottom, 2)

            Divider().foregroundStyle(Theme.textMuted)

            ForEach(regions) { region in
                HStack(spacing: 0) {
                    Text(region.category.rawValue)
                        .font(Theme.processFont)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(MemoryFormatter.format(bytes: region.size))
                        .font(Theme.processNumberFont)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 68, alignment: .trailing)
                    Text(MemoryFormatter.format(bytes: region.residentSize))
                        .font(Theme.processNumberFont)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }

            Divider().foregroundStyle(Theme.textMuted)
                .padding(.top, 4)

            Text("Sizes are virtual; Resident is pages currently in RAM × page size.")
                .font(Theme.explanationFont)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 2)
        }
    }
}
