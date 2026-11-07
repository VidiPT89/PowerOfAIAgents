import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case portuguese = "pt-PT", english = "en"
    var id: String { rawValue }
    var short: String { self == .portuguese ? "PT" : "EN" }
    var title: String { self == .portuguese ? "Português (Portugal)" : "English" }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults

    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var showSplash: Bool { didSet { defaults.set(showSplash, forKey: "showSplash") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial: AppLanguage = Locale.preferredLanguages.first?.hasPrefix("pt") == true ? .portuguese : .english
        language = defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? initial
        appearance = defaults.string(forKey: "appearance").flatMap(AppAppearance.init(rawValue:)) ?? .system
        showSplash = defaults.object(forKey: "showSplash") as? Bool ?? true
    }

    func text(_ pt: String, _ en: String) -> String { language == .portuguese ? pt : en }

    func appearanceTitle(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: text("Sistema", "System")
        case .light: text("Claro", "Light")
        case .dark: text("Escuro", "Dark")
        }
    }
}

/// iVidi.dev identity: orange, burnt amber and near-black.
enum Brand {
    static let orange = Color(hex: 0xF99C00)
    static let amber = Color(hex: 0xFCBB00)
    static let deepOrange = Color(hex: 0xDD7400)
    static let danger = Color(hex: 0xEF4444)
    static let ok = Color(hex: 0x22C55E)
    static let cloud = Color(hex: 0x7C8BA1)
    static let gradient = LinearGradient(colors: [amber, orange, deepOrange], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x0A0A0F) : Color(hex: 0xF7F3EC) }
    static func panel(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x0D0D18) : Color(hex: 0xFFFCF7) }
    static func panel2(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x12121F) : Color(hex: 0xF1EBE1) }
    static func text(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xE2E8F0) : Color(hex: 0x16120D) }
    static func dim(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x94A3B8) : Color(hex: 0x5E5548) }
    static func faint(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x5B6474) : Color(hex: 0x9A8F80) }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? amber : deepOrange }
    static func stroke(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08) }

    /// One colour per racing agent, also used by the swarm cursors.
    static let agentColors: [Color] = [
        Color(hex: 0xF99C00), Color(hex: 0x38BDF8), Color(hex: 0xA3A3A3), Color(hex: 0xE879F9),
        Color(hex: 0x22C55E), Color(hex: 0xEF4444), Color(hex: 0xFCBB00), Color(hex: 0x818CF8),
    ]
    static func agentColor(_ index: Int) -> Color { agentColors[index % agentColors.count] }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
