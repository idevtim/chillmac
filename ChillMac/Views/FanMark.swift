import SwiftUI

/// The ChillMac fan, drawn from the same geometry as `Resources/AppIcon.svg` so the footer,
/// onboarding and menu bar all match the app icon at any size.
///
/// The source artwork is a 100×100 box: three blades rotated 120° apart around a hub ring.
///
/// Blades and hub are separate parts because they need different fill rules: the hub is a
/// ring filled even-odd, and the blade roots touch it, so filling everything even-odd at
/// once would punch slivers out where they meet.
struct FanMarkShape: Shape {
    enum Part { case blades, hub }
    var part: Part

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .blades:
            for angle in [0.0, 120.0, 240.0] {
                path.addPath(Self.blade, transform: Self.rotation(degrees: angle))
            }
        case .hub:
            path.addPath(Self.hub)
        }
        let scale = min(rect.width, rect.height) / 100
        return path.applying(
            CGAffineTransform(translationX: rect.midX - 50 * scale, y: rect.midY - 50 * scale)
                .scaledBy(x: scale, y: scale)
        )
    }

    private static let blade: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 46.5, y: 41))
        p.addCurve(to: CGPoint(x: 52, y: 7), control1: CGPoint(x: 37, y: 30), control2: CGPoint(x: 38, y: 12))
        p.addCurve(to: CGPoint(x: 70.5, y: 22), control1: CGPoint(x: 64, y: 3), control2: CGPoint(x: 75, y: 12))
        p.addCurve(to: CGPoint(x: 56, y: 42), control1: CGPoint(x: 67, y: 30), control2: CGPoint(x: 60, y: 34))
        p.closeSubpath()
        return p
    }()

    /// Ring with a hole, filled even-odd.
    private static let hub: Path = {
        var p = Path()
        p.addEllipse(in: CGRect(x: 41, y: 41, width: 18, height: 18))
        p.addEllipse(in: CGRect(x: 46.5, y: 46.5, width: 7, height: 7))
        return p
    }()

    private static func rotation(degrees: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: 50, y: 50)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -50, y: -50)
    }
}

/// The coloured mark with its two motion-blur ghost blade sets.
struct FanMarkView: View {
    var size: CGFloat = 16

    static let gradient = LinearGradient(
        colors: [Color(red: 0.357, green: 0.890, blue: 0.941), Color(red: 0.188, green: 0.820, blue: 0.345)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            ghost(degrees: -28, opacity: 0.28)
            ghost(degrees: -14, opacity: 0.5)
            FanMarkShape(part: .blades)
                .fill(Self.gradient)
            FanMarkShape(part: .hub)
                .fill(Self.gradient, style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func ghost(degrees: Double, opacity: Double) -> some View {
        FanMarkShape(part: .blades)
            .fill(Self.gradient)
            .rotationEffect(.degrees(degrees))
            .opacity(opacity)
    }
}

extension NSImage {
    /// Solid fan for the status item. A template image, so macOS tints it for the menu bar
    /// appearance and wallpaper.
    static func fanMarkTemplate(pointSize: CGFloat = 16, accessibilityDescription: String = "ChillMac") -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(FanMarkShape(part: .blades).path(in: rect).cgPath)
            context.fillPath()
            context.addPath(FanMarkShape(part: .hub).path(in: rect).cgPath)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
