import SwiftUI

struct AppTheme {
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
