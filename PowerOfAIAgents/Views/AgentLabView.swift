import SwiftUI

/// The user's agent settings, saved between launches and shared by the race and the latency screen.
@MainActor
final class AgentLab: ObservableObject {
    private let defaults: UserDefaults
    private static let key = "agentTunings"

    @Published var tunings: [AgentTuning] {
        didSet {
            guard tunings != oldValue else { return }
            if let data = try? JSONEncoder().encode(tunings) { defaults.set(data, forKey: Self.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Anything unreadable or from a different line-up falls back to the defaults.
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([AgentTuning].self, from: data),
           saved.count == AgentTuning.defaults.count {
            tunings = saved.map(\.clamped)
        } else {
            tunings = AgentTuning.defaults
        }
    }

    var profiles: [AgentProfile] { AgentProfile.lineup(tuned: tunings) }
    var isCustomised: Bool { tunings != AgentTuning.defaults }

    func reset() { tunings = AgentTuning.defaults }
    func reset(agent id: Int) { tunings[id] = AgentTuning.defaults[id] }
}

struct AgentLabView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var lab: AgentLab
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let duration: Double
    let walkTime: Double

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(prefs.text(
                        "Muda o tipo, a latência e a precisão de cada agente e vê como o placar muda. As alterações ficam guardadas e a corrida recomeça com elas.",
                        "Change each agent's type, latency and accuracy and watch the scoreboard change. Your settings are saved and the race restarts with them."))
                        .font(.subheadline)
                        .foregroundStyle(Brand.dim(scheme))
                    ForEach(AgentProfile.lineup) { profile in
                        AgentTuningCard(profile: profile, tuning: $lab.tunings[profile.id], duration: duration, walkTime: walkTime) {
                            lab.reset(agent: profile.id)
                        }
                    }
                    Button(role: .destructive) {
                        withAnimation { lab.reset() }
                    } label: {
                        Label(prefs.text("Repor todos os valores", "Restore all defaults"), systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!lab.isCustomised)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.background(scheme).ignoresSafeArea())
            .navigationTitle(prefs.text("Laboratório de agentes", "Agent lab"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(prefs.text("Concluído", "Done")) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }
}

struct AgentTuningCard: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let profile: AgentProfile
    @Binding var tuning: AgentTuning
    let duration: Double
    let walkTime: Double
    let resetAgent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Brand.agentColor(profile.id)).frame(width: 10, height: 10)
                Text(profile.name).font(.system(.headline, design: .rounded, weight: .bold))
                Text(profile.family == .encoder ? "encoder" : prefs.text("generativo", "generative"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(Brand.dim(scheme))
                Spacer()
                if tuning != AgentTuning.defaults[profile.id] {
                    Button(action: resetAgent) {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.accent(scheme))
                    .accessibilityLabel(prefs.text("Repor \(profile.name)", "Restore \(profile.name)"))
                }
            }

            Picker(prefs.text("Onde corre", "Runs on"), selection: $tuning.kind) {
                Label("local", systemImage: "cpu").tag(AgentKind.local)
                Label("cloud", systemImage: "cloud").tag(AgentKind.cloud)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TuningSlider(title: prefs.text("Inferência", "Inference"), value: $tuning.inference,
                         range: AgentTuning.inferenceRange, logarithmic: true, format: { $0.milliseconds })
            if tuning.kind == .cloud {
                TuningSlider(title: prefs.text("Rede (TCP, TLS, rota)", "Network (TCP, TLS, route)"), value: $tuning.network,
                             range: AgentTuning.networkRange, logarithmic: true, format: { $0.milliseconds })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            TuningSlider(title: prefs.text("Fila", "Queue"), value: $tuning.queue,
                         range: AgentTuning.queueRange, logarithmic: false, format: { $0.milliseconds })
            TuningSlider(title: prefs.text("Precisão", "Accuracy"), value: $tuning.accuracy,
                         range: AgentTuning.accuracyRange, logarithmic: false, format: { String(format: "%.0f%%", $0 * 100) })

            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(prefs.text(
                    "≈ \(tuning.typicalTotal.milliseconds) por decisão · ≈ \(tuning.expectedDecisions(duration: duration, walkTime: walkTime)) decisões em \(Int(duration)) s",
                    "≈ \(tuning.typicalTotal.milliseconds) per decision · ≈ \(tuning.expectedDecisions(duration: duration, walkTime: walkTime)) decisions in \(Int(duration)) s"))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Brand.accent(scheme))
        }
        .animation(.easeInOut(duration: 0.2), value: tuning.kind)
        .card()
    }
}

/// A labelled slider; latencies use a logarithmic scale so 10 ms and 1 s are both easy to reach.
struct TuningSlider: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let logarithmic: Bool
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Brand.text(scheme))
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit()).foregroundStyle(Brand.dim(scheme))
            }
            Slider(value: position, in: 0...1)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
        }
    }

    private var position: Binding<Double> {
        Binding(
            get: { TuningScale.position(of: value, in: range, logarithmic: logarithmic) },
            set: { value = TuningScale.value(at: $0, in: range, logarithmic: logarithmic) })
    }
}

enum TuningScale {
    /// Log scales start at 1 so a range that begins at 0 still works.
    static func position(of value: Double, in range: ClosedRange<Double>, logarithmic: Bool) -> Double {
        let v = value.clamped(to: range)
        guard logarithmic else { return (v - range.lowerBound) / (range.upperBound - range.lowerBound) }
        let low = log(max(range.lowerBound, 1)), high = log(range.upperBound)
        return (log(max(v, 1)) - low) / (high - low)
    }

    static func value(at position: Double, in range: ClosedRange<Double>, logarithmic: Bool) -> Double {
        let p = position.clamped(to: 0...1)
        guard logarithmic else { return range.lowerBound + p * (range.upperBound - range.lowerBound) }
        let low = log(max(range.lowerBound, 1)), high = log(range.upperBound)
        return exp(low + p * (high - low)).clamped(to: range)
    }
}
