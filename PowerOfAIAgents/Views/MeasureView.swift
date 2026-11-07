import SwiftUI

/// Real measurements on this device: the network to ividi.dev and the on-device models.
@MainActor
final class MeasureModel: ObservableObject {
    enum Step: Equatable { case network, encoder, generative }

    /// Request pairs measured per run; reuse is verified by system metrics.
    static let networkRounds = 3
    /// Identical bounded sample for both models.
    static let benchmarkLinks = Array(Article.english.links.prefix(12))

    @Published private(set) var running: Step?
    @Published private(set) var fresh: NetworkSample?
    @Published private(set) var reused: NetworkSample?
    @Published private(set) var networkFailed = false
    @Published private(set) var encoder: ModelRun?
    @Published private(set) var generative: ModelRun?
    @Published private(set) var generativeProgress = 0
    /// GenerationError's own description is "(null)", so only a plain message is shown.
    @Published private(set) var generativeFailed = false
    @Published private(set) var appliedToLab = false
    @Published private(set) var networkSampleCount = 0
    @Published private(set) var encoderUnavailable = false
    private var job: Task<Void, Never>?
    private let network: () async throws -> (fresh: NetworkSample, reused: NetworkSample)
    private let encode: ([ArticleLink]) async -> ModelRun?
    private let generate: (String) async throws -> Bool
    private let availability: () -> GenerativeClassifier.Unavailable?

    init(
        network: @escaping () async throws -> (fresh: NetworkSample, reused: NetworkSample) = { try await NetworkProbe.measurePair() },
        encode: @escaping ([ArticleLink]) async -> ModelRun? = { links in
            await Task.detached(priority: .userInitiated) { EmbeddingClassifier()?.run(on: links) }.value
        },
        generate: @escaping (String) async throws -> Bool = { try await GenerativeClassifier.isAboutSpiders($0) },
        availability: @escaping () -> GenerativeClassifier.Unavailable? = { GenerativeClassifier.unavailableReason }
    ) {
        self.network = network
        self.encode = encode
        self.generate = generate
        self.availability = availability
    }

    var isRunning: Bool { running != nil }
    var hasResults: Bool { fresh != nil || encoder != nil || generative != nil }

    func measureAll() {
        guard !isRunning else { return }
        appliedToLab = false
        fresh = nil
        reused = nil
        encoder = nil
        generative = nil
        networkFailed = false
        generativeFailed = false
        encoderUnavailable = false
        generativeProgress = 0
        networkSampleCount = 0
        running = .network
        job = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.measureNetwork()
            guard !Task.isCancelled else { return }
            await self?.measureEncoder()
            guard !Task.isCancelled else { return }
            if self?.availability() == nil { await self?.measureGenerative() }
            guard !Task.isCancelled else { return }
            self?.running = nil
            self?.job = nil
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
                let pair = try await network()
                guard !Task.isCancelled else { return }
                fresh.append(pair.fresh)
                reused.append(pair.reused)
            } catch {
                guard !Task.isCancelled else { return }
                networkFailed = true
                break
            }
        }
        networkSampleCount = fresh.count
        self.fresh = NetworkSample.average(fresh)
        self.reused = NetworkSample.average(reused)
    }

    private func measureEncoder() async {
        guard !Task.isCancelled else { return }
        running = .encoder
        let result = await encode(Self.benchmarkLinks)
        guard !Task.isCancelled else { return }
        encoder = result
        encoderUnavailable = result == nil
    }

    private func measureGenerative() async {
        running = .generative
        generativeFailed = false
        generativeProgress = 0
        let links = Self.benchmarkLinks
        let clock = ContinuousClock()
        var correct = 0, total = 0.0
        for link in links {
            guard !Task.isCancelled else { return }
            do {
                var verdict = false
                let elapsed = try await clock.measure { verdict = try await generate(link.text) }
                guard !Task.isCancelled else { return }
                total += elapsed.milliseconds
                if verdict == link.relevant { correct += 1 }
                generativeProgress += 1
            } catch {
                guard !Task.isCancelled else { return }
                generativeFailed = true
                return
            }
        }
        generative = ModelRun(decisions: links.count, correct: correct, totalMilliseconds: total)
    }

    /// Puts the measured numbers into the agent lab: the race then uses this device's real figures.
    func apply(to lab: AgentLab) {
        guard !isRunning, hasResults else { return }
        var tunings = lab.tunings
        for (index, result) in [(0, encoder), (3, generative)] {
            guard let result else { continue }
            tunings[index].kind = .local
            tunings[index].inference = result.averageMilliseconds
            tunings[index].accuracy = result.accuracy
            tunings[index].queue = 0
        }
        if let fresh {
            lab.measuredNetwork = fresh.total
            for i in tunings.indices where tunings[i].kind == .cloud { tunings[i].network = fresh.total }
        }
        lab.tunings = tunings.map(\.clamped)
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
                Text(prefs.text("Os dois modelos classificam os mesmos 12 termos em inglês, sem contexto. Precisão nesta amostra pequena; o tempo do encoder exclui carregar o vocabulário.", "Both models classify the same 12 English terms without context. Accuracy is for this small sample; encoder timing excludes loading the embedding."))
                    .font(.caption).foregroundStyle(Brand.dim(scheme))
                networkCard
                encoderCard
                generativeCard
                if let summary { summaryCard(summary) }
                if model.hasResults, !model.isRunning { applyCard }
                Text(prefs.text(
                    "A medição só faz pedidos HEAD a ividi.dev e só quando tocas em Medir. Não envia o texto do artigo. Como em qualquer pedido HTTPS, o servidor recebe o endereço IP e os metadados da ligação.",
                    "Measuring only sends HEAD requests to ividi.dev, and only when you tap Measure. It does not send the article text. As with any HTTPS request, the server receives the IP address and connection metadata."))
                    .font(.caption)
                    .foregroundStyle(Brand.faint(scheme))
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
        .onAppear { if !model.isRunning { shareImage = shareCard?.image() } }
        .onChange(of: model.isRunning) { _, running in shareImage = running ? nil : shareCard?.image() }
        .onChange(of: prefs.language) { _, _ in if !model.isRunning { shareImage = shareCard?.image() } }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(alignment: .leading, spacing: 10) { buttons }
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
                networkBar(prefs.text("Primeiro pedido", "First request"), fresh, longest: max(fresh.total, reused.total))
                networkBar(prefs.text("Pedido seguinte", "Follow-up request"), reused, longest: max(fresh.total, reused.total))
                Text(reused.reusedConnection
                     ? prefs.text("Todos os pedidos seguintes reutilizaram a ligação.", "All follow-up requests reused the connection.")
                     : prefs.text("Nem todos os pedidos seguintes reutilizaram a ligação.", "Not all follow-up requests reused the connection."))
                    .font(.caption).foregroundStyle(Brand.dim(scheme))
                FlowLegend(items: networkSegments.map { (prefs.text($0.pt, $0.en), $0.color) })
                Text(prefs.text(
                    "Média de \(model.networkSampleCount) primeiros pedidos e \(model.networkSampleCount) seguintes. O primeiro pedido gastou \(fresh.handshake.milliseconds) em DNS/TCP/TLS. A reutilização da ligação depende do servidor e do sistema.",
                    "Average of \(model.networkSampleCount) first and \(model.networkSampleCount) follow-up requests. The first request spent \(fresh.handshake.milliseconds) in DNS/TCP/TLS. Connection reuse depends on the server and system."))
                    .font(.caption)
                    .foregroundStyle(Brand.dim(scheme))
            }
            if model.networkFailed {
                Label(model.fresh == nil
                      ? prefs.text("Sem ligação a ividi.dev. Verifica a internet e mede outra vez.", "Could not reach ividi.dev. Check the internet and measure again.")
                      : prefs.text("Só \(model.networkSampleCount) de \(MeasureModel.networkRounds) medições terminaram; as outras falharam.", "Only \(model.networkSampleCount) of \(MeasureModel.networkRounds) measurements finished; the others failed."),
                      systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Brand.danger)
            } else if model.fresh == nil {
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
            } else if model.encoderUnavailable {
                Text(prefs.text("O vocabulário inglês não está disponível neste sistema.", "The English word embedding is unavailable on this system."))
                    .font(.subheadline)
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
                ProgressView(value: Double(model.generativeProgress), total: Double(MeasureModel.benchmarkLinks.count)) {
                    Text(prefs.text("A decidir \(model.generativeProgress) de \(MeasureModel.benchmarkLinks.count) ligações…",
                                    "Deciding \(model.generativeProgress) of \(MeasureModel.benchmarkLinks.count) links…"))
                        .font(.caption)
                }
                .tint(Brand.orange)
            } else if let run = model.generative {
                modelStats(run)
                Text(prefs.text("Gera a resposta palavra a palavra antes de decidir: percebe melhor o contexto, mas cada decisão custa muito mais.",
                                "It generates its answer token by token before deciding: better at context, but each decision costs far more."))
                    .font(.caption)
                    .foregroundStyle(Brand.dim(scheme))
            } else if model.generativeFailed {
                Label(prefs.text("O modelo não respondeu. Tenta outra vez daqui a pouco.", "The model did not answer. Try again in a moment."),
                      systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Brand.danger)
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
                "decisões estimadas do encoder no tempo do primeiro pedido HTTPS (\(summary.trip.milliseconds)), incluindo trabalho do servidor web. Não mede um modelo na nuvem.",
                "estimated encoder decisions in the time of the first HTTPS request (\(summary.trip.milliseconds)), including web-server work. This does not measure a cloud model."))
                .font(.subheadline)
                .foregroundStyle(Brand.dim(scheme))
        }
        .card()
    }

    /// Available whenever something was measured, even if the network or one model failed.
    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.apply(to: lab)
                } label: {
                    Label(prefs.text("Usar na corrida", "Use in the race"), systemImage: "flag.checkered")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                if model.appliedToLab {
                    Label(prefs.text("Aplicado ao laboratório", "Applied to the lab"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.ok)
                }
            }
            Text(prefs.text("Aplica tempo e precisão ao Ember e Flint medidos, como agentes locais sem fila. Copia o pedido HTTPS para a rede dos agentes na nuvem, dentro dos limites do laboratório. A corrida mantém deslocação e variação simuladas.",
                            "Applies time and accuracy to measured Ember and Flint as local agents without a queue. Copies the HTTPS request into cloud network time within lab limits. The race retains simulated walking and jitter."))
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
            rows.append(.init(colorIndex: 1, name: prefs.text("Rede · primeiro pedido", "Network · first request"), detail: "DNS + TCP + TLS + HTTPS",
                              value: fresh.total.milliseconds, note: "ividi.dev"))
            rows.append(.init(colorIndex: 2, name: prefs.text("Rede · pedido seguinte", "Network · follow-up request"), detail: "HTTPS",
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
                         title: prefs.text("Modelos locais e rede HTTPS", "Local models and HTTPS network"),
                         rows: rows,
                         footnote: prefs.text("12 termos em inglês · sem modelo na nuvem", "12 English terms · no cloud model"))
    }
}
