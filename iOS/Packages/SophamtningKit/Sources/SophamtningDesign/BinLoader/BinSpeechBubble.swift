import SwiftUI

/// Pratbubblan med en av Sopors roliga texter, som kärlet säger vid ett tryck. Spetsen pekar ned mot kärlet.
/// Bubblan är dekoration och dold för VoiceOver. Texten tillkännages i stället av kärlet när bubblan visas.
public struct BinSpeechBubble: View {
    let text: String
    /// Var spetsen står i bubblans bredd, så att den pekar på kärlet.
    let tip: HorizontalAlignment

    public init(text: String, tip: HorizontalAlignment = .center) {
        self.text = text
        self.tip = tip
    }

    /// Smal nog att stå ovanför kärlet. Med större text bryts den på fler rader i samma bredd.
    private let maxWidth: CGFloat = 220

    public var body: some View {
        VStack(alignment: tip, spacing: -1) {
            Text(text)
                .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.Theme.border))
                .frame(maxWidth: maxWidth, alignment: Alignment(horizontal: tip, vertical: .center))
            BubbleTip()
                .fill(Color.Theme.surface)
                .overlay(BubbleTip().stroke(Color.Theme.border, lineWidth: 1))
                .frame(width: 14, height: 8)
                .padding(.horizontal, 12)
        }
        .fixedSize()
        // Bubblan är kort och tillfällig, så den växer högst till den största vanliga textstorleken och täcker inte
        // rubriken eller skärmen med tillgänglighetsstorlekar.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}

/// Spetsen under bubblan: en triangel som pekar nedåt. Övre kanten ritas inte, så att den går ihop med bubblan.
private struct BubbleTip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

#Preview("Pratbubblan") {
    VStack(spacing: 24) {
        BinSpeechBubble(text: "Plattar till pizzakartongen…")
        BinSpeechBubble(text: "Hoppas på att grannen har plats…", tip: .leading)
    }
    .padding()
    .background(Color.Theme.bg)
}
