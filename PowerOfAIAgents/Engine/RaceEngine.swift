import Foundation

/// Small deterministic generator, so a race with the same seed always plays out the same way.
struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        return Double.random(in: range, using: &self)
    }
}

enum AgentKind: String, Sendable { case local, cloud }

enum ModelFamily: Sendable {
    /// Non-autoregressive classifier: one forward pass, one calibrated probability.
    case encoder
    /// Generates text token by token before it can answer.
    case generative
}

/// Where every millisecond of one decision goes.
struct LatencyBreakdown: Sendable, Equatable {
    var tcp: Double = 0
    var tls: Double = 0
    var routing: Double = 0
    var queue: Double = 0
    var inference: Double = 0
    var network: Double { tcp + tls + routing }
    var total: Double { tcp + tls + routing + queue + inference }
}

struct AgentProfile: Identifiable, Sendable {
    let id: Int
    let name: String
    let kind: AgentKind
    let family: ModelFamily
    let size: String
    let tcp: ClosedRange<Double>
    let tls: ClosedRange<Double>
    let routing: ClosedRange<Double>
    let queue: ClosedRange<Double>
    let inference: ClosedRange<Double>
    let accuracy: Double

    var typical: LatencyBreakdown {
        LatencyBreakdown(tcp: tcp.mid, tls: tls.mid, routing: routing.mid, queue: queue.mid, inference: inference.mid)
    }

    func sample(using rng: inout SeededRandom) -> LatencyBreakdown {
        LatencyBreakdown(tcp: rng.uniform(tcp), tls: rng.uniform(tls), routing: rng.uniform(routing),
                         queue: rng.uniform(queue), inference: rng.uniform(inference))
    }

    /// Four illustrative agents. Names are fictional, figures are realistic orders of magnitude.
    static let lineup: [AgentProfile] = [
        AgentProfile(id: 0, name: "Ember", kind: .local, family: .encoder, size: "421M",
                     tcp: 0...0, tls: 0...0, routing: 0...0, queue: 0...2, inference: 30...38, accuracy: 0.96),
        AgentProfile(id: 1, name: "Nimbus", kind: .cloud, family: .encoder, size: "API",
                     tcp: 20...45, tls: 30...70, routing: 140...240, queue: 20...260, inference: 35...70, accuracy: 0.97),
        AgentProfile(id: 2, name: "Stratus", kind: .cloud, family: .generative, size: "LLM",
                     tcp: 20...45, tls: 30...70, routing: 140...240, queue: 40...300, inference: 380...720, accuracy: 0.98),
        AgentProfile(id: 3, name: "Flint", kind: .local, family: .generative, size: "3B",
                     tcp: 0...0, tls: 0...0, routing: 0...0, queue: 0...4, inference: 900...1500, accuracy: 0.9),
    ]
}

extension ClosedRange where Bound == Double {
    var mid: Double { (lowerBound + upperBound) / 2 }
}

enum Verdict: Sendable, Equatable {
    case hit            // relevant link, correctly flagged
    case falseAlarm     // irrelevant link flagged by mistake
    case miss           // relevant link the model let through
    case pass           // irrelevant link, correctly ignored
}

enum AgentPhase: Sendable, Equatable {
    case walking(start: Double, end: Double)
    case deciding(start: Double, end: Double, latency: LatencyBreakdown)
    case finished
}

struct AgentRun: Sendable {
    var linkIndex = 0           // global link counter; wraps around the article in laps
    var phase: AgentPhase = .walking(start: 0, end: 0)
    var verdicts: [Int: Verdict] = [:]
    var finds = 0
    var falseAlarms = 0
    var decisions = 0
    var latencySum = 0.0
    var averageLatency: Double { decisions == 0 ? 0 : latencySum / Double(decisions) }
}

/// Pure race simulation: every agent walks to the next link, then spends its real latency deciding.
struct RaceEngine: Sendable {
    let profiles: [AgentProfile]
    let relevance: [Bool]      // one entry per link in the article, true = about spiders
    let duration: Double
    /// Time the robot needs to crawl from one link to the next (the same for everyone).
    let walkTime: Double
    private(set) var runs: [AgentRun]
    private(set) var time: Double = 0
    private var rngs: [SeededRandom]

    init(profiles: [AgentProfile] = AgentProfile.lineup, relevance: [Bool], duration: Double, walkTime: Double = 0.2, seed: UInt64 = 7) {
        precondition(!relevance.isEmpty, "The article needs at least one link")
        self.profiles = profiles
        self.relevance = relevance
        self.duration = duration
        self.walkTime = walkTime
        runs = profiles.map { _ in AgentRun(phase: .walking(start: 0, end: walkTime)) }
        rngs = profiles.map { SeededRandom(seed: seed &* 31 &+ UInt64($0.id)) }
    }

    var isFinished: Bool { time >= duration }

    func isRelevant(globalLink index: Int) -> Bool { relevance[index % relevance.count] }

    mutating func advance(to target: Double) {
        let end = min(target, duration)
        guard end > time else { return }
        for i in runs.indices { step(agent: i, until: end) }
        time = end
        if time >= duration {
            for i in runs.indices { runs[i].phase = .finished }
        }
    }

    private mutating func step(agent i: Int, until end: Double) {
        while true {
            switch runs[i].phase {
            case .finished:
                return
            case let .walking(_, phaseEnd):
                guard phaseEnd <= end else { return }
                let latency = profiles[i].sample(using: &rngs[i])
                runs[i].phase = .deciding(start: phaseEnd, end: phaseEnd + latency.total / 1000, latency: latency)
            case let .deciding(_, phaseEnd, latency):
                guard phaseEnd <= end else { return }
                decide(agent: i, latency: latency)
                runs[i].linkIndex += 1
                runs[i].phase = .walking(start: phaseEnd, end: phaseEnd + walkTime)
            }
        }
    }

    private mutating func decide(agent i: Int, latency: LatencyBreakdown) {
        let relevant = isRelevant(globalLink: runs[i].linkIndex)
        let correct = Double.random(in: 0..<1, using: &rngs[i]) < profiles[i].accuracy
        let flagged = correct ? relevant : !relevant
        let verdict: Verdict = switch (relevant, flagged) {
        case (true, true): .hit
        case (false, true): .falseAlarm
        case (true, false): .miss
        case (false, false): .pass
        }
        runs[i].verdicts[runs[i].linkIndex] = verdict
        runs[i].decisions += 1
        runs[i].latencySum += latency.total
        if verdict == .hit { runs[i].finds += 1 }
        if verdict == .falseAlarm { runs[i].falseAlarms += 1 }
    }

    /// Agents ordered by correct finds, then by fewer mistakes.
    var ranking: [Int] {
        runs.indices.sorted { a, b in
            if runs[a].finds != runs[b].finds { return runs[a].finds > runs[b].finds }
            return runs[a].falseAlarms < runs[b].falseAlarms
        }
    }
}

/// Local-first cascade: the small model answers everything, the cloud only sees the low-confidence share.
enum Cascade {
    static func averageLatency(local: LatencyBreakdown, cloud: LatencyBreakdown, escalation: Double) -> Double {
        local.total + min(max(escalation, 0), 1) * cloud.total
    }
}
