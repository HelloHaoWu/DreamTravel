import SwiftUI

enum DreamStyle {
    static let accent = Color(red: 0.29, green: 0.69, blue: 0.91)
    static let active = Color.primary
    static let softBlue = accent.opacity(0.18)
    static let softGreen = Color.green.opacity(0.12)
    static let verified = Color(red: 0.22, green: 0.48, blue: 0.35)
    static let warning = Color(red: 0.61, green: 0.40, blue: 0.15)
    static let contentWidth: CGFloat = 600
}

struct DreamBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [DreamStyle.accent.opacity(0.22), DreamStyle.accent.opacity(0.05), .clear],
                center: UnitPoint(x: 0.55, y: 0.0),
                startRadius: 10,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 38)
            .background(
                Capsule()
                    .fill(DreamStyle.accent.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.36))
            )
            .contentShape(Rectangle())
    }
}

struct ConditionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.055))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func dreamCard(cornerRadius: CGFloat = 11) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.055), radius: 14, y: 5)
        )
    }
}
