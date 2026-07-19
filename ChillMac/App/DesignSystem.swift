import SwiftUI

/// Layout tokens only — colors come from system hierarchical styles + AccentColor.
enum DesignSystem {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    enum TypeScale {
        static let title: Font = .system(size: 22, weight: .bold)
        static let headline: Font = .system(size: 14, weight: .semibold)
        static let body: Font = .system(size: 13, weight: .medium)
        static let caption: Font = .system(size: 11)
        static let mono: Font = .system(size: 12, weight: .semibold, design: .monospaced)
        static let section: Font = .system(size: 13, weight: .semibold)
    }
}

private struct DesignSystemKey: EnvironmentKey {
    static let defaultValue = DesignSystem.self
}

extension EnvironmentValues {
    var designSystem: DesignSystem.Type {
        get { self[DesignSystemKey.self] }
        set { self[DesignSystemKey.self] = newValue }
    }
}

extension View {
    /// Native card surface using system material (not custom RGB fills).
    func chillCard(padding: CGFloat = DesignSystem.Space.md) -> some View {
        self
            .padding(padding)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
    }

    func chillSectionHeader() -> some View {
        self
            .font(DesignSystem.TypeScale.section)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.leading, DesignSystem.Space.xs)
            .padding(.top, DesignSystem.Space.xs)
    }
}

/// Applies preferred color scheme from settings without a custom Theme color bag.
struct AppearanceHost<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    let content: Content

    init(content: Content) {
        self.content = content
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .preferredColorScheme(settings.preferredColorScheme)
    }
}
