import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(eyebrow: "Power of AI Agents",
                             title: prefs.text("Definições", "Settings"),
                             subtitle: prefs.text("Idioma, aparência e arranque.", "Language, appearance and launch."))

                group(prefs.text("Idioma", "Language"), symbol: "globe") {
                    Picker(prefs.text("Idioma", "Language"), selection: $prefs.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.short).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(prefs.language.title).font(.caption).foregroundStyle(Brand.dim(scheme))
                }

                group(prefs.text("Aparência", "Appearance"), symbol: "paintpalette") {
                    Picker(prefs.text("Aparência", "Appearance"), selection: $prefs.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Label(prefs.appearanceTitle(appearance), systemImage: appearance.symbol).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                group(prefs.text("Arranque", "Launch"), symbol: "sparkles") {
                    Toggle(prefs.text("Mostrar apresentação ao abrir", "Show intro on launch"), isOn: $prefs.showSplash)
                        .tint(Brand.orange)
                }

                VStack(spacing: 14) {
                    LogoMark(size: 96)
                    Text("Power of AI Agents").font(.system(.headline, design: .rounded, weight: .bold))
                    Text(versionText).font(.caption.monospaced()).foregroundStyle(Brand.faint(scheme))
                    CreditsView()
                    Link(destination: Self.privacyURL) {
                        Label(prefs.text("Política de privacidade", "Privacy policy"), systemImage: "hand.raised")
                    }
                    .font(.footnote.weight(.semibold))
                    .tint(Brand.accent(scheme))
                }
                .frame(maxWidth: .infinity)
                .card(padding: 20)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
    }

    static let privacyURL = URL(string: "https://github.com/VidiPT89/PowerOfAIAgents/blob/main/PRIVACY.md")!

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return prefs.text("Versão \(version)", "Version \(version)")
    }

    private func group<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Brand.accent(scheme))
            content()
        }
        .card()
    }
}
