import SwiftUI

struct CreditsView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 8) {
            Text(prefs.text("Desenvolvido por David Arsénio Martins", "Developed by David Arsénio Martins"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.text(scheme))
            HStack(spacing: 14) {
                Link("ividi.dev", destination: URL(string: "https://ividi.dev/")!)
                Text("·").foregroundStyle(Brand.faint(scheme))
                Link("github.com/VidiPT89", destination: URL(string: "https://github.com/VidiPT89/")!)
            }
            .font(.footnote.monospaced())
            .tint(Brand.accent(scheme))
        }
        .multilineTextAlignment(.center)
    }
}

/// Orbiting agents around a glowing core: the app's mark.
struct AgentsOrbit: View {
    var size: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let r = min(canvas.width, canvas.height) * 0.4
                for ring in 1...3 {
                    let rr = r * Double(ring) / 3
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                                   with: .color(Brand.amber.opacity(0.16)),
                                   style: StrokeStyle(lineWidth: 1, dash: ring == 2 ? [3, 6] : []))
                }
                var points: [CGPoint] = []
                for i in 0..<8 {
                    let ring = Double(i % 3 + 1) / 3
                    let speed = 0.35 / ring
                    let a = Double(i) * .pi / 4 + t * speed * (i.isMultiple(of: 2) ? 1 : -1)
                    points.append(CGPoint(x: c.x + cos(a) * r * ring, y: c.y + sin(a) * r * ring))
                }
                for p in points {
                    var line = Path(); line.move(to: c); line.addLine(to: p)
                    context.stroke(line, with: .color(Brand.orange.opacity(0.22)), lineWidth: 1)
                }
                for (i, p) in points.enumerated() {
                    let pulse = 4 + 1.5 * sin(t * 3 + Double(i))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - pulse * 2, y: p.y - pulse * 2, width: pulse * 4, height: pulse * 4)),
                                 with: .color(Brand.agentColor(i).opacity(0.18)))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - pulse, y: p.y - pulse, width: pulse * 2, height: pulse * 2)),
                                 with: .color(Brand.agentColor(i)))
                }
                let core = r * 0.3
                context.fill(Path(ellipseIn: CGRect(x: c.x - core * 1.6, y: c.y - core * 1.6, width: core * 3.2, height: core * 3.2)),
                             with: .radialGradient(Gradient(colors: [Brand.orange.opacity(0.45), .clear]),
                                                   center: c, startRadius: 0, endRadius: core * 1.6))
                context.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)),
                             with: .linearGradient(Gradient(colors: [Brand.amber, Brand.deepOrange]),
                                                   startPoint: CGPoint(x: c.x - core, y: c.y - core),
                                                   endPoint: CGPoint(x: c.x + core, y: c.y + core)))
                context.draw(Text("AI").font(.system(size: core * 0.8, weight: .black, design: .rounded)).foregroundStyle(.black.opacity(0.85)), at: c)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SplashView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let finish: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("iVidi.dev / LAB")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Brand.accent(scheme))
            AgentsOrbit(size: 240)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
            Text("Power of AI Agents")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.text(scheme))
                .multilineTextAlignment(.center)
            Text(prefs.text("Local contra cloud. Física, não magia.", "Local versus cloud. Physics, not magic."))
                .font(.subheadline)
                .foregroundStyle(Brand.dim(scheme))
                .padding(.top, 8)
            Spacer()
            CreditsView()
                .padding(.bottom, 18)
            Button(prefs.text("Entrar", "Enter"), action: finish)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Brand.dim(scheme))
                .padding(.bottom, 26)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background(scheme).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .task {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { appeared = true }
            guard (try? await Task.sleep(for: .seconds(3.2))) != nil else { return }
            finish()
        }
    }
}
