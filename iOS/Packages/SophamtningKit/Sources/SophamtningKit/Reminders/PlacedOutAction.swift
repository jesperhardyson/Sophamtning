import Foundation

/// Att soporna är utställda, som knappen **Utställt** utför det. Körs utan att appen öppnas.
public enum PlacedOutAction {
    /// Hur länge bocken visas innan aktiviteten försvinner.
    public static let checkmarkSeconds: TimeInterval = 3

    /// I appens process: skickar en sparad bock till hushållet direkt. Sätts en gång när appen startar, innan någon knapp
    /// kan tryckas, och är `nil` i widgetmålet.
    nonisolated(unsafe) public static var sendToHousehold: (@Sendable () async -> Void)?

    /// Sparar valet, avslutar aktiviteten och tar sedan bort tömningens väntande notis (reserven), via `cancelReminder` med notisens
    /// identifierare. Inget fel kastas utanför: ett skrivfel hindrar varken avslutningen eller borttagningen, och ett fel vid
    /// borttagningen ger i värsta fall en extra påminnelse, eftersom nästa planering rättar det. Svarar med om valet sparades.
    @discardableResult
    public static func perform(
        store: LocalStore,
        entry: PlacedOut,
        today: DayDate,
        end: @Sendable () async -> Void,
        cancelReminder: @Sendable (String) async throws -> Void
    ) async -> Bool {
        let saved = (try? store.markPlacedOut(entry, today: today)) != nil
        await end()
        try? await cancelReminder(PlannedNotification.identifier(key: entry.key, date: entry.date))
        return saved
    }
}
