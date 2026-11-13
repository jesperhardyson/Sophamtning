import AppIntents
import SophamtningDesign
import SophamtningKit
import SwiftUI

/// "När töms soporna": svarar från det sparade schemat, utan nätanrop och utan att öppna appen.
struct NextPickupIntent: AppIntent {
    static let title: LocalizedStringResource = "När töms soporna"
    static let description = IntentDescription("Säger när soporna töms nästa gång och vilka kärl som töms.")

    @Parameter(title: "Adress", description: "Utan adress gäller huvudadressen.")
    var address: AddressEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("När töms soporna vid \(\.$address)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let data = SiriData.read(from: LocalStore.shared(), addressId: address?.id) else {
            return .result(dialog: IntentDialog(stringLiteral: SiriAnswers.unreadable), view: SiriCardView(card: nil))
        }
        let answer = data.nextPickup(at: Date())
        return .result(dialog: IntentDialog(stringLiteral: answer.text), view: SiriCardView(card: answer.card))
    }
}

/// Fraserna, som fungerar direkt efter installationen och syns i Genvägar och Spotlight.
struct SophamtningShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPickupIntent(),
            phrases: [
                "När töms soporna i \(.applicationName)",
                "När töms kärlen i \(.applicationName)",
                "Nästa tömning i \(.applicationName)",
                "När töms soporna vid \(\.$address) i \(.applicationName)",
            ],
            shortTitle: "När töms soporna",
            systemImageName: "trash"
        )
        AppShortcut(
            intent: PlaceOutIntent(),
            phrases: [
                "Ställ ut kärlen i \(.applicationName)",
                "Jag har ställt ut kärlen i \(.applicationName)",
                "Ställ ut kärlen vid \(\.$address) i \(.applicationName)",
            ],
            shortTitle: "Ställ ut kärlen",
            systemImageName: "checkmark.circle"
        )
    }
}

/// Kortet under Siris svar: kalenderbladet, dagar kvar och kärlen den dagen. Utan kort visas ingenting.
struct SiriCardView: View {
    let card: SiriCard?

    var body: some View {
        if let card {
            HStack(alignment: .center, spacing: 16) {
                CalendarTile(date: card.date)
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.title)
                        .font(.brand(22, relativeTo: .title2))
                        .foregroundStyle(Color.Theme.text)
                    ForEach(card.fractions, id: \.self) { id in
                        FractionChip(id: id, info: ScheduleLogic.displayInfo(for: id, in: card.info))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}
