import SwiftUI

struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Brand.stroke(scheme)))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

struct ScreenHeader: View {
    @Environment(\.colorScheme) private var scheme
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Brand.accent(scheme))
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.text(scheme))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Brand.dim(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Brand.gradient, in: Capsule())
            .shadow(color: Brand.orange.opacity(0.35), radius: configuration.isPressed ? 2 : 8, y: 2)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(Brand.text(scheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Brand.panel2(scheme), in: Capsule())
            .overlay(Capsule().stroke(Brand.stroke(scheme)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct KindTag: View {
    @EnvironmentObject private var prefs: Preferences
    let kind: AgentKind
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind == .local ? "cpu" : "cloud")
            Text(kind == .local ? "local" : prefs.text("nuvem", "cloud"))
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(kind == .local ? Brand.orange : Brand.cloud)
        .background((kind == .local ? Brand.orange : Brand.cloud).opacity(0.14), in: Capsule())
    }
}

extension Double {
    /// Milliseconds with as many decimals as a value that small needs (on-device models can take microseconds).
    var milliseconds: String {
        switch self {
        case 100...: String(format: "%.0f ms", self)
        case 1..<100: String(format: "%.1f ms", self)
        case 0.01..<1: String(format: "%.2f ms", self)
        case 0: "0 ms"
        default: String(format: "%.0f µs", self * 1000)
        }
    }
}
