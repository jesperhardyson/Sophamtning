import SophamtningDesign
import SwiftUI
import UIKit

/// Om introt redan har visats i den här processen. Det visas aldrig när appen kommer tillbaka från bakgrunden.
@MainActor
enum StartIntroState {
    private static var shown = false

    /// Svarar sant första gången och därefter aldrig, och bara om introt ska visas alls.
    static func claim() -> Bool {
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

    var body: some View {
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
