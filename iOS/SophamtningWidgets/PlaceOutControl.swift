import AppIntents
import SophamtningKit
import SwiftUI
import WidgetKit

/// Kontrollen Ställ ut kärlen, i Kontrollcenter, på låsskärmen och på Action-knappen. Ett tryck gör samma sak som Siris
/// Ställ ut kärlen för huvudadressen. Värdet visar läget: "I morgon", "Utställt" eller nästa datum.
struct PlaceOutControl: ControlWidget {
    static let kind = "se.hardyson.sophamtning.placeout"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: StatusProvider()) { status in
            ControlWidgetButton(action: PlaceOutIntent()) {
                Label {
                    Text("Ställ ut kärlen")
                    Text(status)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }
        .displayName("Ställ ut kärlen")
        .description("Markerar att kärlen är utställda för nästa tömning.")
    }

    /// Läser bara från lagringen, som widgetarna.
    struct StatusProvider: ControlValueProvider {
        var previewValue: String { "I morgon" }

        func currentValue() async throws -> String {
            let data = WidgetData.read(from: LocalStore.shared())
            let now = Date()
            return LockScreenContent.make(content: data.content(at: now), info: data.fractionInfo, placedOut: data.placedOut(at: now)).controlValue
        }
    }
}
