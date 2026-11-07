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
}
