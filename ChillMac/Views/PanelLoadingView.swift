import SwiftUI

/// Spinner and caption shown in place of a panel section whose data hasn't arrived yet.
///
/// Panels are driven by polling timers, and several values land a beat after the panel
/// opens — process lists, SMC sensor discovery, the disk walk. Without this the section
/// reads as empty, or worse, as a definitive "none found".
struct PanelLoadingView: View {
    let message: String
    var minHeight: CGFloat = 64

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}
