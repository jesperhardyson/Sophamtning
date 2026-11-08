import SwiftUI

/// Sopors laddningsanimation: ett grönt kärl som öppnar locket, tar emot en fraktion, slår igen locket och gungar.
/// Allt räknas från klockan med `TimelineView`, så en omritning av vyn stör inte slingan. Med Reducera rörelse
/// står kärlet still med stängt lock och en fast text. VoiceOver läser alltid "Hämtar schema", aldrig de roliga texterna.
public struct BinLoaderView: View {
    private let reduceMotionOverride: Bool?
    private let width: CGFloat
    private let showsText: Bool
    private let textColor: Color

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()
    @State private var isOnScreen = true
    @State private var settled = false
    @State private var texts = TextSequence()

    /// - Parameters:
    ///   - reduceMotion: Tvingar läget. Utan värde läses `accessibilityReduceMotion`.
    ///   - width: Kärlets bredd. Höjden följer SVG:ns proportioner. Hemkortet använder 150, som på webben.
    ///   - showsText: Visar den roliga texten under kärlet. Av i små storlekar, där raden redan har egen text.
    ///   - textColor: Textens färg, som på webben `text-2`.
    public init(reduceMotion: Bool? = nil, width: CGFloat = 150, showsText: Bool = true, textColor: Color = Color.Theme.text2) {
        reduceMotionOverride = reduceMotion
        self.width = width
        self.showsText = showsText
        self.textColor = textColor
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hämtar schema")
            .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var content: some View {
        if reduceMotion {
            // Stilla kärl och en fast text. Bara den enkla toningen in finns kvar.
            layout(elapsed: 0, animated: false)
                .opacity(settled ? 1 : 0)
                .onAppear {
                    withAnimation(.easeOut(duration: BinLoaderTimeline.appearDuration).delay(BinLoaderTimeline.appearDelay)) {
                        settled = true
                    }
                }
        } else {
            // Slingan står still när appen inte är aktiv eller vyn inte syns.
            TimelineView(.animation(minimumInterval: nil, paused: scenePhase != .active || !isOnScreen)) { context in
                let elapsed = context.date.timeIntervalSince(start)
                layout(elapsed: elapsed, animated: true)
                    .opacity(BinLoaderTimeline.appearOpacity(at: elapsed))
            }
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
        }
    }

    private func layout(elapsed: TimeInterval, animated: Bool) -> some View {
        VStack(spacing: 16) {
            bin(elapsed: elapsed, animated: animated)
            if showsText {
                Text(animated ? texts.text(forCycle: BinLoaderTimeline.textCycle(at: elapsed)) : "Hämtar schema…")
                    .font(.ui(20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: 340)
                    .opacity(animated ? BinLoaderTimeline.textOpacity(at: elapsed) : 1)
            }
        }
    }

    private func bin(elapsed: TimeInterval, animated: Bool) -> some View {
        BinFigure(pose: animated ? BinLoaderTimeline.loopPose(at: elapsed) : .resting, width: width)
    }
}

/// Kärlet i ett givet läge. Ritas i SVG:ns eget mått (360 × 560) och skalas till `width`. Delas av slingan och tomt läge.
struct BinFigure: View {
    let pose: BinLoaderTimeline.Pose
    let width: CGFloat

    var body: some View {
        let box = BinArtwork.viewBox
        let scale = width / box.width
        let hinge = BinArtwork.local(BinArtwork.hinge)
        let pivot = BinArtwork.local(BinArtwork.bodyPivot)
        let behind = pose.lidIsBehindBody
        let lid = lid(angle: pose.lidAngle, hinge: hinge)
        return ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Color.Theme.surface2)
                .frame(width: BinArtwork.shadow.width, height: BinArtwork.shadow.height)
                .offset(x: BinArtwork.local(BinArtwork.shadow.origin).x, y: BinArtwork.local(BinArtwork.shadow.origin).y)
            ZStack(alignment: .topLeading) {
                if behind { lid }
                if pose.fraction.opacity > 0 { fraction(pose.fraction) }
                parts(BinArtwork.bodyParts)
                if !behind { lid }
            }
            .rotationEffect(
                .degrees(pose.bodySway),
                anchor: UnitPoint(x: pivot.x / box.width, y: pivot.y / box.height)
            )
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width, height: box.height * scale, alignment: .topLeading)
    }

    private func parts(_ parts: [BinArtwork.Part]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(parts.indices, id: \.self) { index in
                BinPartShape(path: parts[index].path)
                    .fill(parts[index].color)
            }
        }
        .frame(width: BinArtwork.viewBox.width, height: BinArtwork.viewBox.height, alignment: .topLeading)
    }

    private func lid(angle: Double, hinge: CGPoint) -> some View {
        parts(BinArtwork.lidParts)
            .rotationEffect(.degrees(angle), anchor: UnitPoint(x: hinge.x / BinArtwork.viewBox.width, y: hinge.y / BinArtwork.viewBox.height))
    }

    /// Fraktionens platta (88 × 88, radie 28, halvgenomskinlig) med ikon. Vrids runt SVG:ns origo och flyttas sedan.
    private func fraction(_ state: BinLoaderTimeline.FractionState) -> some View {
        let tile = BinFractionTile.all[state.index]
        let origin = BinArtwork.local(.zero)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .circular)
                .fill(tile.background.opacity(0.5))
                .frame(width: 88, height: 88)
            Image(tile.icon, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .frame(width: 44, height: 44)
                .foregroundStyle(tile.foreground)
                .offset(x: 22, y: 22)
        }
        .frame(width: 88, height: 88, alignment: .topLeading)
        .rotationEffect(.degrees(state.rotation), anchor: .topLeading)
        .offset(x: origin.x + state.x, y: origin.y + state.y)
        .opacity(state.opacity)
    }
}

/// En bana i SVG:ns koordinater, flyttad så att viewBox börjar i vyns övre vänstra hörn.
private struct BinPartShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(translationX: -BinArtwork.viewBox.minX, y: -BinArtwork.viewBox.minY))
    }
}

/// Fraktionerna i slingan, i webbens ordning: mat, papper, plast. Färgerna följer temat, som på webben.
private struct BinFractionTile {
    let icon: String
    let foreground: Color
    let background: Color

    static let all = [
        BinFractionTile(icon: "apple", foreground: Color.Theme.fracMat, background: Color.Theme.fracMatBg),
        BinFractionTile(icon: "package", foreground: Color.Theme.fracPapper, background: Color.Theme.fracPapperBg),
        BinFractionTile(icon: "cup-soda", foreground: Color.Theme.fracPlast, background: Color.Theme.fracPlastBg),
    ]
}

/// Textkön ligger i vyns tillstånd, så att samma text står kvar vid omritning. En ny text slumpas först när
/// cykeln byter, och ingen upprepas förrän alla visats.
@MainActor
private final class TextSequence {
    private var queue = BinLoaderTexts.Queue()
    private var drawn: [String] = []

    func text(forCycle cycle: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        while drawn.count <= cycle { drawn.append(queue.next(using: &generator)) }
        return drawn[cycle]
    }
}

#Preview("Kärlet laddar") {
    VStack(spacing: 24) {
        BinLoaderView()
        BinLoaderView(reduceMotion: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.Theme.bg)
}

#Preview("Kärlet laddar, mörkt") {
    VStack(spacing: 24) {
        BinLoaderView()
        BinLoaderView(reduceMotion: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.Theme.bg)
    .preferredColorScheme(.dark)
}
