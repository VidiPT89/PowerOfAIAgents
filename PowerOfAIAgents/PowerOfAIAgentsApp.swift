import SwiftUI

@main
struct PowerOfAIAgentsApp: App {
    @StateObject private var prefs = Preferences()
    @StateObject private var lab = AgentLab()
    @StateObject private var history = HistoryStore()
    @StateObject private var connection = ConnectionMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(prefs)
                .environmentObject(lab)
                .environmentObject(history)
                .environmentObject(connection)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if splashDone || !prefs.showSplash {
                MainView()
                    .onAppear { splashDone = true }
                    .transition(.opacity)
            } else {
                SplashView { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { splashDone = true } }
                    .transition(.opacity)
            }
        }
        .background(Brand.background(scheme).ignoresSafeArea())
    }
}

enum AppSection {
    case measure, endpoint, text, history, simulate
    var symbol: String {
        switch self {
        case .measure: "stopwatch"
        case .endpoint: "bolt.horizontal.fill"
        case .text: "text.magnifyingglass"
        case .history: "clock.arrow.circlepath"
        case .simulate: "flag.checkered"
        }
    }
}

enum Simulation: String, CaseIterable {
    case race, swarm, insights
}

struct MainView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var lab: AgentLab
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var connection: ConnectionMonitor
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var race = RaceModel()
    @StateObject private var swarm = SwarmModel()
    @StateObject private var measure = MeasureModel()
    @StateObject private var endpoint = EndpointModel()
    @StateObject private var textLab = TextLabModel()
    @State private var section: AppSection = .measure
    @State private var simulation: Simulation = .race
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $section) {
            MeasureView(model: measure)
                .tabItem { Label(title(.measure), systemImage: AppSection.measure.symbol) }
                .tag(AppSection.measure)
            EndpointView(model: endpoint)
                .tabItem { Label(title(.endpoint), systemImage: AppSection.endpoint.symbol) }
                .tag(AppSection.endpoint)
            TextLabView(model: textLab)
                .tabItem { Label(title(.text), systemImage: AppSection.text.symbol) }
                .tag(AppSection.text)
            HistoryView()
                .tabItem { Label(title(.history), systemImage: AppSection.history.symbol) }
                .tag(AppSection.history)
            SimulateView(simulation: $simulation, race: race, swarm: swarm)
                .tabItem { Label(title(.simulate), systemImage: AppSection.simulate.symbol) }
                .tag(AppSection.simulate)
        }
        .environment(\.showSettings, { showSettings = true })
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(prefs)
                .environmentObject(history)
                .preferredColorScheme(prefs.appearance.scheme)
        }
        .onAppear {
            race.configure(lab.profiles)
            // Both objects live as long as the app, so a strong capture is fine.
            let history = history, connection = connection
            measure.onFinish = { record in
                var record = record
                record.connection = connection.current
                history.add(record)
            }
            endpoint.onFinish = { result in
                guard !result.responses.isEmpty else { return }
                history.add(HistoryRecord(endpoint: result, connection: connection.current))
            }
        }
        .onChange(of: lab.tunings) { _, _ in race.configure(lab.profiles) }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app pauses the simulations and stops measurements instead of letting them run unseen.
            if phase == .background {
                race.pause()
                swarm.pause()
                measure.cancel()
                endpoint.cancel()
                textLab.cancel()
            }
        }
        .onDisappear {
            race.pause()
            swarm.pause()
            measure.cancel()
            endpoint.cancel()
            textLab.cancel()
        }
        .onChange(of: section) { _, new in pauseHidden(section: new, simulation: simulation) }
        .onChange(of: simulation) { _, new in pauseHidden(section: section, simulation: new) }
    }

    private func pauseHidden(section: AppSection, simulation: Simulation) {
        if section != .simulate || simulation != .race { race.pause() }
        if section != .simulate || simulation != .swarm { swarm.pause() }
    }

    private func title(_ section: AppSection) -> String {
        switch section {
        case .measure: prefs.text("Medir", "Measure")
        case .endpoint: prefs.text("Testar API", "Test API")
        case .text: prefs.text("Texto", "Text")
        case .history: prefs.text("Histórico", "History")
        case .simulate: prefs.text("Simular", "Simulate")
        }
    }
}

/// The three illustrative simulations behind one tab, clearly separated from the real tools.
struct SimulateView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    @Binding var simulation: Simulation
    @ObservedObject var race: RaceModel
    @ObservedObject var swarm: SwarmModel

    var body: some View {
        VStack(spacing: 0) {
            Picker(prefs.text("Simulação", "Simulation"), selection: $simulation) {
                Text(prefs.text("Corrida", "Race")).tag(Simulation.race)
                Text(prefs.text("Enxame", "Swarm")).tag(Simulation.swarm)
                Text(prefs.text("Porquê", "Why")).tag(Simulation.insights)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            switch simulation {
            case .race: RaceView(model: race)
            case .swarm: SwarmView(model: swarm)
            case .insights: InsightsView()
            }
        }
        .background(Brand.background(scheme).ignoresSafeArea())
    }
}
