import SwiftUI

/// Shown in place of the Performance Mode card when the privileged helper cannot control
/// fans. Without this the popover offered a Performance Mode toggle and manual sliders that
/// looked live but did nothing, and a user whose helper was merely awaiting approval had no
/// indication of that and no way to act on it from inside the app.
struct HelperStatusCard: View {
    let state: HelperInstaller.HelperState
    let isBusy: Bool
    let onInstall: () -> Void
    let onOpenLoginItems: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if state == .checking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(explanation)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                }
            } else if let action {
                Button(action: action.perform) {
                    Text(action.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBg)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(state == .checking ? Color.clear : Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Copy

    private struct Action {
        let label: String
        let perform: () -> Void
    }

    private var icon: String {
        switch state {
        case .needsApproval: return "hand.raised.fill"
        case .unresponsive: return "exclamationmark.triangle.fill"
        default: return "bolt.slash.fill"
        }
    }

    private var title: String {
        switch state {
        case .checking: return "Checking fan control…"
        case .running: return "Fan control ready"
        case .needsApproval: return "Fan control needs approval"
        case .needsInstall: return "Fan control not installed"
        case .needsUpdate: return "Fan control needs updating"
        case .unresponsive: return "Fan control not responding"
        }
    }

    private var explanation: String {
        switch state {
        case .checking:
            return "Looking for the privileged helper."
        case .running:
            return "The helper is running."
        case .needsApproval:
            return "Enable ChillMac under Login Items & Extensions, then reopen this window."
        case .needsInstall:
            return "ChillMac needs a privileged helper to set fan speeds. Monitoring works without it."
        case .needsUpdate:
            return "The installed helper is from an older version of ChillMac."
        case .unresponsive:
            return "The helper is installed but is not answering. Reinstalling usually fixes this."
        }
    }

    private var action: Action? {
        switch state {
        case .checking, .running:
            return nil
        case .needsApproval:
            return Action(label: "Open Login Items", perform: onOpenLoginItems)
        case .needsInstall:
            return Action(label: "Install Helper", perform: onInstall)
        case .needsUpdate:
            return Action(label: "Update Helper", perform: onInstall)
        case .unresponsive:
            return Action(label: "Reinstall Helper", perform: onInstall)
        }
    }
}
