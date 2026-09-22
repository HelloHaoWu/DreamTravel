import SwiftUI

enum MobileStyle {
    static let accent = Color(red: 0.25, green: 0.63, blue: 0.88)
    static let softBlue = accent.opacity(0.13)
    static let softGreen = Color.green.opacity(0.10)
    static let warning = Color(red: 0.72, green: 0.45, blue: 0.13)
    static let verified = Color(red: 0.16, green: 0.52, blue: 0.33)
}

extension Color {
    init(themeHex: String) {
        let value = UInt64(themeHex, radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

extension PlanAtmosphere {
    var solid: Color { Color(themeHex: tokens.accent) }
    var accent: Color {
        let light = UIColor(solid), dark = UIColor(Color(themeHex: tokens.darkAccent))
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    var wash: Color { accent.opacity(0.10) }
    var glow: Color { Color(themeHex: tokens.glow) }
    var surface: Color {
        let light = UIColor(Color(themeHex: tokens.surface))
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemGroupedBackground : light })
    }
    var titleFont: Font { .system(.title2, design: tokens.editorial ? .serif : .rounded, weight: .bold) }
}

struct MobileCardModifier: ViewModifier {
    @Environment(\.planAtmosphere) private var atmosphere
    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: atmosphere.tokens.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: atmosphere.tokens.corner, style: .continuous)
                    .strokeBorder(atmosphere.accent.opacity(0.09), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
    }
}
extension View { func mobileCard() -> some View { modifier(MobileCardModifier()) } }

private struct PlanAtmosphereKey: EnvironmentKey { static let defaultValue = PlanAtmosphere.classic }
extension EnvironmentValues {
    var planAtmosphere: PlanAtmosphere {
        get { self[PlanAtmosphereKey.self] }
        set { self[PlanAtmosphereKey.self] = newValue }
    }
}

/// Quiet procedural artwork; decorative only, no image downloads or continuous animations.
struct AtmosphereArtwork: View {
    let style: PlanAtmosphere
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            for i in 0..<5 {
                let n = CGFloat(i)
                var path = Path()
                switch style.tokens.motif {
                case "ripple", "orbit":
                    let d = w * (0.25 + n * 0.16)
                    path.addEllipse(in: CGRect(x: w * 0.58 - d / 2, y: h * 0.46 - d / 2, width: d, height: d * (style == .rain ? 0.60 : 1)))
                case "petal", "bloom", "canopy":
                    let x = w * 0.18 + n * w * 0.13
                    path.move(to: CGPoint(x: x, y: h * 0.78))
                    path.addQuadCurve(to: CGPoint(x: x + w * 0.3, y: h * 0.18), control: CGPoint(x: x - w * 0.18, y: h * 0.05))
                    path.addQuadCurve(to: CGPoint(x: x, y: h * 0.78), control: CGPoint(x: x + w * 0.5, y: h * 0.7))
                case "wave", "ribbon":
                    path.move(to: CGPoint(x: 0, y: h * 0.3 + n * 15))
                    path.addCurve(to: CGPoint(x: w, y: h * 0.6 + n * 12), control1: CGPoint(x: w * 0.35, y: -n * 8), control2: CGPoint(x: w * 0.65, y: h + n * 9))
                case "horizon":
                    path.addEllipse(in: CGRect(x: w * 0.35, y: h * 0.15, width: w * 0.4, height: w * 0.4))
                    path.move(to: CGPoint(x: w * 0.1, y: h * 0.58 + n * 14))
                    path.addLine(to: CGPoint(x: w, y: h * 0.58 + n * 14))
                case "arch":
                    path.addRoundedRect(in: CGRect(x: n * 15, y: n * 10, width: w - n * 30, height: h), cornerSize: CGSize(width: w * 0.5, height: h * 0.5))
                case "paper", "grid":
                    path.addRect(CGRect(x: 14 + n * 18, y: 8 + n * 16, width: w * 0.6, height: h * 0.68))
                default:
                    path.move(to: CGPoint(x: w * 0.55, y: n * 16))
                    path.addLine(to: CGPoint(x: w - n * 15, y: h * 0.75))
                    path.addLine(to: CGPoint(x: n * 14, y: h * 0.6))
                    path.closeSubpath()
                }
                context.stroke(path, with: .color(style.accent.opacity(0.13)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct AtmosphereBackground: View {
    @Environment(\.planAtmosphere) private var atmosphere
    @AppStorage("appearance.softTransitions") private var usesTransitions = true
    @AppStorage("appearance.planAtmosphere") private var usesAtmosphere = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Animate only the background colors. Content and card geometry update immediately.
            LinearGradient(colors: [atmosphere.glow.opacity(0.3), atmosphere.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(atmosphere.surface)
                .animation(usesAtmosphere && usesTransitions && !reduceMotion ? .easeOut(duration: 0.22) : nil, value: atmosphere)
            AtmosphereArtwork(style: atmosphere)
                .frame(width: 240, height: 240)
                .padding(.top, 70)
                .transaction { $0.animation = nil }
        }
        .ignoresSafeArea()
    }
}
