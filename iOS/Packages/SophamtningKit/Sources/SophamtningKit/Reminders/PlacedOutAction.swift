import Foundation

/// Att soporna är utställda, som knappen **Utställt** utför det. Körs utanför appens process.
public enum PlacedOutAction {
    /// Sparar valet och avslutar aktiviteten. Ett skrivfel kastas inte utanför: aktiviteten avslutas ändå, och nästa planering
    /// hanterar det. Svarar med om valet sparades.
    @discardableResult
    public static func perform(store: LocalStore, entry: PlacedOut, today: DayDate, end: @Sendable () async -> Void) async -> Bool {
        let saved = (try? store.markPlacedOut(entry, today: today)) != nil
        await end()
        return saved
    }
}
