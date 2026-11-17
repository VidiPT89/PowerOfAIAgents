import Foundation

/// Summary of a list of latencies, in milliseconds.
struct LatencyStats: Sendable, Equatable {
    let count: Int
    let min: Double
    let max: Double
    let mean: Double
    let median: Double
    let p95: Double
    /// Standard deviation: how much one request differs from the next.
    let jitter: Double

    init?(_ values: [Double]) {
        let sorted = values.filter(\.isFinite).sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        count = sorted.count
        min = first
        max = last
        mean = sorted.reduce(0, +) / Double(sorted.count)
        median = Self.percentile(sorted, 0.5)
        p95 = Self.percentile(sorted, 0.95)
        let mean = mean
        jitter = (sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(sorted.count)).squareRoot()
    }

    /// Nearest-rank percentile of already sorted values.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[Swift.min(sorted.count - 1, Swift.max(0, rank - 1))]
    }
}

enum EndpointProbe {
    /// Turns what the person typed into an HTTPS address, or nil. Plain HTTP is refused, as the system would.
    static func normalize(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        components.scheme = "https"
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }
}

/// Sends the requests of one endpoint test. A protocol so tests can answer without a network.
protocol EndpointRunning: Sendable {
    func run(_ url: URL, method: HTTPMethod) async throws -> TimedResponse
    func finish()
}

/// Real requests through URLSession.
struct URLSessionEndpointRunner: EndpointRunning {
    let session = NetworkProbe.makeSession()
    func run(_ url: URL, method: HTTPMethod) async throws -> TimedResponse {
        try await NetworkProbe.measure(url, method: method, on: session)
    }
    func finish() { session.finishTasksAndInvalidate() }
}

/// Times a list of requests to an address the person chose, and keeps what came back.
@MainActor
final class EndpointModel: ObservableObject {
    static let sampleCounts = [5, 10, 20, 50]

    struct Result: Equatable {
        var url: URL
        var method: HTTPMethod
        var reuse: Bool
        var responses: [TimedResponse]
        var failures: Int
        var lastError: String?

        var totals: [Double] { responses.map(\.sample.total) }
        var stats: LatencyStats? { LatencyStats(totals) }
        /// The first request opens the connection; with reuse on, the others ride on it.
        var cold: NetworkSample? { responses.first?.sample }
        var warm: NetworkSample? { reuse ? NetworkSample.average(responses.dropFirst().map(\.sample)) : nil }
        var average: NetworkSample? { NetworkSample.average(responses.map(\.sample)) }
        var statusCodes: [Int] { Array(Set(responses.map(\.status))).sorted() }
        var successRate: Double {
            let all = responses.count + failures
            return all == 0 ? 0 : Double(responses.count) / Double(all)
        }
    }

    @Published var address: String
    @Published var method: HTTPMethod = .head
    @Published var count = 10
    @Published var reuse = true
    @Published private(set) var running = false
    @Published private(set) var progress = 0
    @Published private(set) var result: Result?
    @Published private(set) var invalidAddress = false

    private var job: Task<Void, Never>?
    private let makeRunner: (Bool) -> EndpointRunning
    /// Called once per finished test, so the history can keep it.
    var onFinish: ((Result) -> Void)?

    init(address: String = "ividi.dev", makeRunner: @escaping (Bool) -> EndpointRunning = { _ in URLSessionEndpointRunner() }) {
        self.address = address
        self.makeRunner = makeRunner
    }

    func start() {
        guard !running else { return }
        guard let url = EndpointProbe.normalize(address) else {
            invalidAddress = true
            return
        }
        invalidAddress = false
        running = true
        progress = 0
        let method = method, count = count, reuse = reuse
        result = Result(url: url, method: method, reuse: reuse, responses: [], failures: 0)
        job = Task { [weak self] in
            var current = Result(url: url, method: method, reuse: reuse, responses: [], failures: 0)
            // With reuse on, one session for every request; with it off, each request opens its own connection.
            let shared: EndpointRunning? = reuse ? self?.makeRunner(true) : nil
            defer { shared?.finish() }
            for _ in 0..<count {
                guard !Task.isCancelled, let self else { return }
                let runner = shared ?? self.makeRunner(false)
                do {
                    let response = try await runner.run(url, method: method)
                    current.responses.append(response)
                } catch {
                    current.failures += 1
                    current.lastError = (error as? URLError)?.localizedDescription ?? error.localizedDescription
                }
                if shared == nil { runner.finish() }
                guard !Task.isCancelled else { return }
                self.progress += 1
                self.result = current
            }
            guard let self, !Task.isCancelled else { return }
            self.running = false
            self.job = nil
            self.onFinish?(current)
        }
    }

    func cancel() {
        job?.cancel()
        job = nil
        running = false
    }
}
