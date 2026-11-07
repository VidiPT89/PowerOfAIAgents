import SwiftUI

/// A result card rendered to an image for sharing. It takes plain strings, so it renders the same
/// in any language or theme the app is using.
struct ShareCard: View {
    struct Row: Identifiable {
        let id = UUID()
        let colorIndex: Int
        let name: String
        let detail: String
        let value: String
        let note: String
    }

    let eyebrow: String
    let title: String
    let rows: [Row]
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(2.5)
                        .foregroundStyle(Brand.amber)
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0xE2E8F0))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Circle().fill(Brand.agentColor(row.colorIndex)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0xE2E8F0))
                            Text(row.detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0x94A3B8))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.value).font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(Color(hex: 0xE2E8F0))
                            Text(row.note).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0x94A3B8))
                        }
                    }
                    .padding(12)
                    .background(Color(hex: 0x12121F), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            HStack {
                Text(footnote).font(.system(size: 11)).foregroundStyle(Color(hex: 0x94A3B8))
                Spacer()
                Text("ividi.dev").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Brand.amber)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(hex: 0x0A0A0F))
        .overlay(alignment: .top) { Rectangle().fill(Brand.gradient).frame(height: 4) }
    }

    /// Renders the card at 3× for a crisp image on any screen.
    @MainActor
    func image() -> Image? {
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, .dark))
        renderer.scale = 3
        guard let cgImage = renderer.cgImage else { return nil }
        return Image(decorative: cgImage, scale: 3)
    }
}

/// Share button for a rendered card.
struct ShareResultButton: View {
    @EnvironmentObject private var prefs: Preferences
    let image: Image

    var body: some View {
        ShareLink(item: image, preview: SharePreview("PowerOfAIAgents", image: image)) {
            Label(prefs.text("Partilhar", "Share"), systemImage: "square.and.arrow.up")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
