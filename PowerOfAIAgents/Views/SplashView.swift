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

/// The app's logo: a lightning bolt wrapped by a web of robotic spider agents.
struct LogoMark: View {
    var size: CGFloat = 200
    var glows = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(.white.opacity(0.08)))
            .shadow(color: Brand.orange.opacity(glows ? (pulse ? 0.55 : 0.25) : 0.18), radius: size * (pulse ? 0.16 : 0.1))
            .onAppear {
                guard glows, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)
    }
}

struct SplashView: View {
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.colorScheme) private var scheme
    let finish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("iVidi.dev / LAB")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Brand.accent(scheme))
            LogoMark(size: 190, glows: true)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
                .padding(.vertical, 26)
            Text("Power of AI Agents")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.text(scheme))
                .multilineTextAlignment(.center)
            Text(prefs.text("Local contra nuvem. Física, não magia.", "Local versus cloud. Physics, not magic."))
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
            withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.7)) { appeared = true }
            guard (try? await Task.sleep(for: .seconds(3.2))) != nil else { return }
            finish()
        }
    }
}
