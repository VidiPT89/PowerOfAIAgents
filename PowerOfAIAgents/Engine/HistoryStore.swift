import Foundation
import Network

/// One saved measurement: either the device benchmark (network + on-device models) or an endpoint test.
struct HistoryRecord: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case device, endpoint }

    var id = UUID()
    var date = Date()
    var kind: Kind
    /// Host or address that was measured.
    var target: String
    var connection: ConnectionKind = .unknown

    // Network (first request of the device benchmark, or the median of an endpoint test).
    var totalMs: Double?
    var followUpMs: Double?
    var dnsMs: Double?
    var tcpMs: Double?
    var tlsMs: Double?
    var serverMs: Double?
    var transferMs: Double?

    // Endpoint test.
    var method: String?
    var samples: Int?
    var failures: Int?
    var p95Ms: Double?
    var minMs: Double?
    var maxMs: Double?
    var jitterMs: Double?
    var status: Int?

    // On-device models.
    var encoderMs: Double?
    var encoderAccuracy: Double?
    var generativeMs: Double?
    var generativeAccuracy: Double?
    var language: String?
}

extension HistoryRecord {
    init(endpoint result: EndpointModel.Result, connection: ConnectionKind, date: Date = Date()) {
        let stats = result.stats
        let average = result.average
        self.init(date: date, kind: .endpoint, target: result.url.absoluteString, connection: connection,
                  totalMs: stats?.median, followUpMs: result.warm?.total,
                  dnsMs: average?.dns, tcpMs: average?.tcp, tlsMs: average?.tls, serverMs: average?.server, transferMs: average?.transfer,
                  method: result.method.rawValue, samples: result.responses.count, failures: result.failures,
                  p95Ms: stats?.p95, minMs: stats?.min, maxMs: stats?.max, jitterMs: stats?.jitter,
                  status: result.statusCodes.last)
    }
}

/// Saved measurements, newest first, in a JSON file inside the app's own container. Nothing leaves the device.
@MainActor
final class HistoryStore: ObservableObject {
    static let limit = 500

    @Published private(set) var records: [HistoryRecord] = []
    private let fileURL: URL?

    init(fileURL: URL? = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    static var defaultURL: URL? {
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return folder.appendingPathComponent("PowerOfAIAgents", isDirectory: true).appendingPathComponent("history.json")
    }

    func add(_ record: HistoryRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    func delete(_ id: HistoryRecord.ID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clear() {
        records = []
        save()
    }

    /// The most recent record of the same kind and target before this one, for "versus last time".
    func previous(before record: HistoryRecord) -> HistoryRecord? {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            return records.first { $0.kind == record.kind && $0.target == record.target && $0.id != record.id }
        }
        return records[(index + 1)...].first { $0.kind == record.kind && $0.target == record.target }
    }

    /// Distinct targets, most recent first.
    var targets: [String] {
        var seen = Set<String>()
        return records.compactMap { seen.insert($0.target).inserted ? $0.target : nil }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([HistoryRecord].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: CSV

    nonisolated static let csvHeader = "date,kind,target,connection,method,samples,failures,status,median_or_first_ms,p95_ms,min_ms,max_ms,jitter_ms,follow_up_ms,dns_ms,tcp_ms,tls_ms,server_ms,transfer_ms,encoder_ms,encoder_accuracy,generative_ms,generative_accuracy,language"

    func csv() -> String { Self.csv(records) }

    nonisolated static func csv(_ records: [HistoryRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        func number(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "" }
        func field(_ text: String) -> String {
            text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        let rows = records.map { r in
            [formatter.string(from: r.date), r.kind.rawValue, field(r.target), r.connection.rawValue, r.method ?? "",
             r.samples.map(String.init) ?? "", r.failures.map(String.init) ?? "", r.status.map(String.init) ?? "",
             number(r.totalMs), number(r.p95Ms), number(r.minMs), number(r.maxMs), number(r.jitterMs), number(r.followUpMs),
             number(r.dnsMs), number(r.tcpMs), number(r.tlsMs), number(r.serverMs), number(r.transferMs),
             number(r.encoderMs), number(r.encoderAccuracy), number(r.generativeMs), number(r.generativeAccuracy), r.language ?? ""]
                .joined(separator: ",")
        }
        return ([csvHeader] + rows).joined(separator: "\n") + "\n"
    }

    /// Writes the CSV to a temporary file for the share sheet.
    func csvFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PowerOfAIAgents-history.csv")
        do {
            try csv().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// How the device is connected right now. Saved with each record, because Wi-Fi and mobile data differ a lot.
enum ConnectionKind: String, Codable, Sendable, CaseIterable {
    case wifi, cellular, wired, other, offline, unknown
}

@MainActor
final class ConnectionMonitor: ObservableObject {
    @Published private(set) var current: ConnectionKind = .unknown
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: ConnectionKind
            if path.status != .satisfied { kind = .offline }
            else if path.usesInterfaceType(.wifi) { kind = .wifi }
            else if path.usesInterfaceType(.cellular) { kind = .cellular }
            else if path.usesInterfaceType(.wiredEthernet) { kind = .wired }
            else { kind = .other }
            Task { @MainActor in self?.current = kind }
        }
        monitor.start(queue: DispatchQueue(label: "dev.ividi.powerofaiagents.path"))
    }

    deinit { monitor.cancel() }
}
