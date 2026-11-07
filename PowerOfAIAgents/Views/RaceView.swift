import CoreText
import SwiftUI

@MainActor
final class RaceModel: ObservableObject {
    static let durations: [Double] = [10, 20, 30, 60]

    @Published private(set) var engine: RaceEngine
    @Published private(set) var running = false
    @Published var duration: Double = 20 { didSet { if duration != oldValue { reset() } } }
    private var clock = 0.0
    private let loop = FrameLoop()
    private var seed: UInt64 = 7
    private(set) var profiles = AgentProfile.lineup

    init() {
        engine = RaceEngine(relevance: Article.english.relevance, duration: 20, seed: 7)
    }

    /// Restarts the race with new agent settings from the lab.
    func configure(_ profiles: [AgentProfile]) {
        let changed = profiles.map(\.id) != self.profiles.map(\.id) || zip(profiles, self.profiles).contains { !$0.sameSettings(as: $1) }
        guard changed else { return }
        self.profiles = profiles
        reset()
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
        seed &+= 1
        engine = RaceEngine(profiles: profiles, relevance: Article.english.relevance, duration: duration, seed: seed)
    }
}

/// Word positions of the article for one panel width, measured once with Core Text.
struct ArticleLayout {
    struct Line {
        let y: CGFloat
        let text: AttributedString
    }

    let lines: [Line]
    let linkRects: [CGRect]
    let height: CGFloat
    let fontSize: CGFloat
    let lineHeight: CGFloat

    init(article: Article, width: CGFloat, fontSize: CGFloat, linkColor: Color, textColor: Color) {
        self.fontSize = fontSize
        lineHeight = (fontSize * 1.55).rounded()
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        func measure(_ string: String) -> CGFloat {
            let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
        }
        let space = measure(" ")
        let maxWidth = max(60, width)
        var lines: [Line] = []
        var rects = Array(repeating: CGRect.null, count: article.relevance.count)
        var y: CGFloat = lineHeight * 0.4

        // Title, wrapped like the body but in a larger serif.
        let titleSize = fontSize * 1.5
        let titleFont = CTFontCreateWithName("Georgia-Bold" as CFString, titleSize, nil)
        func measureTitle(_ string: String) -> CGFloat {
            let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): titleFont])
            return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
        }
        var titleLine = ""
        for word in article.title.split(separator: " ") {
            let candidate = titleLine.isEmpty ? String(word) : titleLine + " " + word
            if !titleLine.isEmpty, measureTitle(candidate) > maxWidth {
                lines.append(Line(y: y, text: Self.titleText(titleLine, size: titleSize, color: textColor)))
                y += titleSize * 1.3
                titleLine = String(word)
            } else {
                titleLine = candidate
            }
        }
        lines.append(Line(y: y, text: Self.titleText(titleLine, size: titleSize, color: textColor)))
        y += titleSize * 1.8

        for paragraph in article.paragraphs {
            var current = AttributedString()
            var x: CGFloat = 0
            for token in paragraph {
                let w = measure(token.text)
                if x > 0, x + w > maxWidth, !token.joinsPrevious {
                    lines.append(Line(y: y, text: current))
                    current = AttributedString()
                    x = 0
                    y += lineHeight
                }
                if x > 0, !token.joinsPrevious {
                    current += AttributedString(" ")
                    x += space
                }
                var word = AttributedString(token.text)
                word.foregroundColor = token.link == nil ? textColor : linkColor
                current += word
                if let link = token.link {
                    let rect = CGRect(x: x, y: y, width: w, height: lineHeight * 0.8)
                    rects[link] = rects[link].isNull ? rect : (abs(rects[link].minY - y) < 1 ? rects[link].union(rect) : rects[link])
                }
                x += w
            }
            if !current.characters.isEmpty { lines.append(Line(y: y, text: current)) }
            y += lineHeight * 1.6
        }
        self.lines = lines
        linkRects = rects
        height = y + lineHeight
    }

    private static func titleText(_ string: String, size: CGFloat, color: Color) -> AttributedString {
        var title = AttributedString(string)
        title.font = .custom("Georgia-Bold", size: size)
        title.foregroundColor = color
        return title
    }

    /// Where a global link (counting laps) sits in the endless, repeating article.
    func rect(globalLink index: Int) -> CGRect {
        let count = linkRects.count
        let base = linkRects[index % count]
        return base.offsetBy(dx: 0, dy: CGFloat(index / count) * height)
    }
}

struct RaceView: View {
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var lab: AgentLab
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: RaceModel
    @State private var showLab = false
    @State private var shareImage: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    eyebrow: prefs.text("Corrida em tempo real", "Real-time race"),
                    title: prefs.text("Quatro agentes, uma página", "Four agents, one page"),
                    subtitle: prefs.text(
                        "Cada robô percorre o artigo e decide, ligação a ligação, se fala de aranhas. Todos andam à mesma velocidade: só muda o tempo que demoram a decidir.",
                        "Each robot crawls the article and decides, link by link, whether it is about spiders. They all walk at the same speed: only the time they need to decide changes."))
                controls
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(model.engine.profiles[(row * 2)..<(row * 2 + 2)]) { profile in
                                RacePanel(profile: profile, run: model.engine.runs[profile.id], engine: model.engine)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: panelHeight)
                            }
                        }
                    }
                }
                Scoreboard(engine: model.engine, shareImage: shareImage)
                Text(prefs.text(
                    "Simulação ilustrativa: os nomes dos modelos são fictícios e as latências usam ordens de grandeza reais (rede, TLS, filas e inferência).",
                    "Illustrative simulation: model names are fictional and latencies use real-world orders of magnitude (network, TLS, queues and inference)."))
                    .font(.caption)
                    .foregroundStyle(Brand.faint(scheme))
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.background(scheme).ignoresSafeArea())
        .sensoryFeedback(.success, trigger: model.engine.isFinished) { _, finished in finished }
        .onAppear { if model.engine.isFinished { shareImage = shareCard.image() } }
        .onChange(of: model.engine.isFinished) { _, finished in shareImage = finished ? shareCard.image() : nil }
        .onChange(of: prefs.language) { _, _ in if model.engine.isFinished { shareImage = shareCard.image() } }
        .sheet(isPresented: $showLab) {
            AgentLabView(duration: model.duration, walkTime: model.engine.walkTime)
                .environmentObject(prefs)
                .environmentObject(lab)
                .preferredColorScheme(prefs.appearance.scheme)
        }
    }

    /// The final scoreboard as an image for sharing.
    private var shareCard: ShareCard {
        let engine = model.engine
        let rows = engine.ranking.map { index in
            let profile = engine.profiles[index]
            let run = engine.runs[index]
            return ShareCard.Row(
                colorIndex: profile.id,
                name: profile.name,
                detail: "\(profile.kind == .local ? "local" : prefs.text("nuvem", "cloud")) · \(run.averageLatency.milliseconds)",
                value: prefs.text("\(run.finds) achados", "\(run.finds) finds"),
                note: prefs.text("\(run.decisions) decisões", "\(run.decisions) decisions"))
        }
        return ShareCard(eyebrow: prefs.text("Corrida de agentes", "Agent race"),
                         title: prefs.text("Quatro agentes, uma página, \(Int(engine.duration)) segundos", "Four agents, one page, \(Int(engine.duration)) seconds"),
                         rows: rows,
                         footnote: prefs.text("Simulação ilustrativa · Power of AI Agents", "Illustrative simulation · Power of AI Agents"))
    }

    private var panelHeight: CGFloat {
        #if os(macOS)
        return 300
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? 320 : 250
        #endif
    }

    /// One row when it fits, otherwise the timing controls drop to a second row (narrow iPhones, English labels).
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                actionButtons
                Spacer(minLength: 0)
                timing
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) { actionButtons }
                HStack { timing }
            }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button {
            model.toggle()
        } label: {
            Label(model.running ? prefs.text("Pausa", "Pause") : (model.hasStarted && !model.engine.isFinished ? prefs.text("Continuar", "Resume") : prefs.text("Iniciar corrida", "Start race")),
                  systemImage: model.running ? "pause.fill" : "play.fill")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.space, modifiers: [])

        Button {
            model.reset()
        } label: {
            Label(prefs.text("Repor", "Reset"), systemImage: "arrow.counterclockwise")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    @ViewBuilder private var timing: some View {
        Button {
            model.pause()
            showLab = true
        } label: {
            Label(prefs.text("Ajustar", "Tune"), systemImage: "slider.horizontal.3")
                .lineLimit(1)
                .fixedSize()
                .overlay(alignment: .topTrailing) {
                    if lab.isCustomised {
                        Circle().fill(Brand.orange).frame(width: 7, height: 7).offset(x: 9, y: -7)
                    }
                }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityHint(lab.isCustomised ? prefs.text("Valores personalizados", "Custom values") : "")

        Menu {
            ForEach(RaceModel.durations, id: \.self) { value in
                Button("\(Int(value)) s") { model.duration = value }
            }
        } label: {
            Label("\(Int(model.duration)) s", systemImage: "timer")
                .font(.subheadline.monospacedDigit())
        }
        .fixedSize()

        Text(String(format: "%05.2f s", model.engine.time))
            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
            .foregroundStyle(Brand.accent(scheme))
            .fixedSize()
            .frame(minWidth: 70, alignment: .trailing)
    }
}

struct RacePanel: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let profile: AgentProfile
    let run: AgentRun
    let engine: RaceEngine

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Brand.agentColor(profile.id)).frame(width: 9, height: 9)
                        Text(profile.name)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Brand.text(scheme))
                            .lineLimit(1)
                    }
                    KindTag(kind: profile.kind)
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(run.finds)")
                        .font(.system(.title2, design: .rounded, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Brand.text(scheme))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: run.finds)
                    Text(prefs.text("achados", "finds"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.dim(scheme))
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            GeometryReader { proxy in
                PageCanvas(profile: profile, run: run, engine: engine, size: proxy.size)
            }
            .background(Color(hex: scheme == .dark ? 0x15151F : 0xFFFFFF))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 8)
            HStack {
                metric(prefs.text("decisões", "decisions"), "\(run.decisions)")
                Spacer()
                metric(prefs.text("média", "average"), run.decisions == 0 ? "—" : run.averageLatency.milliseconds)
                Spacer()
                metric(prefs.text("erros", "errors"), "\(run.falseAlarms)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Brand.panel(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Brand.agentColor(profile.id).opacity(0.35)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name), \(profile.kind == .local ? "local" : prefs.text("nuvem", "cloud")), \(run.finds) \(prefs.text("achados", "finds")), \(run.decisions) \(prefs.text("decisões", "decisions"))")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.caption, design: .monospaced, weight: .semibold)).foregroundStyle(Brand.text(scheme))
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Brand.faint(scheme))
        }
    }
}

/// The article, the verdict boxes and the robot, drawn in a single Canvas.
struct PageCanvas: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let profile: AgentProfile
    let run: AgentRun
    let engine: RaceEngine
    let size: CGSize

    @MainActor private static var cache: [String: ArticleLayout] = [:]

    private var layout: ArticleLayout {
        let fontSize: CGFloat = size.width < 220 ? 8.5 : (size.width < 360 ? 10 : 11.5)
        let key = "\(prefs.language.rawValue)-\(Int(size.width))-\(fontSize)-\(scheme == .dark)"
        if let cached = Self.cache[key] { return cached }
        // Window resizes on the Mac create a new width every frame; keep the cache small.
        if Self.cache.count > 16 { Self.cache.removeAll() }
        let layout = ArticleLayout(article: Article.sample(prefs.language), width: size.width - 24, fontSize: fontSize,
                                   linkColor: scheme == .dark ? Color(hex: 0x7DB4FF) : Color(hex: 0x2457C5),
                                   textColor: scheme == .dark ? Color(hex: 0xC9CED8) : Color(hex: 0x2A2A2A))
        Self.cache[key] = layout
        return layout
    }

    var body: some View {
        let layout = layout
        let time = engine.time
        let color = Brand.agentColor(profile.id)
        Canvas { context, canvas in
            let inset: CGFloat = 12
            let spider = spiderPosition(layout: layout, time: time)
            let scroll = max(0, spider.y - canvas.height * 0.48)
            let lapHeight = layout.height

            // Article text, repeated for every lap the agent has started.
            let firstLap = Int(scroll / lapHeight)
            for lap in firstLap...(firstLap + 1) {
                let base = CGFloat(lap) * lapHeight - scroll
                for line in layout.lines {
                    let y = base + line.y
                    guard y > -layout.lineHeight * 2, y < canvas.height + layout.lineHeight else { continue }
                    context.draw(Text(line.text).font(.system(size: layout.fontSize)), at: CGPoint(x: inset, y: y), anchor: .topLeading)
                }
            }

            // Verdict boxes for links this agent has already judged.
            let low = max(0, run.linkIndex - 60)
            if run.linkIndex > low {
                for index in low..<run.linkIndex {
                    guard let verdict = run.verdicts[index] else { continue }
                    let rect = layout.rect(globalLink: index).offsetBy(dx: inset, dy: -scroll).insetBy(dx: -3, dy: -2)
                    guard rect.maxY > 0, rect.minY < canvas.height else { continue }
                    let shape = Path(roundedRect: rect, cornerRadius: 3)
                    switch verdict {
                    case .hit:
                        context.fill(shape, with: .color(Brand.ok.opacity(0.14)))
                        context.stroke(shape, with: .color(Brand.ok), lineWidth: 1.6)
                    case .falseAlarm:
                        context.fill(shape, with: .color(Brand.danger.opacity(0.12)))
                        context.stroke(shape, with: .color(Brand.danger), lineWidth: 1.6)
                    case .miss:
                        context.stroke(shape, with: .color(Brand.danger.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    case .pass:
                        var underline = Path()
                        underline.move(to: CGPoint(x: rect.minX + 3, y: rect.maxY - 1))
                        underline.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 1))
                        context.stroke(underline, with: .color(Brand.faint(scheme).opacity(0.5)), lineWidth: 1)
                    }
                }
            }

            let position = CGPoint(x: spider.x + inset, y: spider.y - scroll)
            let robotSize = min(canvas.width, canvas.height) * 0.32

            // Cloud agents: the request travels to the data centre and back.
            if case let .deciding(start, end, latency) = run.phase, profile.kind == .cloud, end > start {
                drawNetwork(context: &context, canvas: canvas, from: position, progress: (time - start) / (end - start), latency: latency, color: color)
            }

            var walking = false
            var thinking: Double?
            switch run.phase {
            case .walking: walking = true
            case let .deciding(start, end, _): thinking = end > start ? (time - start) / (end - start) : 1
            case .finished: break
            }
            SpiderBot.draw(in: &context, at: position, size: robotSize, color: color, time: time, walking: walking, scheme: scheme)
            if let thinking {
                let r = robotSize * 0.26
                let ring = Path { p in
                    p.addArc(center: position, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(1, thinking)), clockwise: false)
                }
                context.stroke(ring, with: .color(Brand.amber), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .drawingGroup()
    }

    /// The robot crawls from the previous link to the current one, then waits there while deciding.
    private func spiderPosition(layout: ArticleLayout, time: Double) -> CGPoint {
        let target = layout.rect(globalLink: run.linkIndex)
        let to = CGPoint(x: target.midX, y: target.midY)
        guard case let .walking(start, end) = run.phase, run.linkIndex > 0, end > start else { return to }
        let previous = layout.rect(globalLink: run.linkIndex - 1)
        let from = CGPoint(x: previous.midX, y: previous.midY)
        let t = max(0, min(1, (time - start) / (end - start)))
        let eased = t * t * (3 - 2 * t)
        return CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased)
    }

    private func drawNetwork(context: inout GraphicsContext, canvas: CGSize, from: CGPoint, progress: Double, latency: LatencyBreakdown, color: Color) {
        let server = CGPoint(x: canvas.width - 22, y: 20)
        var line = Path()
        line.move(to: from)
        line.addQuadCurve(to: server, control: CGPoint(x: (from.x + server.x) / 2, y: min(from.y, server.y) - 30))
        context.stroke(line, with: .color(Brand.cloud.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        context.fill(Path(roundedRect: CGRect(x: server.x - 16, y: server.y - 11, width: 32, height: 22), cornerRadius: 6), with: .color(Brand.cloud.opacity(0.2)))
        context.draw(Image(systemName: "cloud.fill"), in: CGRect(x: server.x - 10, y: server.y - 8, width: 20, height: 16))

        let total = max(latency.total, 1)
        let outbound = latency.network / 2 / total
        let atServer = (latency.queue + latency.inference) / total
        let packet: CGPoint
        if progress < outbound {
            packet = point(on: from, server, t: progress / outbound)
        } else if progress < outbound + atServer {
            packet = server
        } else {
            packet = point(on: server, from, t: (progress - outbound - atServer) / max(outbound, 0.0001))
        }
        context.fill(Path(ellipseIn: CGRect(x: packet.x - 4, y: packet.y - 4, width: 8, height: 8)), with: .color(Brand.amber))
        let stage = progress < outbound ? "TCP · TLS ↗" : (progress < outbound + atServer ? (latency.queue > latency.inference ? prefs.text("fila", "queue") : prefs.text("inferência", "inference")) : prefs.text("↙ resposta", "↙ response"))
        context.draw(Text(stage).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Brand.cloud),
                     at: CGPoint(x: server.x - 20, y: server.y + 22), anchor: .trailing)
    }

    private func point(on a: CGPoint, _ b: CGPoint, t: Double) -> CGPoint {
        let t = max(0, min(1, t))
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 30)
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                       y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
    }
}

/// A small mechanical spider drawn with paths: gear-like body, eight jointed legs.
enum SpiderBot {
    static func draw(in context: inout GraphicsContext, at c: CGPoint, size: CGFloat, color: Color, time: Double, walking: Bool, scheme: ColorScheme) {
        let body = size * 0.17
        let legColor = scheme == .dark ? Color(hex: 0x1E1E28) : Color(hex: 0x23232B)
        // Shadow
        context.fill(Path(ellipseIn: CGRect(x: c.x - size * 0.42, y: c.y + size * 0.1, width: size * 0.84, height: size * 0.2)),
                     with: .color(.black.opacity(scheme == .dark ? 0.35 : 0.12)))
        // Legs
        for i in 0..<8 {
            // Explicit CGFloat steps keep older Swift compilers within their type-checking budget.
            let spread: CGFloat = -0.75 + CGFloat(i % 4) * 0.5
            let baseAngle: CGFloat = i < 4 ? .pi - spread : spread
            let phase: Double = Double(i) * .pi / 2 + (i < 4 ? 0 : .pi / 4)
            let gait = CGFloat(walking ? sin(time * 18 + phase) : sin(time * 2 + Double(i)) * 0.15)
            let angle: CGFloat = baseAngle + gait * 0.18
            let dx: CGFloat = cos(angle)
            let dy: CGFloat = sin(angle)
            let hip = CGPoint(x: c.x + dx * body * 0.9, y: c.y + dy * body * 0.75)
            let kneeLift: CGFloat = size * 0.16 + gait * size * 0.03
            let knee = CGPoint(x: c.x + dx * size * 0.32, y: c.y + dy * size * 0.22 - kneeLift)
            let foot = CGPoint(x: c.x + dx * size * 0.48, y: c.y + dy * size * 0.3 + size * 0.06)
            var upper = Path(); upper.move(to: hip); upper.addLine(to: knee)
            var lower = Path(); lower.move(to: knee); lower.addLine(to: foot)
            context.stroke(upper, with: .color(color), style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
            context.stroke(lower, with: .color(legColor), style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: knee.x - size * 0.025, y: knee.y - size * 0.025, width: size * 0.05, height: size * 0.05)), with: .color(legColor))
            context.fill(Path(ellipseIn: CGRect(x: foot.x - size * 0.014, y: foot.y - size * 0.014, width: size * 0.028, height: size * 0.028)), with: .color(Brand.ok))
        }
        // Gear body
        var gear = Path()
        let teeth = 12
        for i in 0..<(teeth * 2) {
            let a = Double(i) / Double(teeth * 2) * 2 * .pi + time * (walking ? 2 : 0.4)
            let r = i.isMultiple(of: 2) ? body * 1.18 : body
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { gear.move(to: p) } else { gear.addLine(to: p) }
        }
        gear.closeSubpath()
        context.fill(gear, with: .color(color))
        context.stroke(gear, with: .color(.black.opacity(0.35)), lineWidth: 1)
        let inner = body * 0.62
        context.fill(Path(ellipseIn: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.95), color.opacity(0.9), legColor]),
                                           center: CGPoint(x: c.x - inner * 0.3, y: c.y - inner * 0.3), startRadius: 0, endRadius: inner * 1.3))
        // Eye
        let eye = body * 0.22
        context.fill(Path(ellipseIn: CGRect(x: c.x - eye, y: c.y - eye, width: eye * 2, height: eye * 2)), with: .color(legColor))
        context.fill(Path(ellipseIn: CGRect(x: c.x - eye * 0.4, y: c.y - eye * 0.4, width: eye * 0.8, height: eye * 0.8)), with: .color(Brand.amber))
    }
}

struct Scoreboard: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let engine: RaceEngine
    let shareImage: Image?

    var body: some View {
        let ranking = engine.ranking
        let best = max(1, engine.runs.map(\.decisions).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(prefs.text("Placar", "Scoreboard")).font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                if engine.isFinished,
                   let fastest = engine.runs.indices.max(by: { engine.runs[$0].decisions < engine.runs[$1].decisions }),
                   let slowest = engine.runs.indices.min(by: { engine.runs[$0].decisions < engine.runs[$1].decisions }),
                   fastest != slowest, engine.runs[slowest].decisions > 0 {
                    let ratio = Double(engine.runs[fastest].decisions) / Double(engine.runs[slowest].decisions)
                    Text(prefs.text("\(engine.profiles[fastest].name) decidiu \(String(format: "%.1f", ratio))× mais do que \(engine.profiles[slowest].name)",
                                    "\(engine.profiles[fastest].name) made \(String(format: "%.1f", ratio))× more decisions than \(engine.profiles[slowest].name)"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.accent(scheme))
                }
            }
            ForEach(Array(ranking.enumerated()), id: \.element) { place, index in
                let profile = engine.profiles[index]
                let run = engine.runs[index]
                HStack(spacing: 10) {
                    Text("\(place + 1).").font(.system(.subheadline, design: .monospaced, weight: .bold)).frame(width: 24, alignment: .leading)
                    Image(systemName: profile.kind == .local ? "cpu" : "cloud")
                        .font(.caption)
                        .foregroundStyle(profile.kind == .local ? Brand.orange : Brand.cloud)
                        .frame(width: 16)
                    Text(profile.name).font(.subheadline.weight(.semibold)).frame(width: 58, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Brand.panel2(scheme))
                            Capsule().fill(Brand.agentColor(profile.id).gradient)
                                .frame(width: max(6, proxy.size.width * CGFloat(run.decisions) / CGFloat(best)))
                                .animation(.easeOut(duration: 0.2), value: run.decisions)
                        }
                    }
                    .frame(height: 10)
                    Text("\(run.finds) / \(run.decisions)")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .frame(width: 58, alignment: .trailing)
                    Text(run.decisions == 0 ? "—" : run.averageLatency.milliseconds)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Brand.dim(scheme))
                        .frame(width: 66, alignment: .trailing)
                }
            }
            HStack {
                Text(prefs.text("achados / decisões · latência média por decisão", "finds / decisions · average latency per decision"))
                    .font(.caption2)
                    .foregroundStyle(Brand.faint(scheme))
                Spacer()
                if let shareImage { ShareResultButton(image: shareImage) }
            }
        }
        .card()
    }
}
