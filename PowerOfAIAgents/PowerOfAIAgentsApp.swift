import SwiftUI

@main
struct PowerOfAIAgentsApp: App {
    @StateObject private var prefs = Preferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(prefs)
                .preferredColorScheme(prefs.appearance.scheme)
                .tint(Brand.orange)
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 620)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 820)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var prefs: Preferences
    @State private var splashDone = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if splashDone || !prefs.showSplash {
                MainView().transition(.opacity)
            } else {
                SplashView { withAnimation(.easeInOut(duration: 0.5)) { splashDone = true } }
                    .transition(.opacity)
            }
        }
        .background(Brand.background(scheme).ignoresSafeArea())
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case race, swarm, insights, settings
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .race: "flag.checkered"
        case .swarm: "square.stack.3d.up.fill"
        case .insights: "speedometer"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var race = RaceModel()
    @StateObject private var swarm = SwarmModel()
    @State private var section: AppSection = .race

    var body: some View {
        TabView(selection: $section) {
            RaceView(model: race)
                .tabItem { Label(title(.race), systemImage: AppSection.race.symbol) }
                .tag(AppSection.race)
            SwarmView(model: swarm)
                .tabItem { Label(title(.swarm), systemImage: AppSection.swarm.symbol) }
                .tag(AppSection.swarm)
            InsightsView()
                .tabItem { Label(title(.insights), systemImage: AppSection.insights.symbol) }
                .tag(AppSection.insights)
            SettingsView()
                .tabItem { Label(title(.settings), systemImage: AppSection.settings.symbol) }
                .tag(AppSection.settings)
        }
        .onChange(of: section) { _, new in
            if new != .race { race.pause() }
            if new != .swarm { swarm.pause() }
        }
    }

    private func title(_ section: AppSection) -> String {
        switch section {
        case .race: prefs.text("Corrida", "Race")
        case .swarm: prefs.text("Enxame", "Swarm")
        case .insights: prefs.text("Porquê", "Why")
        case .settings: prefs.text("Definições", "Settings")
        }
    }
}
