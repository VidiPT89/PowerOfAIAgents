import Charts
import SwiftUI

/// Every saved measurement, with a chart over time, comparison with the previous run and CSV export.
struct HistoryView: View {
    enum Filter: String, CaseIterable { case all, device, endpoint }

    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.colorScheme) private var scheme
    @State private var filter: Filter = .all
    @State private var target: String?
    @State private var expanded: HistoryRecord.ID?
    @State private var confirmClear = false
    @State private var csvURL: URL?

    private var filtered: [HistoryRecord] {
        history.records.filter { record in
            switch filter {
            case .all: true
            case .device: record.kind == .device
            case .endpoint: record.kind == .endpoint
            }
        }
        .filter { target == nil || $0.target == target }
    }

    private var targets: [String] {
        Array(Set(history.records.filter { filter == .all || $0.kind.rawValue == filter.rawValue }.map(\.target))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Histórico", "History"),
                    title: prefs.text("As tuas medições", "Your measurements"),
                    subtitle: prefs.text(
                        "Cada medição e cada teste de endereço fica guardado só neste aparelho, com o tipo de ligação. Compara ao longo do tempo, entre Wi-Fi e dados móveis, e exporta para CSV.",
                        "Every measurement and endpoint test is kept on this device only, with the connection type. Compare over time, between Wi-Fi and mobile data, and export to CSV."))
                if history.records.isEmpty {
                    empty
                } else {
                    controls
                    if filtered.contains(where: { $0.totalMs != nil }) { chartCard }
                    summaryCard
                    ForEach(filtered) { record in row(record) }
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
        .onAppear { csvURL = history.records.isEmpty ? nil : history.csvFile() }
        .onChange(of: history.records) { _, records in csvURL = records.isEmpty ? nil : history.csvFile() }
        .onChange(of: filter) { _, _ in target = nil }
        .confirmationDialog(prefs.text("Apagar todo o histórico?", "Delete all history?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(prefs.text("Apagar tudo", "Delete all"), role: .destructive) { history.clear() }
            Button(prefs.text("Cancelar", "Cancel"), role: .cancel) {}
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: prefs.text("Ainda sem medições", "No measurements yet"), symbol: "clock.arrow.circlepath")
            Text(prefs.text("Usa o separador Medir ou Testar API. Cada resultado aparece aqui com a data e a ligação usada.",
                            "Use the Measure or Test API tab. Every result shows up here with the date and the connection used."))
                .font(.subheadline).foregroundStyle(Brand.dim(scheme))
        }
        .card()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(prefs.text("Mostrar", "Show"), selection: $filter) {
                Text(prefs.text("Tudo", "All")).tag(Filter.all)
                Text(prefs.text("Aparelho", "Device")).tag(Filter.device)
                Text(prefs.text("Endereços", "Endpoints")).tag(Filter.endpoint)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 10) {
                if targets.count > 1 {
                    Menu {
                        Button(prefs.text("Todos os destinos", "All targets")) { target = nil }
                        ForEach(targets, id: \.self) { t in Button(short(t)) { target = t } }
                    } label: {
                        Label(target.map(short) ?? prefs.text("Destinos", "All targets"), systemImage: "line.3.horizontal.decrease.circle")
                            .lineLimit(1)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("CSV", systemImage: "square.and.arrow.up").fixedSize()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(role: .destructive) { confirmClear = true } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(prefs.text("Apagar histórico", "Delete history"))
            }
        }
        .card()
    }

    private var chartCard: some View {
        let points = filtered.filter { $0.totalMs != nil }.reversed()
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: prefs.text("Rede ao longo do tempo", "Network over time"),
                      detail: prefs.text("primeiro pedido (aparelho) ou mediana (endereços)", "first request (device) or median (endpoints)"), symbol: "chart.xyaxis.line")
            Chart(Array(points)) { record in
                LineMark(x: .value(prefs.text("Data", "Date"), record.date),
                         y: .value("ms", record.totalMs ?? 0),
                         series: .value(prefs.text("Destino", "Target"), seriesName(record)))
                    .foregroundStyle(by: .value(prefs.text("Destino", "Target"), seriesName(record)))
                    .interpolationMethod(.monotone)
                PointMark(x: .value(prefs.text("Data", "Date"), record.date),
                          y: .value("ms", record.totalMs ?? 0))
                    .foregroundStyle(by: .value(prefs.text("Destino", "Target"), seriesName(record)))
                    .symbol(by: .value(prefs.text("Ligação", "Connection"), prefs.connectionName(record.connection)))
            }
            .chartForegroundStyleScale(range: Brand.agentColors)
            .chartYAxisLabel("ms")
            .frame(height: 200)
        }
        .card()
    }

    private var summaryCard: some View {
        let network = filtered.compactMap(\.totalMs)
        let byConnection = Dictionary(grouping: filtered.filter { $0.totalMs != nil }, by: \.connection)
        let encoder = filtered.compactMap(\.encoderMs)
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: prefs.text("Resumo", "Summary"), detail: prefs.text("\(filtered.count) registos", "\(filtered.count) records"), symbol: "sum")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                if let stats = LatencyStats(network) {
                    StatTile(label: prefs.text("rede · mediana", "network · median"), value: stats.median.milliseconds, tint: Brand.accent(scheme))
                    StatTile(label: prefs.text("rede · melhor", "network · best"), value: stats.min.milliseconds)
                    StatTile(label: prefs.text("rede · pior", "network · worst"), value: stats.max.milliseconds)
                }
                if let stats = LatencyStats(encoder) {
                    StatTile(label: prefs.text("encoder · mediana", "encoder · median"), value: stats.median.milliseconds)
                }
                ForEach(byConnection.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                    if let stats = LatencyStats(byConnection[kind]?.compactMap(\.totalMs) ?? []) {
                        StatTile(label: prefs.connectionName(kind), value: stats.median.milliseconds)
                    }
                }
            }
        }
        .card()
    }

    private func row(_ record: HistoryRecord) -> some View {
        let isOpen = expanded == record.id
        let previous = history.previous(before: record)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                expanded = isOpen ? nil : record.id
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: record.kind == .device ? "iphone.gen3" : "bolt.horizontal")
                        .foregroundStyle(Brand.accent(scheme))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(short(record.target)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(record.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(prefs.locale))
                             + " · " + prefs.connectionName(record.connection))
                            .font(.caption).foregroundStyle(Brand.dim(scheme))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.totalMs?.milliseconds ?? record.encoderMs?.milliseconds ?? "–")
                            .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                        if let delta = delta(record, previous) {
                            Text(delta.text).font(.caption2.monospacedDigit()).foregroundStyle(delta.better ? Brand.ok : Brand.danger)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(Brand.faint(scheme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { details(record) }
        }
        .card(padding: 14)
        .contextMenu {
            Button(role: .destructive) { history.delete(record.id) } label: {
                Label(prefs.text("Apagar", "Delete"), systemImage: "trash")
            }
        }
    }

    private func delta(_ record: HistoryRecord, _ previous: HistoryRecord?) -> (text: String, better: Bool)? {
        guard let now = record.totalMs, let before = previous?.totalMs, before > 0 else { return nil }
        let change = now - before
        guard abs(change) >= 0.5 else { return nil }
        return ((change > 0 ? "+" : "−") + abs(change).milliseconds + prefs.text(" vs anterior", " vs previous"), change < 0)
    }

    @ViewBuilder private func details(_ record: HistoryRecord) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            if record.kind == .endpoint {
                tile(prefs.text("mediana", "median"), record.totalMs)
                tile("p95", record.p95Ms)
                tile(prefs.text("mín", "min"), record.minMs)
                tile(prefs.text("máx", "max"), record.maxMs)
                tile(prefs.text("variação", "jitter"), record.jitterMs)
                if let samples = record.samples {
                    StatTile(label: prefs.text("pedidos · falhas", "requests · failures"), value: "\(samples) · \(record.failures ?? 0)")
                }
                if let method = record.method { StatTile(label: prefs.text("método · HTTP", "method · HTTP"), value: "\(method) · \(record.status.map(String.init) ?? "–")") }
            } else {
                tile(prefs.text("primeiro pedido", "first request"), record.totalMs)
                tile(prefs.text("pedido seguinte", "follow-up"), record.followUpMs)
                if let ms = record.encoderMs {
                    StatTile(label: prefs.text("encoder · acertos", "encoder · accuracy"), value: "\(ms.milliseconds) · \(prefs.number((record.encoderAccuracy ?? 0) * 100))%")
                }
                if let ms = record.generativeMs {
                    StatTile(label: prefs.text("modelo Apple · acertos", "Apple model · accuracy"), value: "\(ms.milliseconds) · \(prefs.number((record.generativeAccuracy ?? 0) * 100))%")
                }
            }
        }
        if let dns = record.dnsMs {
            PhaseBar(title: record.kind == .device ? prefs.text("Fases do primeiro pedido", "Phases of the first request") : prefs.text("Fases (média)", "Phases (average)"),
                     sample: NetworkSample(dns: dns, tcp: record.tcpMs ?? 0, tls: record.tlsMs ?? 0, server: record.serverMs ?? 0, transfer: record.transferMs ?? 0),
                     longest: (dns + (record.tcpMs ?? 0) + (record.tlsMs ?? 0) + (record.serverMs ?? 0) + (record.transferMs ?? 0)))
        }
        Button(role: .destructive) { history.delete(record.id) } label: {
            Label(prefs.text("Apagar este registo", "Delete this record"), systemImage: "trash")
        }
        .font(.caption.weight(.semibold))
        .tint(Brand.danger)
    }

    @ViewBuilder private func tile(_ label: String, _ value: Double?) -> some View {
        if let value { StatTile(label: label, value: value.milliseconds) }
    }

    /// The device benchmark and an endpoint test of the same host are different lines.
    private func seriesName(_ record: HistoryRecord) -> String {
        record.kind == .device ? prefs.text("Medir · ", "Measure · ") + short(record.target) : short(record.target)
    }

    private func short(_ target: String) -> String {
        guard let url = URL(string: target), let host = url.host() else { return target }
        let path = url.path()
        return path.count > 1 ? host + path : host
    }
}
