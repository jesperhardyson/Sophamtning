import SwiftUI

/// Gemensamma rörelser. Med Reducera rörelse blir alla en enkel, kort toning.
public enum Motion {
    /// Övergången mellan laddning, schema, inga hämtningar och fel.
    public static func transition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3)
    }

    /// Något som fälls ut eller ihop, som kalendern i Hitta område och alla platser i bekräftelsen. Med Reducera rörelse
    /// ingen animation, så att innehållet under inte glider.
    public static func expand(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy
    }

    /// Siffror som rullar, till exempel dagar kvar.
    public static func number(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.4)
    }

    /// Rullande siffror, eller en toning med Reducera rörelse.
    public static func numberTransition(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .opacity : .numericText()
    }

    /// Kort på hemskärmen som kommer in. Utan snabb start, eftersom början annars sker bakom bakgrunden som tonas bort.
    static func card(delay: TimeInterval, reduceMotion: Bool) -> Animation {
        let base: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.3, 0.45, 0.15, 1, duration: EntranceTimeline.cardDuration)
        return base.delay(delay)
    }

    /// Rader i en lista som kommer in.
    static func row(delay: TimeInterval, reduceMotion: Bool) -> Animation {
        let base: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: EntranceTimeline.rowDuration)
        return base.delay(delay)
    }

    /// Nedtryck: direkt respons, och fjädring tillbaka.
    static func press(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.1) : .spring(duration: 0.22, bounce: 0.45)
    }
}

/// Hur knappar och rader fjädrar när de trycks ned. Med Reducera rörelse tonas de lite i stället.
public enum PressMotion {
    public static func scale(pressed: Bool, reduceMotion: Bool) -> Double {
        pressed && !reduceMotion ? 0.96 : 1
    }

    public static func opacity(pressed: Bool, reduceMotion: Bool) -> Double {
        pressed && reduceMotion ? 0.7 : 1
    }
}

/// Knappar, kort och rader som går att trycka på. Rörelsen sker bara i ritningen, så den fördröjer aldrig trycket.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label.pressEffect(pressed: configuration.isPressed)
    }
}

/// En knapp som bara är en del av ett kort. Den ritar inget eget nedtryck utan berättar om det, så att hela kortet kan
/// fjädra med `pressEffect`, också delar som inte hör till knappen.
public struct PressReportingButtonStyle: ButtonStyle {
    @Binding var pressed: Bool

    public init(pressed: Binding<Bool>) {
        _pressed = pressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in pressed = isPressed }
    }
}

private struct PressEffect: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(PressMotion.scale(pressed: pressed, reduceMotion: reduceMotion))
            .opacity(PressMotion.opacity(pressed: pressed, reduceMotion: reduceMotion))
            .animation(Motion.press(reduceMotion: reduceMotion), value: pressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    public static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension View {
    /// Samma fjädring som `.pressable`, när `pressed` är sant.
    public func pressEffect(pressed: Bool) -> some View {
        modifier(PressEffect(pressed: pressed))
    }

    /// Ett kort på hemskärmen: glider upp och tonas in när `shown` blir sant, efter sin plats i ordningen.
    /// Bara ritningen animeras. Knappen är på sin slutliga plats och går att trycka på under tiden.
    public func cardEntrance(shown: Bool, index: Int) -> some View {
        modifier(CardEntranceModifier(shown: shown, index: index))
    }

    /// En rad i en lista: tonar och glider in när `shown` blir sant, efter sin plats i listan.
    public func rowEntrance(shown: Bool, index: Int) -> some View {
        modifier(RowEntranceModifier(shown: shown, index: index))
    }

    /// En rad som kommer in första gången den visas. Tillståndet ligger i raden, så vid retur till listan händer inget.
    /// Rader efter de första står stilla och får inget tillstånd, så att långa listor inte kostar mer än korta.
    @ViewBuilder
    public func rowEntranceOnAppear(index: Int) -> some View {
        if EntranceTimeline.animatesRow(index: index) {
            modifier(RowAppearModifier(index: index))
        } else {
            self
        }
    }

    /// Dagar kvar och liknande: siffrorna rullar när texten ändras, men inte när den visas första gången.
    public func rollingNumbers<Value: Equatable>(value: Value, reduceMotion: Bool) -> some View {
        contentTransition(Motion.numberTransition(reduceMotion: reduceMotion))
            .animation(Motion.number(reduceMotion: reduceMotion), value: value)
    }
}

private struct CardEntranceModifier: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let delay = EntranceTimeline.cardDelay(index: index, reduceMotion: reduceMotion)
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : EntranceTimeline.offset(EntranceTimeline.cardDistance, reduceMotion: reduceMotion))
            .animation(Motion.card(delay: delay, reduceMotion: reduceMotion), value: shown)
    }
}

private struct RowEntranceModifier: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Raderna efter de första står stilla från början.
        let visible = shown || !EntranceTimeline.animatesRow(index: index)
        let delay = EntranceTimeline.rowDelay(index: index, reduceMotion: reduceMotion)
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : EntranceTimeline.offset(EntranceTimeline.rowDistance, reduceMotion: reduceMotion))
            .animation(Motion.row(delay: delay, reduceMotion: reduceMotion), value: visible)
    }
}

private struct RowAppearModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.entranceEnabled) private var entranceEnabled
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .rowEntrance(shown: appeared || voiceOver || !entranceEnabled, index: index)
            .onAppear { appeared = true }
    }
}
