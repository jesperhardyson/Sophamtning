import SwiftUI

/// Gemensamma rörelser. Med Reducera rörelse blir alla en enkel, kort toning.
public enum Motion {
    /// Övergången mellan laddning, schema, inga hämtningar och fel.
    public static func transition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3)
    }

    /// Siffror som rullar, till exempel dagar kvar.
    public static func number(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.4)
    }

    /// Rullande siffror, eller en toning med Reducera rörelse.
    public static func numberTransition(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .opacity : .numericText()
    }
}

extension View {
    /// Dagar kvar och liknande: siffrorna rullar när texten ändras, men inte när den visas första gången.
    public func rollingNumbers<Value: Equatable>(value: Value, reduceMotion: Bool) -> some View {
        contentTransition(Motion.numberTransition(reduceMotion: reduceMotion))
            .animation(Motion.number(reduceMotion: reduceMotion), value: value)
    }
}
