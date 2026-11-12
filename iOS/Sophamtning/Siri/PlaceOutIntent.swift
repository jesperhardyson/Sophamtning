import AppIntents
import SophamtningKit

/// "Ställ ut kärlen": samma sak som Klart i Live Activityn och Utställt i notisen, för nästa tömning i dag eller i morgon.
struct PlaceOutIntent: AppIntent {
    static let title: LocalizedStringResource = "Ställ ut kärlen"
    static let description = IntentDescription("Markerar att kärlen är utställda för nästa tömning, i dag eller i morgon.")

    @Parameter(title: "Adress", description: "Utan adress gäller huvudadressen.")
    var address: AddressEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Ställ ut kärlen vid \(\.$address)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let data = SiriData.read(from: LocalStore.shared(), addressId: address?.id) else {
            return .result(dialog: IntentDialog(stringLiteral: SiriAnswers.unreadable))
        }
        switch data.placeOut(at: Date()) {
        case .answer(let text):
            return .result(dialog: IntentDialog(stringLiteral: text))
        case .placeOut(let entry, let name):
            let saved = await MarkPlacedOutIntent.markPlacedOut(entry)
            return .result(dialog: IntentDialog(stringLiteral: saved ? SiriAnswers.placedOutDone(name: name) : SiriAnswers.saveFailed))
        }
    }
}
