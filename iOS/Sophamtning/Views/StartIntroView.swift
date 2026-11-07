import SophamtningDesign
import SwiftUI
import UIKit

/// Om introt redan har visats i den här processen. Det visas aldrig när appen kommer tillbaka från bakgrunden.
@MainActor
enum StartIntroState {
    private static var shown = false

    /// När processen startade, tagen i appens init.
    static let processStart = Date()

    /// Körs i appens init, innan första bilden. Svarar sant första gången och därefter aldrig, och bara om introt ska visas alls.
    static func claim() -> Bool {
        // Första åtkomsten tar starttiden, så den ska ske här i appens init och inte först när vyn visas.
        _ = processStart
        let play = StartIntroTimeline.shouldPlay(voiceOverRunning: UIAccessibility.isVoiceOverRunning, arguments: ProcessInfo.processInfo.arguments, alreadyShown: shown)
        shown = true
        return play
    }
}

/// Överlägget direkt efter startskärmen. Första bilden är exakt startskärmen: samma bakgrundsfärg och samma logotyp i
/// samma storlek, mitt på skärmen. Hemskärmen ligger klar under och hämtar sina data som vanligt. Ett tryck tar bort överlägget direkt.
struct StartIntroView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Klockan startar när första bilden har ritats, så att den ligger exakt som startskärmen även när appen startar långsamt.
    @State private var start: Date?
    /// Avgörs när vyn först visas. Startade processen i bakgrunden och appen öppnas långt senare visas inget intro, och
    /// överlägget är då helt genomskinligt och tar inga tryck, så hemskärmen aldrig täcks.
    @State private var fresh = StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: Date().timeIntervalSince(StartIntroState.processStart))

    var body: some View {
        if fresh { intro } else { Color.clear.allowsHitTesting(false).accessibilityHidden(true).task { onFinish() } }
    }

    private var intro: some View {
        TimelineView(.animation) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) } ?? 0
            let frame = StartIntroTimeline.frame(at: elapsed, reduceMotion: reduceMotion)
            ZStack {
                Color("LaunchBackground").opacity(frame.backgroundOpacity)
                Image("LaunchLogo")
                    .scaleEffect(frame.scale)
                    .opacity(frame.logoOpacity)
            }
            .ignoresSafeArea()
        }
        .onAppear { start = Date() }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        // Bara dekoration. Hemskärmen under är det som läses.
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(StartIntroTimeline.duration(reduceMotion: reduceMotion)))
            onFinish()
        }
    }
}
