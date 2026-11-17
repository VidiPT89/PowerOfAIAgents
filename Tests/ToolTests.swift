import XCTest
@testable import PowerOfAIAgents

/// The real tools: endpoint tests, statistics, history and the on-device text lab.
final class ToolTests: XCTestCase {
    // MARK: Statistics

    func testLatencyStatsUseNearestRankPercentiles() throws {
        let stats = try XCTUnwrap(LatencyStats((1...20).map(Double.init).shuffled()))
        XCTAssertEqual(stats.count, 20)
        XCTAssertEqual(stats.min, 1)
        XCTAssertEqual(stats.max, 20)
        XCTAssertEqual(stats.median, 10)
        XCTAssertEqual(stats.p95, 19)
        XCTAssertEqual(stats.mean, 10.5, accuracy: 1e-9)
        XCTAssertEqual(stats.jitter, 5.766, accuracy: 0.001)
        XCTAssertNil(LatencyStats([]))
        XCTAssertEqual(LatencyStats([42])?.p95, 42)
        XCTAssertEqual(LatencyStats([42])?.jitter, 0)
    }

    // MARK: Addresses

    func testAddressesAreNormalisedToHTTPS() {
        XCTAssertEqual(EndpointProbe.normalize("ividi.dev")?.absoluteString, "https://ividi.dev/")
        XCTAssertEqual(EndpointProbe.normalize("  api.example.com/health?x=1 ")?.absoluteString, "https://api.example.com/health?x=1")
        XCTAssertEqual(EndpointProbe.normalize("HTTPS://Example.com")?.scheme, "https")
        XCTAssertNil(EndpointProbe.normalize("http://example.com"))
        XCTAssertNil(EndpointProbe.normalize("ftp://example.com"))
        XCTAssertNil(EndpointProbe.normalize(""))
        XCTAssertNil(EndpointProbe.normalize("not a url"))
        XCTAssertNil(EndpointProbe.normalize("localhost"))
    }

    // MARK: Endpoint model

    private final class FakeRunner: EndpointRunning, @unchecked Sendable {
        let lock = NSLock()
        var calls = 0
        var finished = 0
        let failEvery: Int?
        let reused: Bool

        init(reused: Bool, failEvery: Int? = nil) {
            self.reused = reused
            self.failEvery = failEvery
        }

        func run(_ url: URL, method: HTTPMethod) async throws -> TimedResponse {
            let n = lock.withLock { calls += 1; return calls }
            if let failEvery, n % failEvery == 0 { throw URLError(.timedOut) }
            // The first request on a runner opens the connection; later ones reuse it.
            let first = n == 1
            return TimedResponse(sample: NetworkSample(dns: first ? 10 : 0, tcp: first ? 20 : 0, tls: first ? 30 : 0,
                                                       server: 40, transfer: 1, reusedConnection: !first),
                                 status: 200, bytes: 0)
        }

        func finish() { lock.withLock { finished += 1 } }
    }

    @MainActor
    private func finish(_ model: EndpointModel) async {
        for _ in 0..<2000 {
            if !model.running { return }
            await Task.yield()
        }
        XCTFail("Endpoint test did not finish")
        model.cancel()
    }

    @MainActor
    func testReusedConnectionSeparatesColdAndWarmRequests() async throws {
        var runners: [FakeRunner] = []
        let model = EndpointModel(address: "api.example.com") { reuse in
            let runner = FakeRunner(reused: reuse)
            runners.append(runner)
            return runner
        }
        var finished: EndpointModel.Result?
        model.onFinish = { finished = $0 }
        model.count = 5
        model.reuse = true
        model.start()
        await finish(model)
        let result = try XCTUnwrap(finished)
        XCTAssertEqual(runners.count, 1, "one shared session when reusing")
        XCTAssertEqual(runners[0].finished, 1)
        XCTAssertEqual(result.responses.count, 5)
        XCTAssertEqual(result.cold?.total, 101)
        XCTAssertEqual(result.warm?.total, 41)
        XCTAssertEqual(result.stats?.median, 41)
        XCTAssertEqual(result.successRate, 1)
        XCTAssertEqual(result.url.absoluteString, "https://api.example.com/")
    }

    @MainActor
    func testWithoutReuseEveryRequestOpensItsOwnConnection() async throws {
        var runners: [FakeRunner] = []
        let model = EndpointModel(address: "api.example.com") { reuse in
            let runner = FakeRunner(reused: reuse)
            runners.append(runner)
            return runner
        }
        model.count = 5
        model.reuse = false
        model.start()
        await finish(model)
        let result = try XCTUnwrap(model.result)
        XCTAssertEqual(runners.count, 5)
        XCTAssertTrue(runners.allSatisfy { $0.finished == 1 })
        XCTAssertNil(result.warm)
        XCTAssertEqual(result.stats?.median, 101)
    }

    @MainActor
    func testFailedRequestsAreCountedAndTheTestCarriesOn() async throws {
        let model = EndpointModel(address: "api.example.com") { _ in FakeRunner(reused: true, failEvery: 2) }
        model.count = 10
        model.start()
        await finish(model)
        let result = try XCTUnwrap(model.result)
        XCTAssertEqual(result.responses.count, 5)
        XCTAssertEqual(result.failures, 5)
        XCTAssertEqual(result.successRate, 0.5)
        XCTAssertNotNil(result.lastError)
    }

    @MainActor
    func testInvalidAddressDoesNotStart() {
        let model = EndpointModel(address: "http://insecure.example.com") { _ in FakeRunner(reused: true) }
        model.start()
        XCTAssertTrue(model.invalidAddress)
        XCTAssertFalse(model.running)
        XCTAssertNil(model.result)
    }

    // MARK: History

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
    }

    @MainActor
    func testHistoryIsSavedAndReloaded() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = HistoryStore(fileURL: url)
        let first = HistoryRecord(date: Date(timeIntervalSince1970: 1_000), kind: .device, target: "ividi.dev", connection: .wifi, totalMs: 120, encoderMs: 0.004)
        let second = HistoryRecord(date: Date(timeIntervalSince1970: 2_000), kind: .device, target: "ividi.dev", connection: .cellular, totalMs: 300)
        store.add(first)
        store.add(second)
        XCTAssertEqual(store.records.map(\.id), [second.id, first.id], "newest first")
        XCTAssertEqual(store.previous(before: second)?.id, first.id)
        XCTAssertNil(store.previous(before: first))

        let reloaded = HistoryStore(fileURL: url)
        XCTAssertEqual(reloaded.records, store.records)
        reloaded.delete(first.id)
        XCTAssertEqual(HistoryStore(fileURL: url).records.map(\.id), [second.id])
        reloaded.clear()
        XCTAssertTrue(HistoryStore(fileURL: url).records.isEmpty)
    }

    @MainActor
    func testHistoryKeepsAtMostTheLimit() {
        let store = HistoryStore(fileURL: nil)
        for i in 0..<(HistoryStore.limit + 5) {
            store.add(HistoryRecord(kind: .endpoint, target: "t\(i)"))
        }
        XCTAssertEqual(store.records.count, HistoryStore.limit)
        XCTAssertEqual(store.records.first?.target, "t\(HistoryStore.limit + 4)")
    }

    func testCSVQuotesFieldsAndKeepsEveryColumn() {
        let record = HistoryRecord(date: Date(timeIntervalSince1970: 0), kind: .endpoint, target: "https://a.example/x?q=1,2",
                                   connection: .wifi, totalMs: 12.5, method: "GET", samples: 10, failures: 1, p95Ms: 30, status: 200)
        let lines = HistoryStore.csv([record]).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], HistoryStore.csvHeader)
        XCTAssertTrue(lines[1].hasPrefix("1970-01-01T00:00:00Z,endpoint,\"https://a.example/x?q=1,2\",wifi,GET,10,1,200,12.500,30.000"))
        let columns = HistoryStore.csvHeader.split(separator: ",").count
        // The quoted target has one comma inside it.
        XCTAssertEqual(lines[1].split(separator: ",", omittingEmptySubsequences: false).count, columns + 1)
    }

    func testEndpointResultBecomesAHistoryRecord() {
        let url = URL(string: "https://api.example.com/")!
        let responses = [101.0, 41, 41, 61].enumerated().map { i, total in
            TimedResponse(sample: NetworkSample(dns: i == 0 ? 60 : 0, server: i == 0 ? 41 : total), status: i == 3 ? 503 : 200, bytes: 0)
        }
        let result = EndpointModel.Result(url: url, method: .get, reuse: true, responses: responses, failures: 1)
        let record = HistoryRecord(endpoint: result, connection: .cellular)
        XCTAssertEqual(record.kind, .endpoint)
        XCTAssertEqual(record.target, url.absoluteString)
        XCTAssertEqual(record.samples, 4)
        XCTAssertEqual(record.failures, 1)
        XCTAssertEqual(record.totalMs, 41)
        XCTAssertEqual(record.maxMs, 101)
        XCTAssertEqual(record.status, 503)
        XCTAssertEqual(record.connection, .cellular)
    }

    @MainActor
    func testDeviceMeasurementIsRecordedWhenItFinishes() async {
        var saved: [HistoryRecord] = []
        let model = MeasureModel(network: {
            (NetworkSample(dns: 5, server: 100), NetworkSample(server: 50, reusedConnection: true))
        }, encode: { links, _ in
            ModelRun(decisions: links.count, correct: 9, totalMilliseconds: 0.06)
        }, generate: { _, _ in true }, availability: { .simulator }, hasEmbedding: { _ in true })
        model.onFinish = { saved.append($0) }
        model.measureAll(language: .english)
        for _ in 0..<1000 where model.isRunning { await Task.yield() }
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.kind, .device)
        XCTAssertEqual(saved.first?.totalMs, 105)
        XCTAssertEqual(saved.first?.followUpMs, 50)
        XCTAssertEqual(saved.first?.encoderAccuracy ?? 0, 0.75, accuracy: 1e-9)
        XCTAssertNil(saved.first?.generativeMs)
    }

    // MARK: Text lab

    func testTextAnalysisFindsLanguageCountsAndTimesEveryTask() {
        let analysis = TextAnalyzer.analyze("Tim Cook announced new features in Cupertino. Developers love how fast the models run on the iPhone!")
        XCTAssertEqual(analysis.dominantLanguage, "en")
        XCTAssertEqual(analysis.sentences, 2)
        XCTAssertGreaterThanOrEqual(analysis.words, 17)
        XCTAssertEqual(Set(analysis.timings.map(\.task)), Set(TextAnalysis.Timing.Task.allCases))
        XCTAssertTrue(analysis.timings.allSatisfy { $0.milliseconds >= 0 })
        XCTAssertGreaterThan(analysis.nouns, 0)
    }

    func testSentimentWithoutAModelIsHidden() {
        XCTAssertNil(TextAnalyzer.sentimentAverage([-1, -1, -1, -1]))
        XCTAssertNil(TextAnalyzer.sentimentAverage([0, 0]))
        XCTAssertNil(TextAnalyzer.sentimentAverage([]))
        XCTAssertEqual(TextAnalyzer.sentimentAverage([0.6, 0.2]) ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(TextAnalyzer.sentimentAverage([-1]), -1)
    }

    func testEmptyTextHasNoAnalysis() {
        let analysis = TextAnalyzer.analyze("   \n ")
        XCTAssertTrue(analysis.timings.isEmpty)
        XCTAssertNil(analysis.dominantLanguage)
    }

    func testSentencesAreSplitAndTrimmed() {
        XCTAssertEqual(TextAnalyzer.sentences("One here.  Two there!\nThree?"), ["One here.", "Two there!", "Three?"])
    }

    func testTopicWordsAreSplitOnCommasAndLines() {
        XCTAssertEqual(TopicClassifier.words(" Food, drink\nfruit ,, "), ["food", "drink", "fruit"])
    }

    func testTopicClassifierSeparatesRelatedAndUnrelatedTerms() throws {
        let classifier = try XCTUnwrap(TopicClassifier(topic: "food", language: .english))
        let decisions = classifier.decide(["bread", "cheese", "keyboard", "train"], threshold: 0.95)
        XCTAssertEqual(decisions.count, 4)
        XCTAssertLessThan(classifier.distance("bread"), classifier.distance("keyboard"))
        XCTAssertLessThan(classifier.distance("cheese"), classifier.distance("train"))
        XCTAssertEqual(classifier.distance("zzqxv"), 2)
        XCTAssertTrue(decisions.allSatisfy { $0.encoderMilliseconds >= 0 && $0.modelSays == nil })
        XCTAssertNil(TopicClassifier(topic: " , ", language: .english))
    }

    func testTopicClassifierFollowsTheLanguageOfTheWords() throws {
        let english = try XCTUnwrap(TopicClassifier(topic: "food", terms: ["bread", "cheese", "keyboard"], language: .portuguese,
                                                    hasEmbedding: { _ in true }))
        XCTAssertEqual(english.language, .english)
        // Without the Portuguese embedding, Portuguese words are refused (the English one would not know them),
        // but English words still work in a Portuguese app.
        XCTAssertNil(TopicClassifier(topic: "comida", terms: ["pão", "queijo", "comboio", "laranja"], language: .portuguese,
                                     hasEmbedding: { $0 == .english }))
        XCTAssertEqual(TopicClassifier(topic: "food", terms: ["bread", "cheese"], language: .portuguese,
                                       hasEmbedding: { $0 == .english })?.language, .english)
        XCTAssertNil(TopicClassifier(topic: "food", language: .english, hasEmbedding: { _ in false }))
    }
}
