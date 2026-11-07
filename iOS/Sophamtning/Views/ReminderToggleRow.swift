import SophamtningDesign
import SophamtningKit
import SwiftUI

/// En rad med reglage för en påminnelse. Ikonen studsar och telefonen ger en lätt vibration när `pulse` ökar, vilket
/// föräldern gör först när påminnelsen faktiskt har slagits på. Med Reducera rörelse pulserar ikonen i stället för att studsa.
struct ReminderToggleRow: View {
    let title: String
    let text: String
    let symbol: String
    let pulse: Int
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            AdaptiveStack(spacing: 12, verticalSpacing: 8, alignment: .top) {
                ReminderSymbol(symbol: symbol, pulse: pulse, color: Color.Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.ui(20, weight: .heavy, relativeTo: .headline))
                        .foregroundStyle(Color.Theme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    Text(text)
                        .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.Theme.text2)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color.Theme.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sensoryFeedback(.impact(weight: .light), trigger: pulse)
    }
}

/// Ikonen för en påminnelse. Den studsar när `pulse` ökar, och pulserar i stället med Reducera rörelse.
struct ReminderSymbol: View {
    let symbol: String
    let pulse: Int
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let image = Image(systemName: symbol)
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
        if reduceMotion {
            image.symbolEffect(.pulse, options: .nonRepeating, value: pulse)
        } else {
            image.symbolEffect(.bounce, options: .nonRepeating, value: pulse)
        }
    }
}

/// Reglaget för Live Activity, gemensamt för inställningarna och adressvyn. Effekten kommer när valet är på och iOS tillåter
/// Live Activities, alltså aldrig när systemet nekar eller när valet stängs av.
struct LiveActivityToggleRow: View {
    let model: AppModel
    let text: String

    @State private var pulse = 0

    private var isActive: Bool { model.settings.liveActivityOn && model.liveActivitiesEnabled }

    var body: some View {
        ReminderToggleRow(
            title: "Live Activity",
            text: text,
            symbol: "iphone.radiowaves.left.and.right",
            pulse: pulse,
            isOn: Binding(
                get: { model.settings.liveActivityOn },
                set: { model.clearStorageError(); model.setLiveActivity($0) }
            )
        )
        .onChange(of: isActive) { _, active in
            if active { pulse += 1 }
        }
    }
}
