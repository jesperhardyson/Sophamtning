import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

extension AppModel {
    /// Reglaget för notis på huvudkortet och i adressvyn. Frågan om tillstånd ställs av modellen, bara när valet slås på.
    /// `onTurnedOn` körs bara när notiserna faktiskt slogs på, aldrig när iOS nekar eller valet stängs av, så att ikonen
    /// studsar och telefonen vibrerar först då.
    func toggleNotifications(_ on: Bool, for key: AddressKey, onTurnedOn: @escaping @MainActor () -> Void) {
        clearStorageError()
        Task {
            let result = await setNotifications(on, for: key)
            if on, result == .granted { onTurnedOn() }
        }
    }
}

/// Texterna när iOS har nekat notiser, samma i adressvyn, hushållsarket och snabbmenyn.
enum NotificationTexts {
    static let deniedTitle = "Notiser är avstängda"
    static let deniedMessage = "Du har stängt av notiser för Sophämtning i iOS."
}

/// Öppnar appens notisinställningar i iOS, där användaren kan slå på notiser igen.
@MainActor
func openNotificationSettings() {
    guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
    Task { await UIApplication.shared.open(url) }
}

/// En rad med reglage för en påminnelse. Ikonen studsar och telefonen ger en lätt vibration när `pulse` ökar, vilket
/// föräldern gör först när påminnelsen faktiskt har slagits på. Med Reducera rörelse pulserar ikonen i stället för att studsa.
struct ReminderToggleRow: View {
    let title: String
    let text: String
    let symbol: String
    let pulse: Int
    @Binding var isOn: Bool
    /// En knapp under reglaget som visar mer om valet, en mening per rad. Utanför reglaget, så att VoiceOver läser den
    /// som en egen knapp.
    var details: (title: String, lines: [String])? = nil

    @State var showsDetails = false
    @Environment(\.dynamicTypeSize) var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toggle
            if let details {
                Button { showsDetails = true } label: {
                    Label(details.title, systemImage: "info.circle")
                        .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                        .foregroundStyle(Color.Theme.primary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsDetails) {
                    // En popover som får sin höjd från texten. Med de största textstorlekarna ryms den inte, och då blir
                    // den ett ark som går att scrolla.
                    if typeSize.isAccessibilitySize {
                        ScrollView { detailLines(details.lines).padding(20) }
                            .presentationDetents([.medium, .large])
                    } else {
                        detailLines(details.lines)
                            .padding(20)
                            .frame(width: 300, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sensoryFeedback(.impact(weight: .light), trigger: pulse)
    }

    private func detailLines(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.ui(16, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var toggle: some View {
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
            ),
            details: (title: "Mer om Live Activity", lines: AddressDetail.liveActivityDetails())
        )
        .onChange(of: isActive) { _, active in
            if active { pulse += 1 }
        }
    }
}
