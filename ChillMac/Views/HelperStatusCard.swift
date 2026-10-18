import SwiftUI

/// Shown in place of the Cooling control when the privileged helper cannot control fans.
///
/// Written as an invitation rather than a warning: monitoring works without the helper, so
/// nothing is broken, and the old orange "not installed" card read as an error. It still has
/// to explain each state and offer the one action that resolves it, or a user whose helper
/// is merely awaiting approval has no way to find that out from inside the app.
struct HelperStatusCard: View {
    let state: HelperInstaller.HelperState
    let isBusy: Bool
    let onInstall: () -> Void
    let onOpenLoginItems: () -> Void
    @Binding var isCollapsed: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if state == .checking {
                checkingRow
            } else if isCollapsed {
                collapsedRow
            } else {
                expandedCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(theme)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    private var checkingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Checking fan control…")
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
        }
        .padding(14)
    }

    private var collapsedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan.fill")
                .font(.system(size: 14))
                .foregroundColor(theme.teal)
            Text("Fan control is off")
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
            Spacer()
            Button("Set up…") { isCollapsed = false }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(theme.teal)
                    .frame(width: 36, height: 36)
                    .background(theme.soft(theme.teal))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(explanation)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if state == .needsInstall {
                VStack(alignment: .leading, spacing: 5) {
                    checkRow("Only touches fan speed — nothing else")
                    checkRow("Fans go back to automatic when you quit")
                    checkRow("Remove it anytime in Settings")
                }
                .padding(.leading, 48)
            }

            HStack(spacing: 14) {
                if isBusy {
                    ProgressView().controlSize(.small)
                    Text(state == .needsApproval ? "Waiting…" : "Installing…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                } else if let action {
                    Button(action.label, action: action.perform)
                        .buttonStyle(PrimaryButtonStyle(color: theme.teal))
                    Button("Not now") { isCollapsed = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                }
            }
            .padding(.leading, 48)
        }
        .padding(16)
    }

    private func checkRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(theme.green)
                .frame(width: 15)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)
        }
    }

    // MARK: - Copy

    private struct Action {
        let label: String
        let perform: () -> Void
    }

    private var icon: String {
        switch state {
        case .needsApproval: return "hand.raised.fill"
        case .unresponsive: return "arrow.clockwise"
        default: return "fan.fill"
        }
    }

    private var title: String {
        switch state {
        case .checking: return "Checking fan control…"
        case .running: return "Fan control is on"
        case .needsApproval: return "Almost there — approve in System Settings"
        case .needsInstall: return "Want cooler, quieter fans?"
        case .needsUpdate: return "Fan control needs a quick update"
        case .unresponsive: return "Fan control isn’t responding"
        }
    }

    private var explanation: String {
        switch state {
        case .checking, .running:
            return ""
        case .needsApproval:
            return "Turn on ChillMac under Login Items & Extensions › Allow in the Background. ChillMac notices as soon as you do."
        case .needsInstall:
            return "Monitoring works as-is. To change fan speeds, ChillMac needs a one-time permission."
        case .needsUpdate:
            return "The installed helper is from an older version of ChillMac."
        case .unresponsive:
            return "The helper is installed but not answering. Reinstalling usually fixes this."
        }
    }

    private var action: Action? {
        switch state {
        case .checking, .running:
            return nil
        case .needsApproval:
            return Action(label: "Open Login Items", perform: onOpenLoginItems)
        case .needsInstall:
            return Action(label: "Set up fan control", perform: onInstall)
        case .needsUpdate:
            return Action(label: "Update", perform: onInstall)
        case .unresponsive:
            return Action(label: "Reinstall", perform: onInstall)
        }
    }
}
