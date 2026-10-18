import SwiftUI

struct AppTheme {
    let isLight: Bool
    let bgGradientTop: Color
    let bgGradientBottom: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textQuaternary: Color
    let textSubtle: Color

    let cardBg: Color
    let cardBgSecondary: Color
    let cardBgClickable: Color
    let cardBgHover: Color
    let footerBg: Color

    let divider: Color
    let dividerSubtle: Color
    let gridLine: Color
    let ringTrack: Color

    static let dark = AppTheme(
        isLight: false,
        bgGradientTop: Color(red: 0.06, green: 0.12, blue: 0.20),
        bgGradientBottom: Color(red: 0.04, green: 0.08, blue: 0.14),
        textPrimary: .white,
        textSecondary: .white.opacity(0.6),
        textTertiary: .white.opacity(0.5),
        textQuaternary: .white.opacity(0.4),
        textSubtle: .white.opacity(0.3),
        cardBg: Color.white.opacity(0.07),
        cardBgSecondary: Color.white.opacity(0.06),
        cardBgClickable: Color.white.opacity(0.10),
        cardBgHover: Color.white.opacity(0.14),
        footerBg: Color.black.opacity(0.25),
        divider: Color.white.opacity(0.1),
        dividerSubtle: Color.white.opacity(0.06),
        gridLine: Color.white.opacity(0.06),
        ringTrack: Color.white.opacity(0.1)
    )

    static let light = AppTheme(
        isLight: true,
        bgGradientTop: Color(red: 0.94, green: 0.95, blue: 0.97),
        bgGradientBottom: Color(red: 0.89, green: 0.91, blue: 0.94),
        textPrimary: Color(red: 0.08, green: 0.08, blue: 0.10),
        textSecondary: Color(red: 0.25, green: 0.27, blue: 0.30),
        textTertiary: Color(red: 0.35, green: 0.37, blue: 0.40),
        textQuaternary: Color(red: 0.45, green: 0.47, blue: 0.50),
        textSubtle: Color(red: 0.60, green: 0.62, blue: 0.65),
        cardBg: Color.white.opacity(0.75),
        cardBgSecondary: Color.white.opacity(0.60),
        cardBgClickable: Color.white.opacity(0.85),
        cardBgHover: Color.white.opacity(0.95),
        footerBg: Color.black.opacity(0.08),
        divider: Color.black.opacity(0.12),
        dividerSubtle: Color.black.opacity(0.06),
        gridLine: Color.black.opacity(0.08),
        ringTrack: Color.black.opacity(0.10)
    )

    static func forScheme(_ scheme: ColorScheme) -> AppTheme {
        scheme == .dark ? .dark : .light
    }

    // MARK: - Accents
    //
    // System colours in dark mode. In light mode each is darkened so it still reads as text
    // on the pale gradient, the same reasoning the old `perfAccentColor` applied to orange.

    var green: Color { isLight ? Color(red: 0.118, green: 0.620, blue: 0.275) : Color(red: 0.188, green: 0.820, blue: 0.345) }
    var teal: Color { isLight ? Color(red: 0.055, green: 0.592, blue: 0.678) : Color(red: 0.251, green: 0.784, blue: 0.878) }
    var blue: Color { isLight ? Color(red: 0.0, green: 0.478, blue: 1.0) : Color(red: 0.039, green: 0.518, blue: 1.0) }
    var yellow: Color { isLight ? Color(red: 0.722, green: 0.525, blue: 0.0) : Color(red: 1.0, green: 0.839, blue: 0.039) }
    var orange: Color { isLight ? Color(red: 0.800, green: 0.451, blue: 0.0) : Color(red: 1.0, green: 0.624, blue: 0.039) }
    var red: Color { isLight ? Color(red: 0.898, green: 0.208, blue: 0.169) : Color(red: 1.0, green: 0.271, blue: 0.227) }

    /// Accent at the low opacity used for icon chips and selected chip backgrounds.
    func soft(_ accent: Color) -> Color { accent.opacity(isLight ? 0.12 : 0.15) }

    /// Hairline between rows inside a card.
    var rowDivider: Color { isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.08) }
    /// Unfilled part of a progress bar.
    var track: Color { isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.10) }
    /// Background of segmented controls and unselected chips.
    var segmentedBg: Color { isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08) }

    /// `<55` green, `<70` yellow, `<85` orange, else red.
    func tempColor(_ celsius: Double) -> Color {
        if celsius >= 85 { return red }
        if celsius >= 70 { return orange }
        if celsius >= 55 { return yellow }
        return green
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [bgGradientTop, bgGradientBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dark
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Themed Wrapper

struct ThemedView<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    private var resolvedTheme: AppTheme {
        AppTheme.forScheme(settings.preferredColorScheme ?? colorScheme)
    }

    var body: some View {
        content
            .environment(\.theme, resolvedTheme)
            .preferredColorScheme(settings.preferredColorScheme)
    }
}
