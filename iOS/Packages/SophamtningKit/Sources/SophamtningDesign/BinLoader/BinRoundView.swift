import SwiftUI

/// Kärlet i hemskärmens tomma läge och bredvid rubriken. Det spelar ett varv när det visas och står sedan still med
/// stängt lock. Ett tryck spelar ett nytt varv med nästa fraktion och en lätt vibration, och en av Sopors roliga texter
/// kommer fram i en pratbubbla som svävar uppåt och tonas bort efter cirka 2 sekunder. Varje tryck ger en ny bubbla, hur
/// snabbt man än trycker, och de som redan syns står kvar sin tid, högst tre åt gången. Ett tryck under ett varv låter
/// varvet spela klart. Det är dekoration: ingen slinga, så att slingan fortsatt betyder att något hämtas.
/// Med Reducera rörelse står kärlet still, och bubblan tonas bara in och ut på plats.
/// Dolt för VoiceOver. Visas en bubbla tillkännages texten.
public struct BinRoundView: View {
    private let firstRound: Date?
    private let reduceMotionOverride: Bool?
    private let maxWidth: CGFloat
    private let bubbleTip: HorizontalAlignment
    private let bubblePlacement: BinBubbleTimeline.Placement
    private let tapTrigger: Int
    @ScaledMetric(relativeTo: .largeTitle) private var scaledWidth: CGFloat = 135

    /// Största bredden, så att sökfältet under kärlet inte trycks långt ned med största text.
    public static let maxWidth: CGFloat = 200

    /// Kärlets bredd: den skalade bredden, högst `maxWidth`.
    public static func drawnWidth(scaled: CGFloat, maxWidth: CGFloat = maxWidth) -> CGFloat {
        min(scaled, maxWidth)
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Varvet som spelas eller spelades senast. Styr fraktionen.
    @State private var round = 0
    /// När det pågående varvet startade. `nil` när kärlet står still.
    @State private var roundStart: Date?
    @State private var playedFirst = false
    @State private var taps = 0
    /// Bubblorna som syns. Varje tryck lägger till en, och var och en syns sin egen tid.
    @State private var bubbles = BinBubbleStack()
    /// Ingen text upprepas förrän alla visats, och två tryck i rad ger aldrig samma text.
    @State private var texts = BinLoaderTexts.Queue()

    /// - Parameters:
    ///   - firstRound: När första varvet ska spelas. `nil` väntar, till exempel medan hemskärmen väntar på introt.
    ///     Ett datum som redan passerat spelar direkt.
    ///   - width: Kärlets bredd. Växer med textstorleken som logotypen, högst till `maxWidth`.
    ///   - maxWidth: Största bredden med stor text.
    ///   - bubbleTip: Var bubblan står i förhållande till kärlet: mitt över, eller med vänsterkanten vid kärlet.
    ///   - bubblePlacement: Om spetsen står ovanför locket eller ovanför hela kärlet.
    ///   - tapTrigger: Ökar när något annat än kärlet ska räknas som ett tryck på det, till exempel rubriken bredvid.
    ///     Det ger samma sak som ett tryck på kärlet.
    ///   - reduceMotion: Tvingar läget. Utan värde läses `accessibilityReduceMotion`.
    public init(firstRound: Date?, width: CGFloat = 135, maxWidth: CGFloat = BinRoundView.maxWidth, bubbleTip: HorizontalAlignment = .center, bubblePlacement: BinBubbleTimeline.Placement = .overLid, tapTrigger: Int = 0, reduceMotion: Bool? = nil) {
        self.firstRound = firstRound
        self.maxWidth = maxWidth
        self.bubbleTip = bubbleTip
        self.bubblePlacement = bubblePlacement
        self.tapTrigger = tapTrigger
        reduceMotionOverride = reduceMotion
        _scaledWidth = ScaledMetric(wrappedValue: width, relativeTo: .largeTitle)
    }

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var width: CGFloat { Self.drawnWidth(scaled: scaledWidth, maxWidth: maxWidth) }

    public var body: some View {
        figure
            .contentShape(BinBodyShape())
            .onTapGesture { tapped() }
            .onChange(of: tapTrigger) { _, _ in tapped() }
            .overlay(alignment: Alignment(horizontal: bubbleTip, vertical: .top)) { bubble }
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
                if !reduceMotion { roundStart = Date() }
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
            .task(id: bubbles.nextExpiry) {
                // Den äldsta bubblan har tonats bort. Nästa får en ny väntan, eftersom `nextExpiry` då ändras.
                guard let expiry = bubbles.nextExpiry else { return }
                let left = expiry.timeIntervalSinceNow
                if left > 0 {
                    guard (try? await Task.sleep(for: .seconds(left))) != nil else { return }
                }
                withAnimation(stackAnimation) { bubbles.removeExpired(at: Date()) }
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

    /// Hur bubblorna flyttar sig när en ny kommer eller en försvinner. Med Reducera rörelse byter de plats direkt.
    private var stackAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }

    /// Bubblorna står med spetsen ovanför locket, eller ovanför hela kärlet, och svävar uppåt därifrån. Underkanten står
    /// fast, så att en bubbla med flera rader växer uppåt och aldrig täcker kärlet. Flera bubblor staplas: den nyaste
    /// står närmast kärlet och skjuter de äldre utåt. Bara den nyaste har en spets, men alla har plats för den, så att
    /// stapeln inte hoppar när en ny kommer.
    @ViewBuilder
    private var bubble: some View {
        if !bubbles.bubbles.isEmpty {
            let tipY = BinBubbleTimeline.tipY(binWidth: width, placement: bubblePlacement)
            // En linje utan höjd i kärlets överkant. Bubblans underkant står på linjen och flyttas sedan till spetsens
            // plats, så att bubblan växer uppåt oavsett hur många rader den har.
            // Under kärlet står bubblans överkant på linjen i stället, och den växer och svävar nedåt.
            let below = bubblePlacement.isBelow
            Color.clear
                .frame(height: 0)
                .overlay(alignment: Alignment(horizontal: bubbleTip, vertical: below ? .top : .bottom)) {
                    // Den nyaste närmast kärlet: överst när bubblorna står under kärlet, annars nederst.
                    let stack = below ? Array(bubbles.bubbles.reversed()) : bubbles.bubbles
                    let newest = bubbles.bubbles.last?.id
                    VStack(alignment: bubbleTip, spacing: 4) {
                        ForEach(stack) { item in
                            TimelineView(.animation) { context in
                                let elapsed = context.date.timeIntervalSince(item.start)
                                BinSpeechBubble(text: item.text, tip: bubbleTip, pointsUp: below, showsTip: item.id == newest)
                                    .scaleEffect(BinBubbleTimeline.scale(at: elapsed, reduceMotion: reduceMotion), anchor: UnitPoint(x: bubbleTip == .leading ? 0 : 0.5, y: below ? 0 : 1))
                                    .opacity(BinBubbleTimeline.opacity(at: elapsed))
                                    .offset(y: (below ? 1 : -1) * BinBubbleTimeline.rise(at: elapsed, reduceMotion: reduceMotion))
                            }
                            // Bubblan tonas in av sin egen tidslinje. En som får lämna plats i förtid tonas bort.
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        }
                    }
                    // Linjen har ingen höjd. Utan det här får varje bubbla höjden 0, och de hamnar ovanpå varandra.
                    .fixedSize()
                }
                .offset(y: tipY)
                .allowsHitTesting(false)
        }
    }

    /// Ett tryck: alltid en ny bubbla med nästa text och en vibration, hur snabbt man än trycker. Bubblan läggs till
    /// bland dem som redan syns. Ett nytt varv bara om kärlet står still.
    private func tapped() {
        let now = Date()
        if BinBubbleTimeline.startsRound(roundElapsed: roundStart.map { now.timeIntervalSince($0) }, reduceMotion: reduceMotion) {
            // Ett tryck före det första varvet ersätter det, så att inget varv spelas två gånger.
            if playedFirst { round += 1 }
            roundStart = now
        }
        playedFirst = true
        taps += 1
        var generator = SystemRandomNumberGenerator()
        let text = texts.next(using: &generator)
        withAnimation(stackAnimation) { bubbles.add(text, at: now) }
        // Kärlet och bubblan är dolda för VoiceOver, så texten tillkännages i stället, med låg prioritet.
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
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
        BinRoundView(firstRound: .distantPast, width: 30, maxWidth: 56, bubbleTip: .leading, bubblePlacement: .aboveBin)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.Theme.bg)
}
