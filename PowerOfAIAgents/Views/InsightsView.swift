import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var lab: AgentLab
    @Environment(\.colorScheme) private var scheme
    @State private var escalation = 0.1

    private var profiles: [AgentProfile] { lab.profiles }
    private var segments: [(KeyPath<LatencyBreakdown, Double>, String, String, Color)] {[
        (\.tcp, "TCP", "TCP", Color(hex: 0x64748B)),
        (\.tls, "TLS", "TLS", Color(hex: 0x94A3B8)),
        (\.routing, "Rota até ao data center", "Route to the data centre", Brand.cloud),
        (\.queue, "Fila no servidor", "Server queue", Color(hex: 0xA78BFA)),
        (\.inference, "Inferência", "Inference", Brand.orange),
    ]}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Anatomia da latência", "Latency anatomy"),
                    title: prefs.text("Onde vão os milissegundos", "Where the milliseconds go"),
                    subtitle: prefs.text(
                        "Uma decisão na cloud paga a viagem antes de o modelo começar a pensar. No dispositivo, só se paga a inferência.",
                        "A cloud decision pays for the trip before the model even starts thinking. On the device, you only pay for inference."))
                anatomy
                cascade
                VStack(alignment: .leading, spacing: 12) {
                    lesson("network", prefs.text("A rede cobra sempre", "The network always charges"),
                           prefs.text("Handshake TCP, negociação TLS, rotas transoceânicas e filas no gateway somam centenas de milissegundos. Com memória unificada, o modelo local lê os dados sem sair da máquina.",
                                      "TCP handshake, TLS negotiation, ocean-crossing routes and gateway queues add up to hundreds of milliseconds. With unified memory, a local model reads the data without leaving the machine."))
                    lesson("scope", prefs.text("A ferramenta certa para a tarefa", "The right tool for the job"),
                           prefs.text("Dizer se uma ligação é relevante não precisa de gerar texto palavra a palavra. Um encoder faz uma única passagem e devolve uma probabilidade em dezenas de milissegundos.",
                                      "Deciding whether a link is relevant does not need text generated word by word. An encoder does a single pass and returns a probability in tens of milliseconds."))
                    lesson("square.stack.3d.down.right", prefs.text("Arquitetura em cascata", "Cascade architecture"),
                           prefs.text("Modelos pequenos no dispositivo filtram o grosso das decisões. Os modelos grandes na cloud só entram quando o local tem pouca confiança.",
                                      "Small on-device models filter the bulk of decisions. Large cloud models only step in when the local one has low confidence."))
                }
                .card()
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
    }

    private var anatomy: some View {
        let longest = profiles.map(\.typical.total).max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(profiles) { profile in
                let typical = profile.typical
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(Brand.agentColor(profile.id)).frame(width: 9, height: 9)
                        Text(profile.name).font(.subheadline.weight(.semibold))
                        KindTag(kind: profile.kind)
                        Text(profile.family == .encoder ? prefs.text("encoder · \(profile.size)", "encoder · \(profile.size)") : prefs.text("generativo · \(profile.size)", "generative · \(profile.size)"))
                            .font(.caption2.monospaced())
                            .foregroundStyle(Brand.dim(scheme))
                        Spacer()
                        Text(typical.total.milliseconds).font(.system(.subheadline, design: .monospaced, weight: .bold))
                    }
                    GeometryReader { proxy in
                        HStack(spacing: 1) {
                            ForEach(segments.indices, id: \.self) { i in
                                let value = typical[keyPath: segments[i].0]
                                if value > 0 {
                                    Rectangle().fill(segments[i].3)
                                        .frame(width: max(2, proxy.size.width * value / longest))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 14)
                }
            }
            FlowLegend(items: segments.map { (prefs.text($0.1, $0.2), $0.3) })
        }
        .card()
    }

    @ViewBuilder private var cascade: some View {
        // The fastest local agent filters, the slowest cloud agent takes what it escalates.
        let localAgent = profiles.filter { $0.kind == .local }.min { $0.typical.total < $1.typical.total }
        let cloudAgent = profiles.filter { $0.kind == .cloud }.max { $0.typical.total < $1.typical.total }
        VStack(alignment: .leading, spacing: 12) {
            Text(prefs.text("Simulador de cascata", "Cascade simulator"))
                .font(.system(.headline, design: .rounded, weight: .bold))
            if let localAgent, let cloudAgent {
                cascadeBody(local: localAgent, cloud: cloudAgent)
            } else {
                Label(prefs.text("A cascata precisa de pelo menos um agente local e um na cloud. Muda o tipo de um agente no laboratório da Corrida.",
                                 "A cascade needs at least one local and one cloud agent. Change an agent's type in the Race lab."),
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Brand.dim(scheme))
            }
        }
        .card()
    }

    @ViewBuilder private func cascadeBody(local localAgent: AgentProfile, cloud cloudAgent: AgentProfile) -> some View {
        let mixed = Cascade.averageLatency(local: localAgent.typical, cloud: cloudAgent.typical, escalation: escalation)
        let cloudOnly = cloudAgent.typical.total
        let faster = mixed <= cloudOnly
        Text(prefs.text("\(localAgent.name) decide tudo localmente e só envia para \(cloudAgent.name) a percentagem de casos com pouca confiança.",
                        "\(localAgent.name) decides everything locally and only forwards the low-confidence share to \(cloudAgent.name)."))
            .font(.subheadline)
            .foregroundStyle(Brand.dim(scheme))
        HStack {
            Text(prefs.text("Enviado para a cloud", "Sent to the cloud")).font(.caption)
            Slider(value: $escalation, in: 0...1)
            Text("\(Int(escalation * 100))%").font(.system(.subheadline, design: .monospaced, weight: .semibold)).frame(width: 48, alignment: .trailing)
        }
        HStack(spacing: 12) {
            result(prefs.text("Só cloud", "Cloud only"), cloudOnly.milliseconds, Brand.cloud)
            result(prefs.text("Cascata", "Cascade"), mixed.milliseconds, Brand.orange)
            if faster {
                result(prefs.text("Mais rápido", "Faster"), String(format: "×%.1f", cloudOnly / max(mixed, 1)), Brand.ok)
            } else {
                result(prefs.text("Mais lento", "Slower"), String(format: "×%.1f", mixed / max(cloudOnly, 1)), Brand.danger)
            }
        }
    }

    private func result(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(Brand.dim(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func lesson(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Brand.accent(scheme))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Brand.text(scheme))
                Text(body).font(.subheadline).foregroundStyle(Brand.dim(scheme)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FlowLegend: View {
    @Environment(\.colorScheme) private var scheme
    let items: [(String, Color)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(items[i].1).frame(width: 10, height: 10)
                    Text(items[i].0).font(.caption).foregroundStyle(Brand.dim(scheme))
                }
            }
        }
    }
}
