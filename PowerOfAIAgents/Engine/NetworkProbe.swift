import Foundation

/// Where the time of one real HTTPS request went, in milliseconds, from the system's own timestamps.
struct NetworkSample: Sendable, Equatable {
    var dns = 0.0
    var tcp = 0.0
    var tls = 0.0
    /// From sending the request to the first byte back: one round trip plus the server's work.
    var server = 0.0
    var transfer = 0.0
    var reusedConnection = false

    var handshake: Double { dns + tcp + tls }
    var total: Double { dns + tcp + tls + server + transfer }

    init(dns: Double = 0, tcp: Double = 0, tls: Double = 0, server: Double = 0, transfer: Double = 0, reusedConnection: Bool = false) {
        self.dns = dns
        self.tcp = tcp
        self.tls = tls
        self.server = server
        self.transfer = transfer
        self.reusedConnection = reusedConnection
    }

    init(domainLookupStart: Date?, domainLookupEnd: Date?, connectStart: Date?, secureConnectionStart: Date?,
         secureConnectionEnd: Date?, connectEnd: Date?, requestStart: Date?, responseStart: Date?, responseEnd: Date?,
         reusedConnection: Bool) {
        func ms(_ from: Date?, _ to: Date?) -> Double {
            guard let from, let to else { return 0 }
            return max(0, to.timeIntervalSince(from) * 1000)
        }
        self.init(dns: ms(domainLookupStart, domainLookupEnd),
                  tcp: ms(connectStart, secureConnectionStart ?? connectEnd),
                  tls: ms(secureConnectionStart, secureConnectionEnd),
                  server: ms(requestStart, responseStart),
                  transfer: ms(responseStart, responseEnd),
                  reusedConnection: reusedConnection)
    }

    init(_ metrics: URLSessionTaskTransactionMetrics) {
        self.init(domainLookupStart: metrics.domainLookupStartDate, domainLookupEnd: metrics.domainLookupEndDate,
                  connectStart: metrics.connectStartDate, secureConnectionStart: metrics.secureConnectionStartDate,
                  secureConnectionEnd: metrics.secureConnectionEndDate, connectEnd: metrics.connectEndDate,
                  requestStart: metrics.requestStartDate, responseStart: metrics.responseStartDate,
                  responseEnd: metrics.responseEndDate, reusedConnection: metrics.isReusedConnection)
    }

    /// Every network transaction of one request added up, so a redirect never hides the handshake.
    static func combined(_ transactions: [NetworkSample]) -> NetworkSample? {
        guard !transactions.isEmpty else { return nil }
        return NetworkSample(dns: transactions.map(\.dns).reduce(0, +),
                             tcp: transactions.map(\.tcp).reduce(0, +),
                             tls: transactions.map(\.tls).reduce(0, +),
                             server: transactions.map(\.server).reduce(0, +),
                             transfer: transactions.map(\.transfer).reduce(0, +),
                             reusedConnection: transactions.allSatisfy(\.reusedConnection))
    }

    static func average(_ samples: [NetworkSample]) -> NetworkSample? {
        guard !samples.isEmpty else { return nil }
        let n = Double(samples.count)
        return NetworkSample(dns: samples.map(\.dns).reduce(0, +) / n,
                             tcp: samples.map(\.tcp).reduce(0, +) / n,
                             tls: samples.map(\.tls).reduce(0, +) / n,
                             server: samples.map(\.server).reduce(0, +) / n,
                             transfer: samples.map(\.transfer).reduce(0, +) / n,
                             reusedConnection: samples.allSatisfy(\.reusedConnection))
    }
}

/// Real requests to ividi.dev: a brand-new connection pays DNS, TCP and TLS; a reused one does not.
enum NetworkProbe {
    /// The final address, so the request is not redirected (the root redirects to a language).
    static let url = URL(string: "https://ividi.dev/en")!

    /// One request on a new connection, then one more on that same connection.
    static func measurePair() async throws -> (fresh: NetworkSample, reused: NetworkSample) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let fresh = try await sample(on: session)
        let reused = try await sample(on: session)
        return (fresh, reused)
    }

    private static func sample(on session: URLSession) async throws -> NetworkSample {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        let collector = MetricsCollector()
        let (_, response) = try await session.data(for: request, delegate: collector)
        guard let http = response as? HTTPURLResponse, http.statusCode < 500 else { throw URLError(.badServerResponse) }
        // The metrics callback can land a moment after the response.
        for _ in 0..<20 where collector.metrics == nil { try await Task.sleep(for: .milliseconds(25)) }
        let transactions = (collector.metrics?.transactionMetrics ?? [])
            .filter { $0.resourceFetchType == .networkLoad }
            .map(NetworkSample.init)
        guard let sample = NetworkSample.combined(transactions) else { throw URLError(.cannotParseResponse) }
        return sample
    }
}

private final class MetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: URLSessionTaskMetrics?

    var metrics: URLSessionTaskMetrics? { lock.withLock { collected } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { collected = metrics }
    }
}
