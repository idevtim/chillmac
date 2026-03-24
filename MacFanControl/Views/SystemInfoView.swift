import SwiftUI

struct SystemInfoView: View {
    @ObservedObject var systemInfo: SystemInfo

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            InfoRow(label: "Model", value: systemInfo.machineModel)
            InfoRow(label: "Chip", value: systemInfo.chipName)
            InfoRow(label: "Memory", value: systemInfo.ramAmount)
            InfoRow(label: "macOS", value: systemInfo.macOSVersion)
            InfoRow(label: "Disk", value: systemInfo.diskUsage)
            InfoRow(label: "Uptime", value: systemInfo.uptime)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}
