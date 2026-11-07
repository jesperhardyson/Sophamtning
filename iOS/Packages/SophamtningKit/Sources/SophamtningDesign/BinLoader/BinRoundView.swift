import SwiftUI

/// Kärlet i hemskärmens tomma läge. Det spelar ett varv när det visas och står sedan still med stängt lock. Ett tryck
/// spelar ett nytt varv med nästa fraktion och en lätt vibration. Det är dekoration: ingen slinga och ingen text, så att
/// slingan fortsatt betyder att något hämtas. Med Reducera rörelse står det still och trycket gör inget.
/// Dolt för VoiceOver.
public struct BinRoundView: View {
    private let firstRound: Date?
    private let reduceMotionOverride: Bool?
    @ScaledMetric(relativeTo: .largeTitle) private var scaledWidth: CGFloat = 135

    /// Största bredden, så att sökfältet under kärlet inte trycks långt ned med största text.
    public static let maxWidth: CGFloat = 200

    /// Kärlets bredd: den skalade bredden, högst `maxWidth`.
    public static func drawnWidth(scaled: CGFloat) -> CGFloat {
        min(scaled, maxWidth)
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Varvet som spelas eller spelades senast. Styr fraktionen.
    @State private var round = 0
    /// När det pågående varvet startade. `nil` när kärlet står still.
    @State private var roundStart: Date?
    @State private var playedFirst = false
    @State private var taps = 0

    /// - Parameters:
    ///   - firstRound: När första varvet ska spelas. `nil` väntar, till exempel medan hemskärmen väntar på introt.
    ///     Ett datum som redan passerat spelar direkt.
    ///   - width: Kärlets bredd. Växer med textstorleken som logotypen, högst till `maxWidth`.
    ///   - reduceMotion: Tvingar läget. Utan värde läses `accessibilityReduceMotion`.
    public init(firstRound: Date?, width: CGFloat = 135, reduceMotion: Bool? = nil) {
        self.firstRound = firstRound
        reduceMotionOverride = reduceMotion
        _scaledWidth = ScaledMetric(wrappedValue: width, relativeTo: .largeTitle)
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var width: CGFloat { Self.drawnWidth(scaled: scaledWidth) }

    public var body: some View {
        figure
            .contentShape(BinBodyShape())
            .onTapGesture { playRound(tapped: true) }
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
            .task(id: firstRound) {
                guard let firstRound, !playedFirst else { return }
                let wait = firstRound.timeIntervalSinceNow
                if wait > 0 {
                    guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
                }
                // Ett tryck under väntan har redan spelat varvet.
                guard !playedFirst else { return }
                playedFirst = true
                playRound(tapped: false)
            }
            .task(id: roundStart) {
                // Varvet är slut: kärlet står still, och klockan stannar.
                guard let roundStart else { return }
                let left = BinLoaderTimeline.roundDuration - Date().timeIntervalSince(roundStart)
                if left > 0 {
                    guard (try? await Task.sleep(for: .seconds(left))) != nil else { return }
                }
                self.roundStart = nil
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var figure: some View {
        if let roundStart {
            TimelineView(.animation) { context in
                BinFigure(
                    pose: BinLoaderTimeline.roundPose(round: round, elapsed: context.date.timeIntervalSince(roundStart), reduceMotion: reduceMotion),
                    width: width
                )
            }
        } else {
            BinFigure(pose: .resting, width: width)
        }
    }

    /// Startar ett varv. Ett tryck under ett pågående varv gör inget, och med Reducera rörelse spelas inget.
    private func playRound(tapped: Bool) {
        guard roundStart == nil, !reduceMotion else { return }
        if tapped {
            // Ett tryck före det första varvet ersätter det, så att inget varv spelas två gånger.
            if playedFirst { round += 1 }
            playedFirst = true
            taps += 1
        }
        roundStart = Date()
    }
}

/// Trycket gäller bara själva kärlet, inte den tomma ytan ovanför där fraktionen faller.
private struct BinBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Kärlets kropp och lock i SVG:n: x 115 till 375, y 40 till 441, i en viewBox på 360 × 560 från (60, -110).
        let box = BinArtwork.viewBox
        let sx = rect.width / box.width
        let sy = rect.height / box.height
        return Path(CGRect(x: (115 - box.minX) * sx, y: (40 - box.minY) * sy, width: 260 * sx, height: 401 * sy))
    }
}

#Preview("Kärlet i tomt läge") {
    VStack(spacing: 24) {
        BinRoundView(firstRound: .distantPast)
        BinRoundView(firstRound: .distantPast, reduceMotion: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.Theme.bg)
}
