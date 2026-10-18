import SwiftUI

// Small building blocks shared by the popover, Settings, detail panels and onboarding.

/// Thin rounded bar: track plus accent fill.
struct ProgressBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}

/// 1px hairline between rows inside a card.
struct CardDivider: View {
    var leadingInset: CGFloat = 0
    @Environment(\.theme) private var theme

    var body: some View {
        theme.rowDivider
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// Title, optional caption and a trailing control, padded as a card row.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var caption: Text? = nil
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                if let caption {
                    caption
                        .font(.system(size: 11))
                        .foregroundColor(theme.textQuaternary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// `SettingsRow` with a small switch.
struct SwitchRow: View {
    let title: String
    var caption: Text? = nil
    @Binding var isOn: Bool
    var tint: Color

    var body: some View {
        SettingsRow(title: title, caption: caption) {
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tint)
                .labelsHidden()
        }
    }
}

/// Filled teal button used for the main action of a card or onboarding step.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color
    var horizontalPadding: CGFloat = 14
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1))
            .cornerRadius(cornerRadius)
            .contentShape(Rectangle())
    }
}

// MARK: - Detail panels

/// Chrome every detail panel shares: gradient, 24pt title, scrolling content, resize handle.
/// The close button is overlaid by `DetailPanelController`.
struct DetailPanelScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @State private var panelHeight: CGFloat = CGFloat(AppSettings.shared.detailPanelHeight)

    var body: some View {
        ZStack {
            theme.backgroundGradient

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                    .padding(.leading, 20)
                    .padding(.trailing, 56)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ScrollView(.vertical, showsIndicators: AppSettings.shared.showScrollIndicators) {
                    VStack(alignment: .leading, spacing: 14) {
                        content()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                PanelResizeHandle(panelHeight: $panelHeight) {
                    AppSettings.shared.detailPanelHeight = Double(panelHeight)
                }
            }
        }
        .frame(width: 370, height: panelHeight)
    }
}

/// Plain-language status line, then a hero number with its context.
struct PanelHero: View {
    let status: String
    let statusColor: Color
    let value: String
    let context: String
    var trailing: String? = nil

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(statusColor)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                Text(context)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textQuaternary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Icon, title with optional caption, and a coloured value. One row of a panel card.
struct PanelValueRow<Accessory: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var caption: String? = nil
    let value: String
    var valueColor: Color? = nil
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textQuaternary)
                    }
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(valueColor ?? theme.textSecondary)
            }
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension PanelValueRow where Accessory == EmptyView {
    init(icon: String, iconColor: Color, title: String, caption: String? = nil, value: String, valueColor: Color? = nil) {
        self.init(icon: icon, iconColor: iconColor, title: title, caption: caption, value: value, valueColor: valueColor) { EmptyView() }
    }
}

/// One row of a "Using the most" list. The bar is relative to the top consumer.
struct TopConsumerRow: View {
    let icon: NSImage?
    let name: String
    let fraction: Double
    let value: String
    let color: Color

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .cornerRadius(5)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 18))
                        .foregroundColor(color.opacity(0.5))
                }
            }
            .frame(width: 22, height: 22)

            Text(name)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 110, alignment: .leading)

            ProgressBar(fraction: fraction, color: color, height: 4)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

/// Rounded card background used throughout.
extension View {
    func cardBackground(_ theme: AppTheme, radius: CGFloat = 12) -> some View {
        background(theme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
