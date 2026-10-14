import SwiftUI

/// Card at the top of the main popover announcing a newer version, so updating is one
/// click from the first screen rather than buried in Settings.
struct UpdateBannerView: View {
    let version: String
    let onUpdate: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text("ChillMac v\(version) is available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text("Installs and relaunches automatically")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            Button(action: onUpdate) {
                Text("Update")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.teal)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.teal.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}
