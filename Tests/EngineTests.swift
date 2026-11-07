import XCTest
@testable import PowerOfAIAgents

final class EngineTests: XCTestCase {
    func testBothLanguagesShareTheSameLinks() {
        XCTAssertEqual(Article.english.relevance, Article.portuguese.relevance)
        XCTAssertGreaterThan(Article.english.relevance.count, 30)
        XCTAssertTrue(Article.english.relevance.contains(true))
        XCTAssertTrue(Article.english.relevance.contains(false))
    }

    func testLocalEncoderMakesSeveralTimesMoreDecisionsThanTheCloud() {
        var engine = RaceEngine(relevance: Article.english.relevance, duration: 20)
        engine.advance(to: 20)
        let ember = engine.runs[0].decisions
        for cloud in engine.profiles.indices where engine.profiles[cloud].kind == .cloud {
            XCTAssertGreaterThan(Double(ember), Double(engine.runs[cloud].decisions) * 2.5)
        }
        XCTAssertEqual(engine.ranking.first, 0)
        XCTAssertTrue(engine.isFinished)
    }

    func testRaceIsDeterministicAndStepIndependent() {
        var oneShot = RaceEngine(relevance: Article.english.relevance, duration: 10, seed: 3)
        oneShot.advance(to: 10)
        var stepped = RaceEngine(relevance: Article.english.relevance, duration: 10, seed: 3)
        var t = 0.0
        while t < 10 { t += 1.0 / 60; stepped.advance(to: t) }
        for i in oneShot.runs.indices {
            XCTAssertEqual(oneShot.runs[i].decisions, stepped.runs[i].decisions)
            XCTAssertEqual(oneShot.runs[i].finds, stepped.runs[i].finds)
        }
    }

    func testVerdictsAreConsistentWithCounters() {
        var engine = RaceEngine(relevance: Article.english.relevance, duration: 30)
        engine.advance(to: 30)
        for run in engine.runs {
            XCTAssertEqual(run.verdicts.count, run.decisions)
            XCTAssertEqual(run.verdicts.values.filter { $0 == .hit }.count, run.finds)
            XCTAssertEqual(run.verdicts.values.filter { $0 == .falseAlarm }.count, run.falseAlarms)
            XCTAssertEqual(run.verdicts.values.filter { $0 == .miss }.count, run.misses)
            XCTAssertEqual(run.errors, run.verdicts.values.filter { $0 == .falseAlarm || $0 == .miss }.count)
        }
    }

    func testCloudLatencyIsMostlyNetworkForTheDecisionAPI() {
        let cloud = AgentProfile.lineup[1].typical
        XCTAssertGreaterThan(cloud.network, cloud.inference)
        XCTAssertEqual(AgentProfile.lineup[0].typical.network, 0)
    }

    func testCascadeIsFasterThanCloudOnly() {
        let local = AgentProfile.lineup[0].typical
        let cloud = AgentProfile.lineup[2].typical
        XCTAssertLessThan(Cascade.averageLatency(local: local, cloud: cloud, escalation: 0.1), cloud.total)
        XCTAssertEqual(Cascade.averageLatency(local: local, cloud: cloud, escalation: 0), local.total)
    }

    func testSwarmBuildsEveryLayerOnce() {
        var engine = SwarmEngine(agentCount: 8)
        engine.advance(to: .greatestFiniteMagnitude)
        XCTAssertTrue(engine.isFinished)
        XCTAssertEqual(engine.builtAt.compactMap { $0 }.count, engine.layers.count)
        XCTAssertTrue(engine.agents.allSatisfy { $0.layer == nil })
    }

    func testMoreAgentsFinishFaster() {
        let one = SwarmEngine.completionTime(agentCount: 1)
        let eight = SwarmEngine.completionTime(agentCount: 8)
        let thirtyTwo = SwarmEngine.completionTime(agentCount: 32)
        XCTAssertLessThan(eight, one / 4)
        XCTAssertLessThan(thirtyTwo, eight)
    }

    func testPunctuationAfterALinkSticksToIt() {
        let article = Article(title: "T", markup: ["A [web|s], then [rain|n]."])
        let tokens = article.paragraphs[0]
        XCTAssertEqual(tokens.map(\.text), ["A", "web", ",", "then", "rain", "."])
        XCTAssertEqual(tokens.map(\.joinsPrevious), [false, false, true, false, false, true])
        XCTAssertEqual(article.relevance, [true, false])
    }

    @MainActor
    func testEveryLinkGetsAPlaceInTheLayout() {
        for article in [Article.english, Article.portuguese] {
            for width in [140.0, 320.0, 520.0] {
                let layout = ArticleLayout(article: article, width: width, fontSize: 10, linkColor: .blue, textColor: .black)
                XCTAssertFalse(layout.linkRects.contains { $0.isNull }, "\(article.title) @ \(width)")
                XCTAssertTrue(layout.linkRects.allSatisfy { $0.maxY < layout.height })
                XCTAssertGreaterThan(layout.rect(globalLink: article.relevance.count).minY, layout.rect(globalLink: 0).minY)
            }
        }
    }

    func testSwarmPredictionMatchesASteppedRun() {
        let expected = SwarmEngine.completionTime(agentCount: 6)
        var engine = SwarmEngine(agentCount: 6)
        var t = 0.0
        while !engine.isFinished { t += 1.0 / 60; engine.advance(to: t) }
        XCTAssertEqual(engine.completionTime ?? 0, expected, accuracy: 1e-9)
    }

    func testDefaultTuningKeepsTheOriginalTypicalLatencies() {
        for profile in AgentProfile.lineup {
            let tuned = profile.tuned(AgentTuning(profile: profile))
            XCTAssertEqual(tuned.typical.total, profile.typical.total, accuracy: 0.001, profile.name)
            XCTAssertEqual(tuned.kind, profile.kind)
            XCTAssertEqual(tuned.accuracy, profile.accuracy)
        }
    }

    func testFasterTuningMakesMoreDecisions() {
        var tunings = AgentTuning.defaults
        tunings[2].inference = 20          // Stratus becomes a quick cloud classifier
        tunings[2].queue = 0
        var slow = RaceEngine(relevance: Article.english.relevance, duration: 20)
        var fast = RaceEngine(profiles: AgentProfile.lineup(tuned: tunings), relevance: Article.english.relevance, duration: 20)
        slow.advance(to: 20)
        fast.advance(to: 20)
        XCTAssertGreaterThan(fast.runs[2].decisions, slow.runs[2].decisions * 2)
    }

    func testMovingAnAgentToTheDeviceRemovesTheNetwork() {
        var tuning = AgentTuning.defaults[1]
        tuning.kind = .local
        let profile = AgentProfile.lineup[1].tuned(tuning)
        XCTAssertEqual(profile.typical.network, 0)
        XCTAssertEqual(profile.kind, .local)
    }

    func testPerfectAccuracyNeverMakesMistakes() {
        let tunings = AgentTuning.defaults.map { tuning -> AgentTuning in
            var t = tuning; t.accuracy = 1; return t
        }
        var engine = RaceEngine(profiles: AgentProfile.lineup(tuned: tunings), relevance: Article.english.relevance, duration: 30)
        engine.advance(to: 30)
        for run in engine.runs {
            XCTAssertFalse(run.verdicts.values.contains(.falseAlarm))
            XCTAssertFalse(run.verdicts.values.contains(.miss))
        }
    }

    func testTuningIsClampedAndExpectedDecisionsMatchARace() {
        let wild = AgentTuning(kind: .cloud, inference: -5, network: 99_999, queue: -1, accuracy: 3)
        XCTAssertEqual(wild.clamped.inference, AgentTuning.inferenceRange.lowerBound)
        XCTAssertEqual(wild.clamped.network, AgentTuning.networkRange.upperBound)
        XCTAssertEqual(wild.clamped.accuracy, 1)
        var engine = RaceEngine(relevance: Article.english.relevance, duration: 30)
        engine.advance(to: 30)
        let predicted = AgentTuning.defaults[0].expectedDecisions(duration: 30, walkTime: engine.walkTime)
        XCTAssertEqual(Double(engine.runs[0].decisions), Double(predicted), accuracy: Double(predicted) * 0.05)
    }

    @MainActor
    func testLabSavesAndRestoresTunings() {
        let defaults = UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!
        let lab = AgentLab(defaults: defaults)
        XCTAssertFalse(lab.isCustomised)
        lab.tunings[3].accuracy = 0.75
        XCTAssertTrue(lab.isCustomised)
        XCTAssertEqual(AgentLab(defaults: defaults).tunings[3].accuracy, 0.75)
        lab.reset()
        XCTAssertEqual(AgentLab(defaults: defaults).tunings, AgentTuning.defaults)
    }

    func testLogSliderRoundTrips() {
        for value in [5.0, 34, 450, 2500] {
            let p = TuningScale.position(of: value, in: AgentTuning.inferenceRange, logarithmic: true)
            XCTAssertEqual(TuningScale.value(at: p, in: AgentTuning.inferenceRange, logarithmic: true), value, accuracy: value * 1e-9)
        }
        XCTAssertEqual(TuningScale.position(of: 0, in: AgentTuning.queueRange, logarithmic: false), 0)
    }

    @MainActor
    func testFrameStepIsCappedAfterASuspension() {
        XCTAssertEqual(FrameLoop.step(elapsed: .milliseconds(16)), 0.016, accuracy: 1e-9)
        XCTAssertEqual(FrameLoop.step(elapsed: .seconds(300)), FrameLoop.maxStep)
        XCTAssertEqual(FrameLoop.step(elapsed: .seconds(-5)), 0)
    }

    @MainActor
    func testLabIgnoresSavedDataFromAnotherLineUp() {
        let defaults = UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!
        defaults.set(try! JSONEncoder().encode([AgentTuning.defaults[0]]), forKey: "agentTunings")
        XCTAssertEqual(AgentLab(defaults: defaults).tunings, AgentTuning.defaults)
        defaults.set(Data("not json".utf8), forKey: "agentTunings")
        XCTAssertEqual(AgentLab(defaults: defaults).tunings, AgentTuning.defaults)
    }

    func testNetworkSampleSplitsTheSystemTimestamps() {
        let t0 = Date(timeIntervalSince1970: 0)
        func at(_ ms: Double) -> Date { t0.addingTimeInterval(ms / 1000) }
        let sample = NetworkSample(domainLookupStart: at(0), domainLookupEnd: at(10), connectStart: at(10),
                                   secureConnectionStart: at(40), secureConnectionEnd: at(90), connectEnd: at(90),
                                   requestStart: at(91), responseStart: at(151), responseEnd: at(153), reusedConnection: false)
        XCTAssertEqual(sample.dns, 10, accuracy: 0.001)
        XCTAssertEqual(sample.tcp, 30, accuracy: 0.001)
        XCTAssertEqual(sample.tls, 50, accuracy: 0.001)
        XCTAssertEqual(sample.server, 60, accuracy: 0.001)
        XCTAssertEqual(sample.transfer, 2, accuracy: 0.001)
        XCTAssertEqual(sample.handshake, 90, accuracy: 0.001)

        // A reused connection has no handshake timestamps at all.
        let reused = NetworkSample(domainLookupStart: nil, domainLookupEnd: nil, connectStart: nil, secureConnectionStart: nil,
                                   secureConnectionEnd: nil, connectEnd: nil, requestStart: at(0), responseStart: at(40),
                                   responseEnd: at(41), reusedConnection: true)
        XCTAssertEqual(reused.handshake, 0)
        XCTAssertEqual(reused.total, 41, accuracy: 0.001)

        let average = NetworkSample.average([sample, reused])
        XCTAssertEqual(average?.total ?? 0, (sample.total + reused.total) / 2, accuracy: 0.001)
        XCTAssertEqual(average?.reusedConnection, false)
        XCTAssertNil(NetworkSample.average([]))

        // A redirect is two transactions: the first pays the handshake, the second reuses the connection.
        let redirected = NetworkSample.combined([sample, reused])
        XCTAssertEqual(redirected?.handshake ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(redirected?.total ?? 0, sample.total + reused.total, accuracy: 0.001)
        XCTAssertEqual(redirected?.reusedConnection, false)
    }

    func testArticleLinksKeepWholeTerms() {
        let links = Article.english.links
        XCTAssertEqual(links.count, Article.english.relevance.count)
        XCTAssertEqual(links.first, ArticleLink(text: "wolf spider", relevant: true))
        XCTAssertTrue(links.contains(ArticleLink(text: "hydraulic system", relevant: true)))
    }

    func testOnDeviceEncoderIsRealFastAndHonest() throws {
        let classifier = try XCTUnwrap(EmbeddingClassifier(), "English word embedding missing on this system")
        XCTAssertTrue(classifier.isAboutSpiders("wolf spider"))
        XCTAssertTrue(classifier.isAboutSpiders("arachnids"))
        XCTAssertFalse(classifier.isAboutSpiders("rain"))
        XCTAssertFalse(classifier.isAboutSpiders("steel"))
        let run = classifier.run(on: Article.english.links, rounds: 5)
        XCTAssertEqual(run.decisions, Article.english.links.count)
        XCTAssertGreaterThan(run.accuracy, 0.6)
        XCTAssertTrue(run.averageMilliseconds.isFinite)
        XCTAssertGreaterThan(run.averageMilliseconds, 0)
    }

    func testMillisecondsKeepUsefulPrecision() {
        XCTAssertEqual(465.0.milliseconds, "465 ms")
        XCTAssertEqual(34.7.milliseconds, "34.7 ms")
        XCTAssertEqual(0.25.milliseconds, "0.25 ms")
        XCTAssertEqual(0.004.milliseconds, "4 µs")
        XCTAssertEqual(0.0.milliseconds, "0 ms")
    }

    @MainActor
    func testNetworkPresetOnlyChangesCloudAgents() {
        let lab = AgentLab(defaults: UserDefaults(suiteName: "lab-test-\(UUID().uuidString)")!)
        lab.setCloudNetwork(480)
        for (i, tuning) in lab.tunings.enumerated() {
            XCTAssertEqual(tuning.network, tuning.kind == .cloud ? 480 : AgentTuning.defaults[i].network)
        }
        XCTAssertEqual(lab.activeNetworkPreset([40, 480]), 480)
        lab.tunings[1].network = 300
        XCTAssertNil(lab.activeNetworkPreset([40, 480]))
    }

    @MainActor
    func testShareCardRendersAnImage() {
        let card = ShareCard(eyebrow: "Test", title: "Title",
                             rows: [.init(colorIndex: 0, name: "Ember", detail: "local", value: "12", note: "34 ms")],
                             footnote: "Power of AI Agents")
        XCTAssertNotNil(card.image())
    }
    @MainActor
    private func finishMeasurement(_ model: MeasureModel) async {
        for _ in 0..<1000 {
            if !model.isRunning { return }
            await Task.yield()
        }
        XCTFail("Measurement did not finish")
        model.cancel()
    }

    @MainActor
    func testCancelledRequestCannotOverwriteRestartedMeasurement() async {
        var pending: [CheckedContinuation<(fresh: NetworkSample, reused: NetworkSample), Error>] = []
        let model = MeasureModel(network: {
            try await withCheckedThrowingContinuation { pending.append($0) }
        }, encode: { _, _ in nil }, availability: { .systemTooOld })
        model.measureAll()
        XCTAssertTrue(model.isRunning) // Prevent a second start before the task is scheduled.
        model.measureAll()
        for _ in 0..<100 { if pending.count == 1 { break }; await Task.yield() }
        XCTAssertEqual(pending.count, 1)
        guard pending.count == 1 else { model.cancel(); return }
        model.cancel()
        model.measureAll()
        for _ in 0..<100 { if pending.count == 2 { break }; await Task.yield() }
        guard pending.count == 2 else { XCTFail("Restart missing"); return }
        pending[0].resume(returning: (NetworkSample(server: 999), NetworkSample(server: 999)))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(model.isRunning)
        XCTAssertNil(model.fresh)
        XCTAssertFalse(model.networkFailed)
        model.cancel()
        pending[1].resume(throwing: URLError(.cancelled))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.networkFailed)
    }

    @MainActor
    func testRemeasureClearsOldResultsAndUsesTheSameSample() async {
        var fail = false
        var generated: [String] = []
        let model = MeasureModel(network: {
            if fail { throw URLError(.notConnectedToInternet) }
            return (NetworkSample(server: 100), NetworkSample(server: 50))
        }, encode: { links, _ in
            XCTAssertEqual(links, MeasureModel.benchmarkLinks(.english))
            return fail ? nil : ModelRun(decisions: links.count, correct: 4, totalMilliseconds: 12)
        }, generate: { term, _ in
            if fail { throw URLError(.unknown) }
            generated.append(term)
            return false
        }, availability: { nil })
        model.measureAll()
        await finishMeasurement(model)
        XCTAssertEqual(generated, MeasureModel.benchmarkLinks(.english).map(\.text))
        XCTAssertEqual(model.networkSampleCount, 3)
        XCTAssertNotNil(model.generative)
        fail = true
        model.measureAll()
        XCTAssertFalse(model.hasResults)
        await finishMeasurement(model)
        XCTAssertNil(model.fresh)
        XCTAssertNil(model.encoder)
        XCTAssertNil(model.generative)
        XCTAssertTrue(model.networkFailed)
        XCTAssertTrue(model.generativeFailed)
        XCTAssertTrue(model.encoderUnavailable)
    }

    @MainActor
    func testPartialNetworkResultsReportActualSampleCount() async {
        var calls = 0
        let model = MeasureModel(network: {
            calls += 1
            if calls > 1 { throw URLError(.timedOut) }
            return (NetworkSample(server: 200), NetworkSample(server: 80))
        }, encode: { _, _ in nil }, availability: { .systemTooOld })
        model.measureAll()
        await finishMeasurement(model)
        XCTAssertEqual(model.networkSampleCount, 1)
        XCTAssertEqual(model.fresh?.total, 200)
        XCTAssertTrue(model.networkFailed)
    }

    @MainActor
    func testApplyingMeasurementsCopiesAccuracyAndLocalExecution() async {
        let suite = "lab-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lab = AgentLab(defaults: defaults)
        lab.tunings[0].kind = .cloud
        lab.tunings[3].kind = .cloud
        let model = MeasureModel(network: {
            (NetworkSample(server: 400), NetworkSample(server: 100))
        }, encode: { links, _ in
            ModelRun(decisions: links.count, correct: 3, totalMilliseconds: 0.048)
        }, generate: { _, _ in false }, availability: { nil })
        model.apply(to: lab)
        XCTAssertFalse(model.appliedToLab)
        model.measureAll()
        await finishMeasurement(model)
        model.apply(to: lab)
        XCTAssertEqual(lab.tunings[0].kind, .local)
        XCTAssertEqual(lab.tunings[0].inference, 0.004, accuracy: 0.000001)
        XCTAssertEqual(lab.tunings[0].accuracy, 0.25)
        XCTAssertEqual(lab.tunings[0].queue, 0)
        XCTAssertEqual(lab.tunings[3].kind, .local)
        XCTAssertEqual(lab.tunings[3].accuracy, model.generative?.accuracy)
        XCTAssertEqual(lab.tunings[1].network, 400)
        XCTAssertEqual(lab.measuredNetwork, 400)
        XCTAssertTrue(model.appliedToLab)
    }

    func testEmptyEmbeddingBenchmarkHasFiniteResults() throws {
        let classifier = try XCTUnwrap(EmbeddingClassifier())
        for run in [classifier.run(on: [], rounds: 5), classifier.run(on: Article.english.links, rounds: 0)] {
            XCTAssertEqual(run.decisions, 0)
            XCTAssertEqual(run.averageMilliseconds, 0)
            XCTAssertEqual(run.accuracy, 0)
        }
    }

    @MainActor
    func testCancellingEncoderDoesNotStartGenerationOrPublishResults() async {
        var pending: CheckedContinuation<ModelRun?, Never>?
        var generated = false
        let model = MeasureModel(network: {
            (NetworkSample(server: 100), NetworkSample(server: 50))
        }, encode: { _, _ in
            await withCheckedContinuation { pending = $0 }
        }, generate: { _, _ in generated = true; return true }, availability: { nil })
        model.measureAll()
        for _ in 0..<100 { if pending != nil { break }; await Task.yield() }
        guard let pending else { XCTFail("Encoder did not start"); model.cancel(); return }
        model.cancel()
        pending.resume(returning: ModelRun(decisions: 12, correct: 12, totalMilliseconds: 1))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertNil(model.encoder)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(generated)
        XCTAssertFalse(model.generativeFailed)
    }

    func testSwarmLayerCompletionIsIndependentOfFrameSteps() {
        for count in [1, 12, 32] {
            var direct = SwarmEngine(agentCount: count)
            direct.advance(to: 1000)
            var stepped = SwarmEngine(agentCount: count)
            while !stepped.isFinished { stepped.advance(to: stepped.time + 0.1) }
            XCTAssertEqual(direct.builtAt, stepped.builtAt)
            XCTAssertEqual(direct.completionTime, stepped.completionTime)
        }
    }

    func testZeroAccuracyCountsBothKindsOfError() {
        let tunings = AgentTuning.defaults.map { tuning in
            var result = tuning
            result.accuracy = 0
            return result
        }
        var engine = RaceEngine(profiles: AgentProfile.lineup(tuned: tunings), relevance: [true, false], duration: 20)
        engine.advance(to: 20)
        for run in engine.runs {
            XCTAssertGreaterThan(run.misses, 0)
            XCTAssertGreaterThan(run.falseAlarms, 0)
            XCTAssertEqual(run.errors, run.decisions)
            XCTAssertEqual(run.finds, 0)
        }
    }

    @MainActor
    func testMeasuredNetworkPresetSurvivesARelaunch() {
        let suite = "lab-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(AgentLab(defaults: defaults).measuredNetwork)
        AgentLab(defaults: defaults).measuredNetwork = 87
        XCTAssertEqual(AgentLab(defaults: defaults).measuredNetwork, 87)
        defaults.set(-1.0, forKey: "measuredNetwork")
        XCTAssertNil(AgentLab(defaults: defaults).measuredNetwork)
    }

    @MainActor
    func testModelResultsApplyEvenWhenTheNetworkFails() async {
        let suite = "lab-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lab = AgentLab(defaults: defaults)
        let model = MeasureModel(network: { throw URLError(.notConnectedToInternet) },
                                 encode: { links, _ in ModelRun(decisions: links.count, correct: links.count, totalMilliseconds: 0.12) },
                                 availability: { .systemTooOld })
        model.measureAll()
        await finishMeasurement(model)
        XCTAssertTrue(model.networkFailed)
        XCTAssertNil(model.fresh)
        XCTAssertTrue(model.hasResults)
        model.apply(to: lab)
        XCTAssertTrue(model.appliedToLab)
        XCTAssertEqual(lab.tunings[0].accuracy, 1)
        XCTAssertEqual(lab.tunings[1].network, AgentTuning.defaults[1].network)
        XCTAssertNil(lab.measuredNetwork)
    }

    func testPortugueseEncoderSplitsHyphenatedCompounds() throws {
        let classifier = try XCTUnwrap(EmbeddingClassifier(language: .portuguese), "Portuguese word embedding missing on this system")
        XCTAssertTrue(classifier.isAboutSpiders("aranha-lobo"))
        XCTAssertTrue(classifier.isAboutSpiders("aranhas-saltadoras"))
        XCTAssertTrue(classifier.isAboutSpiders("seda de aranha"))
        XCTAssertFalse(classifier.isAboutSpiders("chuva"))
        XCTAssertFalse(classifier.isAboutSpiders("aço"))
        let run = classifier.run(on: MeasureModel.benchmarkLinks(.portuguese), rounds: 5)
        XCTAssertEqual(run.decisions, MeasureModel.benchmarkSize)
        XCTAssertGreaterThan(run.accuracy, 0.6)
        XCTAssertGreaterThan(run.averageMilliseconds, 0)
    }

    func testBenchmarkTermsFollowTheLanguageWithTheSameAnswers() {
        let english = MeasureModel.benchmarkLinks(.english)
        let portuguese = MeasureModel.benchmarkLinks(.portuguese)
        XCTAssertEqual(english.count, MeasureModel.benchmarkSize)
        XCTAssertEqual(portuguese.count, MeasureModel.benchmarkSize)
        XCTAssertEqual(english.map(\.relevant), portuguese.map(\.relevant))
        XCTAssertEqual(portuguese.first?.text, "aranha-lobo")
        XCTAssertEqual(english.first?.text, "wolf spider")
    }

    @MainActor
    func testMeasuringInPortugueseUsesPortugueseTermsAndRecordsTheLanguage() async {
        var encoded: [AppLanguage] = []
        var generated: [String] = []
        let model = MeasureModel(network: {
            (NetworkSample(server: 100), NetworkSample(server: 50))
        }, encode: { links, language in
            encoded.append(language)
            XCTAssertEqual(links, MeasureModel.benchmarkLinks(.portuguese))
            return ModelRun(decisions: links.count, correct: 9, totalMilliseconds: 0.05)
        }, generate: { term, language in
            XCTAssertEqual(language, .portuguese)
            generated.append(term)
            return true
        }, availability: { nil })
        model.measureAll(language: .portuguese)
        await finishMeasurement(model)
        XCTAssertEqual(encoded, [.portuguese])
        XCTAssertEqual(generated, MeasureModel.benchmarkLinks(.portuguese).map(\.text))
        XCTAssertEqual(model.sampleLanguage, .portuguese)
        XCTAssertEqual(model.encoder?.accuracy, 0.75)
    }

    func testGenerativeInstructionsMatchTheLanguage() {
        XCTAssertTrue(GenerativeClassifier.instructions(.portuguese).contains("aranhas"))
        XCTAssertTrue(GenerativeClassifier.instructions(.english).contains("spiders"))
    }
}
