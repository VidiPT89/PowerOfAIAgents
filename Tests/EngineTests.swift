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
        XCTAssertEqual(engine.agents.map(\.built).reduce(0, +), engine.layers.count)
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
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(FrameLoop.step(from: last, to: last.addingTimeInterval(0.016)), 0.016, accuracy: 1e-6)
        XCTAssertEqual(FrameLoop.step(from: last, to: last.addingTimeInterval(300)), FrameLoop.maxStep)
        XCTAssertEqual(FrameLoop.step(from: last, to: last.addingTimeInterval(-5)), 0)
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
        XCTAssertLessThan(run.averageMilliseconds, 5)
    }

    func testGenerativeAvailabilityNeverCrashes() {
        _ = GenerativeClassifier.unavailableReason
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
}
