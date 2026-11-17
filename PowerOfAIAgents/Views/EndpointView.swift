import Charts
import SwiftUI

/// Times real requests to any HTTPS address the person types: their own API, a CDN, a model provider.
struct EndpointView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var connection: ConnectionMonitor
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: EndpointModel
    @FocusState private var addressFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Testar um endereço", "Test an endpoint"),
                    title: prefs.text("Quanto demora a tua API?", "How fast is your API?"),
                    subtitle: prefs.text(
                        "Escreve qualquer endereço HTTPS (a tua API, um servidor de modelos, um CDN). A app faz pedidos reais e mostra onde foi cada milissegundo: DNS, TCP, TLS, servidor e transferência.",
                        "Type any HTTPS address (your API, a model server, a CDN). The app sends real requests and shows where every millisecond went: DNS, TCP, TLS, server and transfer."))
                form
                if let result = model.result { results(result) } else { emptyState }
                Text(prefs.text(
                    "Os pedidos só saem quando tocas em Testar e vão diretamente deste aparelho para o endereço que escreveste. A app não passa por nenhum servidor seu e guarda os resultados só no aparelho.",
                    "Requests are only sent when you tap Test and go straight from this device to the address you typed. The app uses no server of its own and keeps results on the device only."))
                    .font(.caption)
                    .foregroundStyle(Brand.faint(scheme))
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Brand.background(scheme).ignoresSafeArea())
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(Brand.accent(scheme))
                TextField("api.example.com/health", text: $model.address)
                    .plainEntry(url: true)
                    .focused($addressFocused)
                    .onSubmit(start)
                    .submitLabel(.go)
                    .font(.system(.body, design: .monospaced))
                    .disabled(model.running)
            }
            .padding(12)
            .background(Brand.panel2(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if model.invalidAddress {
                Label(prefs.text("Escreve um endereço HTTPS válido, por exemplo api.example.com/health.",
                                 "Type a valid HTTPS address, for example api.example.com/health."),
                      systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.danger)
            }
            if !recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent, id: \.self) { target in
                            Button(shortName(target)) { model.address = target }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(model.running)
                        }
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { options }
                VStack(alignment: .leading, spacing: 12) { options }
            }
            HStack(spacing: 10) {
                Button {
                    if model.running { model.cancel() } else { start() }
                } label: {
                    Label(model.running ? prefs.text("Parar", "Stop") : prefs.text("Testar", "Test"),
                          systemImage: model.running ? "stop.fill" : "bolt.horizontal.fill")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                if model.running {
                    ProgressView(value: Double(model.progress), total: Double(model.count))
                        .tint(Brand.orange)
                        .frame(maxWidth: 160)
                    Text("\(model.progress)/\(model.count)").font(.caption.monospacedDigit()).foregroundStyle(Brand.dim(scheme))
                }
                Spacer()
                ConnectionBadge(kind: connection.current)
            }
        }
        .card()
    }

    @ViewBuilder private var options: some View {
        Picker(prefs.text("Método", "Method"), selection: $model.method) {
            ForEach(HTTPMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 160)
        Picker(prefs.text("Pedidos", "Requests"), selection: $model.count) {
            ForEach(EndpointModel.sampleCounts, id: \.self) { Text("\($0)×").tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 240)
        Toggle(prefs.text("Reutilizar ligação", "Reuse connection"), isOn: $model.reuse)
            .tint(Brand.orange)
            .fixedSize()
    }

    private func start() {
        addressFocused = false
        model.start()
    }

    private var recent: [String] {
        let saved = history.records.filter { $0.kind == .endpoint }.map(\.target)
        var seen = Set<String>()
        return (saved + ["https://ividi.dev/", "https://www.apple.com/"]).filter { seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    private func shortName(_ target: String) -> String {
        guard let url = URL(string: target), let host = url.host() else { return target }
        let path = url.path()
        return path.count > 1 ? host + path : host
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: prefs.text("Como funciona", "How it works"), symbol: "questionmark.circle")
            bullet("1", prefs.text("O primeiro pedido abre a ligação: paga DNS, TCP e TLS.", "The first request opens the connection: it pays for DNS, TCP and TLS."))
            bullet("2", prefs.text("Com a reutilização ligada, os seguintes aproveitam a ligação aberta, como uma app real faria.", "With reuse on, the next requests ride on the open connection, as a real app would."))
            bullet("3", prefs.text("Recebes a mediana, o p95 e a variação, um gráfico pedido a pedido e o resultado fica no Histórico.", "You get the median, p95 and jitter, a request-by-request chart, and the result is kept in History."))
            bullet("4", prefs.text("Compara Wi-Fi e dados móveis, ou dois servidores, para decidir se uma funcionalidade aguenta ir à rede ou deve correr no aparelho.", "Compare Wi-Fi with mobile data, or two servers, to decide whether a feature can afford the network or should run on the device."))
        }
        .card()
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Brand.gradient, in: Circle())
            Text(text).font(.subheadline).foregroundStyle(Brand.dim(scheme)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Results

    @ViewBuilder private func results(_ result: EndpointModel.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: shortName(result.url.absoluteString),
                      detail: "\(result.method.rawValue) · \(result.reuse ? prefs.text("ligação reutilizada", "connection reused") : prefs.text("ligação nova em cada pedido", "new connection per request"))",
                      symbol: "bolt.horizontal", active: model.running)
            if let stats = result.stats {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    StatTile(label: prefs.text("mediana", "median"), value: stats.median.milliseconds, tint: Brand.accent(scheme))
                    StatTile(label: "p95", value: stats.p95.milliseconds)
                    StatTile(label: prefs.text("mínimo", "min"), value: stats.min.milliseconds)
                    StatTile(label: prefs.text("máximo", "max"), value: stats.max.milliseconds)
                    StatTile(label: prefs.text("variação (desvio)", "jitter (std dev)"), value: stats.jitter.milliseconds)
                    StatTile(label: prefs.text("sucesso", "success"), value: "\(prefs.number(result.successRate * 100))%",
                             tint: result.failures > 0 ? Brand.danger : Brand.ok)
                    StatTile(label: "HTTP", value: result.statusCodes.map(String.init).joined(separator: " · "))
                }
                chart(result)
                if let cold = result.cold {
                    PhaseBar(title: prefs.text("Primeiro pedido (ligação nova)", "First request (new connection)"), sample: cold,
                             longest: max(cold.total, result.warm?.total ?? 0))
                }
                if let warm = result.warm {
                    PhaseBar(title: prefs.text("Média dos seguintes (ligação reutilizada)", "Average of the rest (reused connection)"), sample: warm,
                             longest: max(result.cold?.total ?? 0, warm.total))
                } else if !result.reuse, let average = result.average {
                    PhaseBar(title: prefs.text("Média (cada um com ligação nova)", "Average (each with a new connection)"), sample: average, longest: average.total)
                }
                FlowLegend(items: PhaseBar.segments.map { (prefs.text($0.pt, $0.en), $0.color) })
                if !model.running { verdict(result, stats) }
            }
            if result.failures > 0 {
                Label(prefs.text("\(result.failures) pedido(s) falharam", "\(result.failures) request(s) failed") + (result.lastError.map { ": \($0)" } ?? "."),
                      systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private func chart(_ result: EndpointModel.Result) -> some View {
        Chart {
            ForEach(Array(result.responses.enumerated()), id: \.offset) { index, response in
                BarMark(x: .value(prefs.text("Pedido", "Request"), index + 1),
                        y: .value("ms", response.sample.handshake))
                    .foregroundStyle(Color(hex: 0xA78BFA))
                BarMark(x: .value(prefs.text("Pedido", "Request"), index + 1),
                        y: .value("ms", response.sample.server + response.sample.transfer))
                    .foregroundStyle(Brand.cloud)
            }
            if let median = result.stats?.median {
                RuleMark(y: .value(prefs.text("mediana", "median"), median))
                    .foregroundStyle(Brand.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(prefs.text("mediana", "median") + " " + median.milliseconds)
                            .font(.caption2.weight(.semibold)).foregroundStyle(Brand.orange)
                    }
            }
        }
        .chartXAxisLabel(prefs.text("pedido", "request"))
        .chartYAxisLabel("ms")
        .frame(height: 180)
        .accessibilityLabel(prefs.text("Tempo de cada pedido", "Time of each request"))
    }

    /// What the numbers mean for a feature that makes one request per user action.
    private func verdict(_ result: EndpointModel.Result, _ stats: LatencyStats) -> some View {
        let perSecond = stats.median > 0 ? 1000 / stats.median : 0
        let feel: String = switch stats.p95 {
        case ..<100: prefs.text("Parece instantâneo: abaixo de 100 ms mesmo no p95.", "Feels instant: under 100 ms even at p95.")
        case ..<300: prefs.text("Nota-se pouco, mas uma cadeia de vários pedidos já se sente.", "Barely noticeable, but a chain of several requests will be felt.")
        case ..<1000: prefs.text("Nota-se. Para decisões repetidas (classificar, filtrar), um modelo no aparelho fica muito à frente.", "Noticeable. For repeated decisions (classify, filter), an on-device model wins by far.")
        default: prefs.text("Lento. Mostra progresso ao utilizador ou leva o trabalho para o aparelho.", "Slow. Show progress to the user or move the work onto the device.")
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(prefs.text("O que isto quer dizer", "What this means")).font(.system(.headline, design: .rounded, weight: .bold))
            Text(feel).font(.subheadline).foregroundStyle(Brand.text(scheme))
            Text(prefs.text("Pedidos em série a este ritmo: cerca de \(prefs.number(perSecond, decimals: perSecond < 10 ? 1 : 0)) por segundo. Mede o encoder no separador Medir para comparar com uma decisão no aparelho.",
                            "Back-to-back requests at this pace: about \(prefs.number(perSecond, decimals: perSecond < 10 ? 1 : 0)) per second. Measure the encoder in the Measure tab to compare with an on-device decision."))
                .font(.caption)
                .foregroundStyle(Brand.dim(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One request split into DNS, TCP, TLS, server and transfer.
struct PhaseBar: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let title: String
    let sample: NetworkSample
    let longest: Double

    struct Segment {
        let pt: String, en: String, color: Color
        let value: KeyPath<NetworkSample, Double>
    }

    static let segments: [Segment] = [
        Segment(pt: "DNS", en: "DNS", color: Color(hex: 0x2DD4BF), value: \.dns),
        Segment(pt: "TCP", en: "TCP", color: Color(hex: 0x38BDF8), value: \.tcp),
        Segment(pt: "TLS", en: "TLS", color: Color(hex: 0xA78BFA), value: \.tls),
        Segment(pt: "Ida e volta + servidor", en: "Round trip + server", color: Brand.cloud, value: \.server),
        Segment(pt: "Transferência", en: "Transfer", color: Brand.amber, value: \.transfer),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(sample.total.milliseconds).font(.system(.subheadline, design: .monospaced, weight: .bold))
            }
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(Self.segments.indices, id: \.self) { i in
                        let value = sample[keyPath: Self.segments[i].value]
                        if value > 0.05 {
                            Rectangle().fill(Self.segments[i].color)
                                .frame(width: max(2, proxy.size.width * value / max(longest, 1)))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 14)
            Text(Self.segments.filter { sample[keyPath: $0.value] > 0.05 }
                    .map { "\(prefs.text($0.pt, $0.en)) \(sample[keyPath: $0.value].milliseconds)" }
                    .joined(separator: " · "))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Brand.dim(scheme))
        }
        .accessibilityElement(children: .combine)
    }
}
