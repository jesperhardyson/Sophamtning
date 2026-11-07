import Foundation

/// Att soporna är utställda, som knappen **Utställt** utför det. Körs utanför appens process.
public enum PlacedOutAction {
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
