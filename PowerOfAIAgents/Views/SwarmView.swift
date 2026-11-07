import SwiftUI

@MainActor
final class SwarmModel: ObservableObject {
    @Published private(set) var engine: SwarmEngine
    @Published private(set) var running = false
    @Published var agentCount: Int = 12 { didSet { if agentCount != oldValue { reset() } } }
    /// The run is deterministic, so the finishing time is known before it starts.
    @Published private(set) var expectedTime: Double
    let soloTime = SwarmEngine.completionTime(agentCount: 1)
    private var clock = 0.0
    private let loop = FrameLoop()

    init() {
        engine = SwarmEngine(agentCount: 12)
        expectedTime = SwarmEngine.completionTime(agentCount: 12)
    }

    var hasStarted: Bool { engine.time > 0 }

    func toggle() { running ? pause() : start() }

    func start() {
        if engine.isFinished { reset() }
        guard !running else { return }
        running = true
        loop.start { [weak self] step in
            guard let self else { return false }
            self.clock += step
            self.engine.advance(to: self.clock)
            if self.engine.isFinished { self.running = false }
            return self.running
        }
    }

    func pause() {
        running = false
        loop.stop()
    }

    func reset() {
        pause()
        clock = 0
        engine = SwarmEngine(agentCount: agentCount)
        expectedTime = SwarmEngine.completionTime(agentCount: agentCount)
    }
}

struct SwarmView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: SwarmModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Agentes em paralelo", "Parallel agents"),
                    title: prefs.text("Um enxame a construir uma interface", "A swarm building an interface"),
                    subtitle: prefs.text(
                        "Cada cursor é um agente. Tiram a próxima camada de uma fila partilhada, voam até lá e constroem-na. Mais agentes, menos espera.",
                        "Each cursor is an agent. They take the next layer from a shared queue, fly there and build it. More agents, less waiting."))
                controls
                SwarmCanvas(engine: model.engine, summary: prefs.text("\(model.engine.builtCount) de \(model.engine.layers.count) camadas construídas por \(agentsText)", "\(model.engine.builtCount) of \(model.engine.layers.count) layers built by \(agentsText)"))
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.stroke(scheme)))
                statusPill
                    .frame(maxWidth: .infinity)
                stats
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
    }

    /// "1 agent", "12 agents".
    private var agentsText: String {
        let one = model.agentCount == 1
        return "\(model.agentCount) \(prefs.text(one ? "agente" : "agentes", one ? "agent" : "agents"))"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    model.toggle()
                } label: {
                    Label(model.running ? prefs.text("Pausa", "Pause") : (model.hasStarted && !model.engine.isFinished ? prefs.text("Continuar", "Resume") : prefs.text("Construir", "Build")),
                          systemImage: model.running ? "pause.fill" : "play.fill")
                    .lineLimit(1)
                    .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    model.reset()
                } label: {
                    Label(prefs.text("Repor", "Reset"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill").foregroundStyle(Brand.accent(scheme))
                Slider(value: Binding(get: { Double(model.agentCount) }, set: { model.agentCount = Int($0.rounded()) }), in: 1...32, step: 1)
                    .accessibilityLabel(prefs.text("Número de agentes", "Number of agents"))
                    .accessibilityValue("\(model.agentCount)")
                Text(agentsText)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .frame(minWidth: 96, alignment: .trailing)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            HStack(spacing: -3) {
                ForEach(0..<min(5, model.agentCount), id: \.self) { i in
                    Circle().fill(Brand.agentColor(i)).frame(width: 9, height: 9).overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
                }
            }
            Text(agentsText)
            Text("·").foregroundStyle(.white.opacity(0.4))
            Text("\(model.engine.builtCount) / \(model.engine.layers.count) \(prefs.text("camadas", "layers"))")
            ProgressView(value: Double(model.engine.builtCount), total: Double(model.engine.layers.count))
                .tint(Brand.orange)
                .frame(width: 70)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: 0x111118).opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1)))
    }

    private var stats: some View {
        let elapsed = model.engine.completionTime ?? model.engine.time
        return HStack(spacing: 12) {
            stat(prefs.text("Tempo", "Elapsed"), String(format: "%.1f s", elapsed),
                 detail: prefs.text(String(format: "previsto %.1f s", model.expectedTime), String(format: "expected %.1f s", model.expectedTime)))
            stat(prefs.text("Um só agente", "Single agent"), String(format: "%.0f s", model.soloTime))
            stat(prefs.text("Aceleração", "Speed-up"), String(format: "×%.1f", model.soloTime / max(model.expectedTime, 0.01)))
        }
    }

    private func stat(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(Brand.text(scheme))
            Text(label).font(.caption).foregroundStyle(Brand.dim(scheme))
            if let detail {
                Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(Brand.faint(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// The dashboard under construction, its layers and the agents' cursors.
struct SwarmCanvas: View {
    @Environment(\.colorScheme) private var scheme
    let engine: SwarmEngine
    let summary: String

    var body: some View {
        Canvas { context, size in
            let time = engine.time
            let finished = engine.isFinished
            let dark = scheme == .dark
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: dark ? 0x0E0E16 : 0xEDE8DF)))
            drawGrid(&context, size: size, dark: dark)

            func frame(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
            }

            for layer in engine.layers {
                guard let builtAt = engine.builtAt[layer.id] else { continue }
                let appear = finished ? 1 : min(1, (time - builtAt) / 0.25)
                draw(layer, in: frame(layer.rect), context: &context, opacity: max(0.2, appear), dark: dark)
            }

            // Layers being worked on: blue outline, size badge and a growing fill.
            for agent in engine.agents {
                guard let id = agent.layer, agent.isBuilding(at: time) else { continue }
                let layer = engine.layers[id]
                let rect = frame(layer.rect)
                let progress = (time - agent.travelEnd) / max(agent.buildEnd - agent.travelEnd, 0.01)
                draw(layer, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height), context: &context, opacity: 0.5, dark: dark)
                context.stroke(Path(rect), with: .color(Color(hex: 0x3B82F6)), lineWidth: 1)
                let label = "\(Int(layer.rect.width * 1440)) × \(Int(layer.rect.height * 900))"
                let badge = context.resolve(Text(label).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.white))
                let badgeSize = badge.measure(in: CGSize(width: 200, height: 20))
                let badgeRect = CGRect(x: rect.midX - badgeSize.width / 2 - 4, y: rect.maxY + 3, width: badgeSize.width + 8, height: badgeSize.height + 3)
                context.fill(Path(roundedRect: badgeRect, cornerRadius: 3), with: .color(Color(hex: 0x3B82F6)))
                context.draw(badge, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
            }

            // Cursors
            for agent in engine.agents {
                let p = agent.location(at: time)
                let point = CGPoint(x: p.x * size.width, y: p.y * size.height)
                guard point.y < size.height + 20 else { continue }
                let color = Brand.agentColor(agent.id)
                var arrow = Path()
                arrow.move(to: point)
                arrow.addLine(to: CGPoint(x: point.x + 3.5, y: point.y + 13))
                arrow.addLine(to: CGPoint(x: point.x + 6.5, y: point.y + 8))
                arrow.addLine(to: CGPoint(x: point.x + 12, y: point.y + 7))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(color))
                context.stroke(arrow, with: .color(.white), lineWidth: 1)
                if agent.isBuilding(at: time) {
                    let tag = context.resolve(Text("A\(agent.id + 1)").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.black))
                    let s = tag.measure(in: CGSize(width: 60, height: 20))
                    let r = CGRect(x: point.x + 10, y: point.y + 12, width: s.width + 6, height: s.height + 2)
                    context.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color))
                    context.draw(tag, at: CGPoint(x: r.midX, y: r.midY))
                }
            }
        }
        .drawingGroup()
        .accessibilityLabel(summary)
    }

    private func drawGrid(_ context: inout GraphicsContext, size: CGSize, dark: Bool) {
        var grid = Path()
        let step: CGFloat = 24
        var x: CGFloat = 0
        while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y: CGFloat = 0
        while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        context.stroke(grid, with: .color(dark ? .white.opacity(0.035) : .black.opacity(0.045)), lineWidth: 0.5)
    }

    private func draw(_ layer: SwarmLayer, in rect: CGRect, context: inout GraphicsContext, opacity: Double, dark: Bool) {
        guard rect.width > 0.5 else { return }
        var ctx = context
        ctx.opacity = opacity
        let ink = dark ? Color(hex: 0xC9CED8) : Color(hex: 0x3A3A44)
        switch layer.kind {
        case .surface:
            ctx.fill(Path(rect), with: .color(Color(hex: dark ? 0x161622 : 0xFBFAF7)))
        case .sidebar:
            ctx.fill(Path(rect), with: .color(Color(hex: 0x111118)))
        case .navItem:
            let active = abs(layer.rect.minY - 0.465) < 0.01
            ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(active ? Brand.orange : .white.opacity(0.04)))
        case .text:
            let onDark = layer.rect.minX < 0.17
            ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(onDark ? .white.opacity(0.55) : ink.opacity(0.35)))
        case .heading:
            let onDark = layer.rect.minX < 0.17
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(onDark ? Brand.amber : ink.opacity(0.85)))
        case .button:
            ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(layer.rect.minX > 0.9 ? Brand.orange : ink.opacity(0.12)))
        case .input:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(layer.rect.minX < 0.17 ? .white.opacity(0.08) : ink.opacity(0.06)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(ink.opacity(0.15)), lineWidth: 0.6)
        case .chip:
            ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(Brand.amber.opacity(0.28)))
        case .icon:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(layer.rect.minX < 0.17 ? Brand.orange.opacity(0.85) : ink.opacity(0.4)))
        case .avatar:
            ctx.fill(Path(ellipseIn: rect), with: .linearGradient(Gradient(colors: [Brand.amber, Brand.deepOrange]), startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        case .row:
            ctx.fill(Path(rect), with: .color(ink.opacity(0.035)))
            var line = Path(); line.move(to: CGPoint(x: rect.minX, y: rect.maxY)); line.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            ctx.stroke(line, with: .color(ink.opacity(0.1)), lineWidth: 0.5)
        case .cell:
            ctx.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: rect.height * 0.2), cornerRadius: 2), with: .color(ink.opacity(0.28)))
        case .card:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color(hex: dark ? 0x1C1C2A : 0xFFFFFF)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(ink.opacity(0.1)), lineWidth: 0.6)
        case .spark:
            var path = Path()
            for i in 0...12 {
                let x = rect.minX + rect.width * Double(i) / 12
                let y = rect.midY + sin(Double(i) * 0.9 + rect.minX * 40) * rect.height * 0.4
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(Brand.orange), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}
