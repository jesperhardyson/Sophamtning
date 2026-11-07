import SophamtningDesign
import SwiftUI
import UIKit

/// Om introt redan har visats i den här processen. Det visas aldrig när appen kommer tillbaka från bakgrunden.
@MainActor
enum StartIntroState {
    private static var shown = false

    /// När processen startade, tagen i appens init.
    static let processStart = Date()

    /// Om det är en start från början, sett från nu. Läses när första bilden ritas.
    static var isFreshLaunch: Bool {
        StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: Date().timeIntervalSince(processStart))
    }

    /// Körs i appens init, innan första bilden. Svarar första gången och därefter aldrig: om introt ska visas och om hemskärmens kort ska komma in.
    static func claim() -> (intro: Bool, cards: Bool) {
        // Första åtkomsten tar starttiden, så den ska ske här i appens init och inte först när vyn visas.
        _ = processStart
        let arguments = ProcessInfo.processInfo.arguments
        let intro = StartIntroTimeline.shouldPlay(voiceOverRunning: UIAccessibility.isVoiceOverRunning, arguments: arguments, alreadyShown: shown)
        let cards = StartEntrance.shouldPlay(arguments: arguments, alreadyPlayed: shown)
        shown = true
        return (intro, cards)
    }
}

/// Överlägget direkt efter startskärmen. Första bilden är exakt startskärmen: samma bakgrundsfärg och samma logotyp i
/// samma storlek, mitt på skärmen, här i två lager som ihop är pixelidentiska med `LaunchLogo`. Hemskärmen ligger klar under och
/// hämtar sina data som vanligt. Ett tryck tar bort överlägget direkt, och när det börjar lämna går trycken igenom till hemskärmen.
struct StartIntroView: View {
    /// Introt börjar lämna skärmen, och hemskärmens kort ska komma in.
    let onExit: () -> Void
    let onFinish: () -> Void
    /// Appen öppnades långt efter att processen startade, och inget intro visas.
    let onNoFreshLaunch: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Klockan startar när första bilden har ritats, så att den ligger exakt som startskärmen även när appen startar långsamt.
    @State private var start: Date?
    /// Ökar när kalendern studsar, för den lätta vibrationen.
    @State private var bounces = 0
    /// Avgörs när vyn först visas. Startade processen i bakgrunden och appen öppnas långt senare visas inget intro, och
    /// överlägget är då helt genomskinligt och tar inga tryck, så hemskärmen aldrig täcks.
    @State private var fresh = StartIntroState.isFreshLaunch

    var body: some View {
        if fresh { intro } else { Color.clear.allowsHitTesting(false).accessibilityHidden(true).onAppear(perform: onNoFreshLaunch) }
    }

    private var intro: some View {
        TimelineView(.animation) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) } ?? 0
            let frame = StartIntroTimeline.frame(at: elapsed, reduceMotion: reduceMotion)
            ZStack {
                Color("LaunchBackground").opacity(frame.backgroundOpacity)
                ZStack {
                    Image("LaunchLogoRing")
                        .rotationEffect(.degrees(frame.ringRotation))
                    Image("LaunchLogoCalendar")
                        .scaleEffect(frame.calendarScale)
                }
                .scaleEffect(frame.scale)
                .opacity(frame.logoOpacity)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onFinish)
            .allowsHitTesting(StartIntroTimeline.capturesTouches(at: elapsed, reduceMotion: reduceMotion))
        }
        .onAppear { start = Date() }
        // Bara dekoration. Hemskärmen under är det som läses.
        .accessibilityHidden(true)
        .sensoryFeedback(.impact(weight: .light), trigger: bounces)
        .task { await play() }
    }

    /// Händelserna under introt, i tidsordning. Tas introt bort avbryts det som återstår.
    private func play() async {
        var now: TimeInterval = 0
        func wait(until time: TimeInterval) async -> Bool {
            do { try await Task.sleep(for: .seconds(max(0, time - now))) } catch { return false }
            now = time
            return true
        }
        if !reduceMotion {
            guard await wait(until: StartIntroTimeline.bounceStart) else { return }
            bounces += 1
        }
        guard await wait(until: StartIntroTimeline.exitStart(reduceMotion: reduceMotion)) else { return }
        onExit()
        guard await wait(until: StartIntroTimeline.duration(reduceMotion: reduceMotion)) else { return }
        onFinish()
    }
}
