import CoreGraphics
import Foundation

enum LayerKind: Sendable {
    case surface, sidebar, navItem, text, heading, button, input, chip, icon, avatar, row, cell, card, spark
}

/// One piece of the interface the swarm builds. Coordinates are normalised (0...1).
struct SwarmLayer: Sendable, Identifiable {
    let id: Int
    let rect: CGRect
    let kind: LayerKind
}

enum Blueprint {
    /// A review dashboard, broken into the layers a team of agents would lay down one by one.
    static func dashboard() -> [SwarmLayer] {
        var layers: [SwarmLayer] = []
        func add(_ kind: LayerKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            layers.append(SwarmLayer(id: layers.count, rect: CGRect(x: x, y: y, width: w, height: h), kind: kind))
        }
        add(.surface, 0, 0, 1, 1)
        // Sidebar
        add(.sidebar, 0, 0, 0.17, 1)
        add(.heading, 0.02, 0.025, 0.1, 0.03)
        add(.icon, 0.135, 0.025, 0.02, 0.03)
        add(.input, 0.015, 0.075, 0.14, 0.035)
        for i in 0..<9 {
            let y = 0.135 + Double(i) * 0.055
            add(.navItem, 0.01, y, 0.15, 0.042)
            add(.icon, 0.02, y + 0.009, 0.016, 0.024)
            add(.text, 0.045, y + 0.013, 0.07 + Double(i % 3) * 0.015, 0.016)
        }
        add(.avatar, 0.02, 0.93, 0.03, 0.04)
        add(.text, 0.06, 0.94, 0.08, 0.018)
        // Top bar
        add(.surface, 0.17, 0, 0.83, 0.07)
        add(.heading, 0.19, 0.022, 0.11, 0.028)
        for i in 0..<3 { add(.chip, 0.33 + Double(i) * 0.09, 0.02, 0.08, 0.032) }
        for i in 0..<3 { add(.icon, 0.86 + Double(i) * 0.035, 0.022, 0.022, 0.028) }
        add(.avatar, 0.965, 0.018, 0.026, 0.036)
        // Title block
        add(.heading, 0.19, 0.095, 0.2, 0.034)
        add(.text, 0.19, 0.14, 0.5, 0.016)
        add(.button, 0.83, 0.095, 0.07, 0.036)
        add(.button, 0.91, 0.095, 0.075, 0.036)
        // KPI cards
        for i in 0..<4 {
            let x = 0.19 + Double(i) * 0.2
            add(.card, x, 0.18, 0.185, 0.12)
            add(.text, x + 0.012, 0.195, 0.08, 0.014)
            add(.heading, x + 0.012, 0.22, 0.06, 0.034)
            add(.chip, x + 0.13, 0.195, 0.042, 0.022)
            add(.spark, x + 0.012, 0.265, 0.16, 0.025)
        }
        // Filters
        add(.input, 0.19, 0.325, 0.3, 0.04)
        add(.icon, 0.2, 0.333, 0.016, 0.024)
        for i in 0..<4 { add(.chip, 0.51 + Double(i) * 0.095, 0.327, 0.085, 0.036) }
        add(.button, 0.9, 0.325, 0.085, 0.04)
        // Tabs
        for i in 0..<3 { add(.chip, 0.19 + Double(i) * 0.1, 0.385, 0.09, 0.03) }
        // Table
        let columns: [Double] = [0.19, 0.31, 0.43, 0.57, 0.69, 0.81, 0.91]
        let widths: [Double] = [0.11, 0.11, 0.13, 0.11, 0.11, 0.09, 0.07]
        add(.card, 0.19, 0.425, 0.795, 0.555)
        add(.row, 0.19, 0.425, 0.795, 0.04)
        for c in columns.indices { add(.text, columns[c] + 0.01, 0.438, widths[c] * 0.6, 0.016) }
        for r in 0..<13 {
            let y = 0.47 + Double(r) * 0.038
            add(.row, 0.19, y, 0.795, 0.036)
            for c in columns.indices {
                let kind: LayerKind = c == 0 ? .avatar : (c == 5 ? .chip : .cell)
                let width = kind == .avatar ? 0.018 : widths[c] * (0.55 + Double((r * 7 + c * 3) % 5) * 0.08)
                add(kind, columns[c] + 0.01, y + 0.008, width, 0.02)
            }
        }
        // Pagination
        for i in 0..<6 { add(.chip, 0.73 + Double(i) * 0.043, 0.965, 0.035, 0.022) }
        add(.text, 0.2, 0.968, 0.12, 0.015)
        return layers
    }
}

struct SwarmAgent: Sendable {
    let id: Int
    var position: CGPoint
    var from: CGPoint
    var layer: Int?
    var travelStart = 0.0
    var travelEnd = 0.0
    var buildEnd = 0.0
    var built = 0

    func location(at time: Double) -> CGPoint {
        guard layer != nil, time < travelEnd, travelEnd > travelStart else { return position }
        let t = max(0, min(1, (time - travelStart) / (travelEnd - travelStart)))
        let eased = t * t * (3 - 2 * t)
        return CGPoint(x: from.x + (position.x - from.x) * eased, y: from.y + (position.y - from.y) * eased)
    }

    func isBuilding(at time: Double) -> Bool { layer != nil && time >= travelEnd && time < buildEnd }
}

/// Pure swarm simulation: agents take the next layer from a shared queue, fly there and build it.
struct SwarmEngine: Sendable {
    let layers: [SwarmLayer]
    /// Seconds to cross the whole canvas.
    let travelTime: Double
    let buildTime: ClosedRange<Double>
    private(set) var agents: [SwarmAgent]
    private(set) var builtAt: [Double?]
    private(set) var time = 0.0
    private var queue = 0
    private var rng: SeededRandom

    init(layers: [SwarmLayer] = Blueprint.dashboard(), agentCount: Int, travelTime: Double = 0.55, buildTime: ClosedRange<Double> = 0.18...0.45, seed: UInt64 = 11) {
        self.layers = layers
        self.travelTime = travelTime
        self.buildTime = buildTime
        rng = SeededRandom(seed: seed)
        builtAt = Array(repeating: nil, count: layers.count)
        let count = max(1, agentCount)
        agents = (0..<count).map { i in
            let start = CGPoint(x: 0.5 + 0.3 * cos(Double(i) / Double(count) * 2 * .pi),
                                y: 1.08 + 0.04 * sin(Double(i)))
            return SwarmAgent(id: i, position: start, from: start)
        }
        for i in agents.indices { assign(agent: i, at: 0) }
    }

    var builtCount: Int { builtAt.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }
    var isFinished: Bool { builtCount == layers.count }

    var completionTime: Double? { isFinished ? builtAt.compactMap { $0 }.max() : nil }

    /// How long the same blueprint takes with a given number of agents, simulated to the end.
    static func completionTime(agentCount: Int, seed: UInt64 = 11) -> Double {
        var engine = SwarmEngine(agentCount: agentCount, seed: seed)
        engine.advance(to: .greatestFiniteMagnitude)
        return engine.completionTime ?? 0
    }

    mutating func advance(to target: Double) {
        guard target > time else { return }
        var progressed = true
        while progressed {
            progressed = false
            // Complete the earliest finishing build first, so the queue order stays fair.
            let next = agents.indices
                .filter { agents[$0].layer != nil && agents[$0].buildEnd <= target }
                .min { agents[$0].buildEnd < agents[$1].buildEnd }
            if let i = next, let layer = agents[i].layer {
                let finishedAt = agents[i].buildEnd
                builtAt[layer] = finishedAt
                agents[i].built += 1
                agents[i].layer = nil
                assign(agent: i, at: finishedAt)
                progressed = true
            }
        }
        time = target
    }

    private mutating func assign(agent i: Int, at moment: Double) {
        guard queue < layers.count else {
            agents[i].layer = nil
            return
        }
        let layer = queue
        queue += 1
        let rect = layers[layer].rect
        let target = CGPoint(x: rect.midX, y: rect.midY)
        let from = agents[i].position
        let distance = hypot(target.x - from.x, target.y - from.y)
        agents[i].from = from
        agents[i].position = target
        agents[i].layer = layer
        agents[i].travelStart = moment
        agents[i].travelEnd = moment + Double(distance) * travelTime
        agents[i].buildEnd = agents[i].travelEnd + rng.uniform(buildTime)
    }
}
