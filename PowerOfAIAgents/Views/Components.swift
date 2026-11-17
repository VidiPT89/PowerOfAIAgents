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

/// Opens the settings sheet from any screen header.
private struct ShowSettingsKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var showSettings: (@MainActor () -> Void)? {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}

struct ScreenHeader: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.showSettings) private var showSettings
    @EnvironmentObject private var prefs: Preferences
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
            if let showSettings {
                Button { showSettings() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(Brand.accent(scheme))
                        .frame(width: 40, height: 40)
                        .background(Brand.panel2(scheme), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(prefs.text("Definições", "Settings"))
            }
        }
    }
}

/// A small labelled value tile used by the tool screens.
struct StatTile: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(tint ?? Brand.text(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Brand.dim(scheme)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Section title inside a card.
struct CardTitle: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var detail: String? = nil
    let symbol: String
    var active = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Brand.accent(scheme))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                if let detail { Text(detail).font(.caption2.monospaced()).foregroundStyle(Brand.faint(scheme)) }
            }
            Spacer()
            if active { ProgressView().controlSize(.small) }
        }
    }
}

/// Wi-Fi, mobile data… shown next to every measurement.
struct ConnectionBadge: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let kind: ConnectionKind

    var body: some View {
        Label(prefs.connectionName(kind), systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(kind == .offline ? Brand.danger : Brand.accent(scheme))
            .background(Brand.panel2(scheme), in: Capsule())
    }
}

extension ConnectionKind {
    var symbol: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .wired: "cable.connector"
        case .other: "network"
        case .offline: "wifi.slash"
        case .unknown: "questionmark.circle"
        }
    }
}

extension Preferences {
    func connectionName(_ kind: ConnectionKind) -> String {
        switch kind {
        case .wifi: "Wi-Fi"
        case .cellular: text("Dados móveis", "Mobile data")
        case .wired: text("Cabo", "Wired")
        case .other: text("Outra rede", "Other network")
        case .offline: text("Sem rede", "Offline")
        case .unknown: text("Rede desconhecida", "Unknown network")
        }
    }

    /// A number in the app's language.
    func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: language.rawValue)))
    }

    var locale: Locale { Locale(identifier: language.rawValue) }
}

extension View {
    /// Plain text entry for addresses and terms: no capitals or corrections on iOS.
    func plainEntry(url: Bool = false) -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(url ? .URL : .default)
        #else
        self.autocorrectionDisabled()
        #endif
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
