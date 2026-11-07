import SwiftUI

/// Real measurements on this device: the network to ividi.dev and the on-device models.
@MainActor
final class MeasureModel: ObservableObject {
    enum Step: Equatable { case network, encoder, generative }

    /// Fresh and reused connections measured per run.
    static let networkRounds = 3
    /// Links given to the generative model (it needs about a second each).
    static let generativeLinks = 12

    @Published private(set) var running: Step?
    @Published private(set) var fresh: NetworkSample?
    @Published private(set) var reused: NetworkSample?
    @Published private(set) var networkFailed = false
    @Published private(set) var encoder: ModelRun?
    @Published private(set) var generative: ModelRun?
    @Published private(set) var generativeProgress = 0
    @Published private(set) var generativeError: String?
    @Published private(set) var appliedToLab = false
    private var job: Task<Void, Never>?

    var isRunning: Bool { running != nil }
    var hasResults: Bool { fresh != nil || encoder != nil || generative != nil }

    func measureAll() {
        guard !isRunning else { return }
        appliedToLab = false
        job = Task { [weak self] in
            await self?.measureNetwork()
            await self?.measureEncoder()
            if GenerativeClassifier.unavailableReason == nil { await self?.measureGenerative() }
            self?.running = nil
        }
    }

    func cancel() {
        job?.cancel()
        job = nil
        running = nil
    }

    private func measureNetwork() async {
        running = .network
        networkFailed = false
        var fresh: [NetworkSample] = [], reused: [NetworkSample] = []
        for _ in 0..<Self.networkRounds {
            guard !Task.isCancelled else { return }
            do {
                let pair = try await NetworkProbe.measurePair()
                fresh.append(pair.fresh)
                reused.append(pair.reused)
            } catch {
                networkFailed = fresh.isEmpty
                break
            }
        }
        self.fresh = NetworkSample.average(fresh)
        self.reused = NetworkSample.average(reused)
    }

    private func measureEncoder() async {
        guard !Task.isCancelled else { return }
        running = .encoder
        let links = Article.english.links
        // Off the main thread so the interface stays smooth while it measures.
        encoder = await Task.detached(priority: .userInitiated) { EmbeddingClassifier()?.run(on: links) }.value
    }

    private func measureGenerative() async {
        running = .generative
        generativeError = nil
        generativeProgress = 0
        let links = Array(Article.english.links.prefix(Self.generativeLinks))
        let clock = ContinuousClock()
        var correct = 0, total = 0.0
        for link in links {
            guard !Task.isCancelled else { return }
            do {
                var verdict = false
                let elapsed = try await clock.measure { verdict = try await GenerativeClassifier.isAboutSpiders(link.text) }
                total += elapsed.milliseconds
                if verdict == link.relevant { correct += 1 }
                generativeProgress += 1
            } catch {
                generativeError = error.localizedDescription
                return
            }
        }
        generative = ModelRun(decisions: links.count, correct: correct, totalMilliseconds: total)
    }

    /// Puts the measured numbers into the agent lab: the race then uses this device's real figures.
    func apply(to lab: AgentLab) {
        if let encoder { lab.tunings[0].inference = encoder.averageMilliseconds }
        if let generative { lab.tunings[3].inference = generative.averageMilliseconds }
        if let fresh {
            lab.measuredNetwork = fresh.total
            for i in lab.tunings.indices where lab.tunings[i].kind == .cloud { lab.tunings[i].network = fresh.total }
        }
        lab.tunings = lab.tunings.map(\.clamped)
        appliedToLab = true
    }
}

struct MeasureView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var lab: AgentLab
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: MeasureModel
    @State private var shareImage: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Medição real", "Real measurement"),
                    title: prefs.text("Mede no teu aparelho", "Measure on your device"),
                    subtitle: prefs.text(
                        "Sem simulação: pedidos HTTPS reais a ividi.dev e modelos que correm neste aparelho a classificar as ligações do artigo.",
                        "No simulation: real HTTPS requests to ividi.dev and models running on this device labelling the article's links."))
                controls
                networkCard
                encoderCard
                generativeCard
                if let summary { summaryCard(summary) }
                Text(prefs.text(
                    "A medição só faz pedidos HEAD a ividi.dev e só quando tocas em Medir. Nada é enviado sobre ti nem guardado fora do aparelho.",
                    "Measuring only sends HEAD requests to ividi.dev, and only when you tap Measure. Nothing about you is sent or stored off the device."))
                    .font(.caption)
                    .foregroundStyle(Brand.faint(scheme))
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
        .onChange(of: model.isRunning) { _, running in shareImage = running ? nil : shareCard?.image() }
        .onChange(of: prefs.language) { _, _ in if !model.isRunning { shareImage = shareCard?.image() } }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(alignment: .leading, spacing: 10) { HStack(spacing: 10) { buttons } }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button {
            model.isRunning ? model.cancel() : model.measureAll()
        } label: {
            Label(model.isRunning ? prefs.text("Parar", "Stop") : (model.hasResults ? prefs.text("Medir outra vez", "Measure again") : prefs.text("Medir", "Measure")),
                  systemImage: model.isRunning ? "stop.fill" : "stopwatch")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PrimaryButtonStyle())
        if model.isRunning { ProgressView().controlSize(.small) }
        if let shareImage, !model.isRunning { ShareResultButton(image: shareImage) }
    }

    // MARK: Cards

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(prefs.text("Rede real", "Real network"), detail: "HEAD \(NetworkProbe.url.absoluteString)", symbol: "network", active: model.running == .network)
            if let fresh = model.fresh, let reused = model.reused {
                networkBar(prefs.text("Ligação nova", "New connection"), fresh, longest: max(fresh.total, reused.total))
                networkBar(prefs.text("Ligação reutilizada", "Reused connection"), reused, longest: max(fresh.total, reused.total))
                FlowLegend(items: networkSegments.map { (prefs.text($0.pt, $0.en), $0.color) })
                Text(prefs.text(
                    "Média de \(MeasureModel.networkRounds) ligações novas e \(MeasureModel.networkRounds) reutilizadas. O aperto de mão (DNS, TCP, TLS) custou \(fresh.handshake.milliseconds) e só se paga na ligação nova.",
                    "Average of \(MeasureModel.networkRounds) new and \(MeasureModel.networkRounds) reused connections. The handshake (DNS, TCP, TLS) cost \(fresh.handshake.milliseconds) and is only paid on a new connection."))
                    .font(.caption)
                    .foregroundStyle(Brand.dim(scheme))
            } else if model.networkFailed {
                Label(prefs.text("Sem ligação a ividi.dev. Verifica a internet e mede outra vez.", "Could not reach ividi.dev. Check the internet and measure again."),
                      systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Brand.danger)
            } else {
                placeholder
            }
        }
        .card()
    }

    private var encoderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(prefs.text("Encoder no aparelho", "On-device encoder"), detail: "NaturalLanguage · word embeddings", symbol: "cpu", active: model.running == .encoder)
            if let run = model.encoder {
                modelStats(run)
                Text(prefs.text(
                    "Uma pesquisa de vetor e uma distância por ligação, sem gerar texto. Rapidíssimo, mas só reconhece o que está perto de \"spider\" no espaço das palavras.",
                    "One vector lookup and a distance per link, no text generated. Extremely fast, but it only recognises what sits near \"spider\" in word space."))
                    .font(.caption)
                    .foregroundStyle(Brand.dim(scheme))
            } else {
                placeholder
            }
        }
        .card()
    }

    private var generativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle(prefs.text("Modelo generativo no aparelho", "On-device generative model"), detail: "Apple Foundation Models", symbol: "sparkles", active: model.running == .generative)
            if let reason = GenerativeClassifier.unavailableReason {
                Label(unavailableText(reason), systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Brand.dim(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.running == .generative {
                ProgressView(value: Double(model.generativeProgress), total: Double(MeasureModel.generativeLinks)) {
                    Text(prefs.text("A decidir \(model.generativeProgress) de \(MeasureModel.generativeLinks) ligações…",
                                    "Deciding \(model.generativeProgress) of \(MeasureModel.generativeLinks) links…"))
                        .font(.caption)
                }
                .tint(Brand.orange)
            } else if let run = model.generative {
                modelStats(run)
                Text(prefs.text("Gera a resposta palavra a palavra antes de decidir: percebe melhor o contexto, mas cada decisão custa muito mais.",
                                "It generates its answer token by token before deciding: better at context, but each decision costs far more."))
                    .font(.caption)
                    .foregroundStyle(Brand.dim(scheme))
            } else if let error = model.generativeError {
                VStack(alignment: .leading, spacing: 4) {
                    Label(prefs.text("O modelo não respondeu. Tenta outra vez daqui a pouco.", "The model did not answer. Try again in a moment."),
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Brand.danger)
                    Text(error).font(.caption2.monospaced()).foregroundStyle(Brand.faint(scheme)).lineLimit(3)
                }
            } else {
                placeholder
            }
        }
        .card()
    }

    private struct Summary {
        let trip: Double
        let encoder: ModelRun
    }

    private var summary: Summary? {
        guard let fresh = model.fresh, let encoder = model.encoder, encoder.averageMilliseconds > 0 else { return nil }
        return Summary(trip: fresh.total, encoder: encoder)
    }

    private func summaryCard(_ summary: Summary) -> some View {
        let decisions = summary.trip / summary.encoder.averageMilliseconds
        return VStack(alignment: .leading, spacing: 12) {
            Text(prefs.text("O que isto quer dizer", "What this means")).font(.system(.headline, design: .rounded, weight: .bold))
            Text(decisions.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: prefs.language.rawValue))))
                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Brand.gradient)
            Text(prefs.text(
                "decisões do encoder local no tempo de uma única viagem nova até ao servidor (\(summary.trip.milliseconds)), antes de qualquer modelo na nuvem começar a pensar.",
                "local encoder decisions in the time of a single new trip to the server (\(summary.trip.milliseconds)), before any cloud model even starts thinking."))
                .font(.subheadline)
                .foregroundStyle(Brand.dim(scheme))
            HStack(spacing: 10) {
                Button {
                    model.apply(to: lab)
                } label: {
                    Label(prefs.text("Usar na corrida", "Use in the race"), systemImage: "flag.checkered")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isRunning)
                if model.appliedToLab {
                    Label(prefs.text("Aplicado ao laboratório", "Applied to the lab"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.ok)
                }
            }
            Text(prefs.text("Põe o tempo do encoder no Ember, o do modelo generativo no Flint e a viagem medida na rede dos agentes na nuvem.",
                            "Puts the encoder time on Ember, the generative time on Flint and the measured trip on the cloud agents' network."))
                .font(.caption)
                .foregroundStyle(Brand.faint(scheme))
        }
        .card()
    }

    // MARK: Pieces

    private struct Segment {
        let pt: String, en: String, color: Color
        let value: KeyPath<NetworkSample, Double>
    }

    private var networkSegments: [Segment] {[
        Segment(pt: "DNS", en: "DNS", color: Color(hex: 0x2DD4BF), value: \.dns),
        Segment(pt: "TCP", en: "TCP", color: Color(hex: 0x38BDF8), value: \.tcp),
        Segment(pt: "TLS", en: "TLS", color: Color(hex: 0xA78BFA), value: \.tls),
        Segment(pt: "Ida e volta + servidor", en: "Round trip + server", color: Brand.cloud, value: \.server),
        Segment(pt: "Transferência", en: "Transfer", color: Brand.amber, value: \.transfer),
    ]}

    private func networkBar(_ title: String, _ sample: NetworkSample, longest: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(sample.total.milliseconds).font(.system(.subheadline, design: .monospaced, weight: .bold))
            }
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(networkSegments.indices, id: \.self) { i in
                        let value = sample[keyPath: networkSegments[i].value]
                        if value > 0.05 {
                            Rectangle().fill(networkSegments[i].color)
                                .frame(width: max(2, proxy.size.width * value / max(longest, 1)))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)
            Text(networkSegments.filter { sample[keyPath: $0.value] > 0.05 }
                    .map { "\(prefs.text($0.pt, $0.en)) \(sample[keyPath: $0.value].milliseconds)" }
                    .joined(separator: " · "))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Brand.dim(scheme))
        }
    }

    private func modelStats(_ run: ModelRun) -> some View {
        HStack(spacing: 12) {
            stat(prefs.text("por decisão", "per decision"), run.averageMilliseconds.milliseconds)
            stat(prefs.text("decisões/s", "decisions/s"), run.decisionsPerSecond >= 1000 ? String(format: "%.0fk", run.decisionsPerSecond / 1000) : String(format: "%.1f", run.decisionsPerSecond))
            stat(prefs.text("acertos", "accuracy"), String(format: "%.0f%%", run.accuracy * 100))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(Brand.text(scheme))
            Text(label).font(.caption).foregroundStyle(Brand.dim(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cardTitle(_ title: String, detail: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Brand.accent(scheme))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                Text(detail).font(.caption2.monospaced()).foregroundStyle(Brand.faint(scheme))
            }
            Spacer()
            if active { ProgressView().controlSize(.small) }
        }
    }

    private var placeholder: some View {
        Text(prefs.text("Toca em Medir para ver os valores deste aparelho.", "Tap Measure to see this device's numbers."))
            .font(.subheadline)
            .foregroundStyle(Brand.faint(scheme))
    }

    private func unavailableText(_ reason: GenerativeClassifier.Unavailable) -> String {
        switch reason {
        case .systemTooOld: prefs.text("Precisa de iOS 26 ou macOS 26 com Apple Intelligence.", "Needs iOS 26 or macOS 26 with Apple Intelligence.")
        case .simulator: prefs.text("O simulador não corre o modelo da Apple. Experimenta num iPhone, iPad ou Mac com Apple Intelligence.", "The simulator cannot run Apple's model. Try it on an iPhone, iPad or Mac with Apple Intelligence.")
        case .deviceNotEligible: prefs.text("Este aparelho não suporta Apple Intelligence.", "This device does not support Apple Intelligence.")
        case .intelligenceOff: prefs.text("Ativa a Apple Intelligence nas Definições do sistema para medir este modelo.", "Turn on Apple Intelligence in the system Settings to measure this model.")
        case .modelNotReady: prefs.text("O modelo da Apple ainda está a ser descarregado. Tenta mais tarde.", "Apple's model is still downloading. Try again later.")
        case .other: prefs.text("O modelo da Apple não está disponível agora.", "Apple's model is not available right now.")
        }
    }

    // MARK: Share

    private var shareCard: ShareCard? {
        var rows: [ShareCard.Row] = []
        if let fresh = model.fresh, let reused = model.reused {
            rows.append(.init(colorIndex: 1, name: prefs.text("Rede · ligação nova", "Network · new connection"), detail: "DNS + TCP + TLS + HTTPS",
                              value: fresh.total.milliseconds, note: "ividi.dev"))
            rows.append(.init(colorIndex: 2, name: prefs.text("Rede · ligação reutilizada", "Network · reused connection"), detail: "HTTPS",
                              value: reused.total.milliseconds, note: "ividi.dev"))
        }
        if let run = model.encoder {
            rows.append(.init(colorIndex: 0, name: prefs.text("Encoder no aparelho", "On-device encoder"), detail: "NaturalLanguage",
                              value: run.averageMilliseconds.milliseconds, note: String(format: prefs.text("%.0f%% acertos", "%.0f%% accuracy"), run.accuracy * 100)))
        }
        if let run = model.generative {
            rows.append(.init(colorIndex: 3, name: prefs.text("Modelo generativo no aparelho", "On-device generative model"), detail: "Apple Foundation Models",
                              value: run.averageMilliseconds.milliseconds, note: String(format: prefs.text("%.0f%% acertos", "%.0f%% accuracy"), run.accuracy * 100)))
        }
        guard !rows.isEmpty else { return nil }
        return ShareCard(eyebrow: prefs.text("Medição real", "Real measurement"),
                         title: prefs.text("Local contra nuvem, medido no meu aparelho", "Local versus cloud, measured on my device"),
                         rows: rows,
                         footnote: "Power of AI Agents")
    }
}
