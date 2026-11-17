import Foundation

/// Var `refreshAll` körs. Avgör om ett nytt meddelande från källan ger en notis.
public enum RefreshContext: Sendable {
    /// Appen är öppen. Ett nytt meddelande visas som kort och räknas som sett utan notis.
    case foreground
    /// Bakgrundsuppdateringen. Ett nytt meddelande ger en notis, om valet är på och iOS tillåter notiser.
    case background
}

extension AppModel {
    /// Rubriken på notisen när källans namn inte är känt.
    static let sourceMessageFallbackTitle = "Sophämtning"

    /// Meddelandena som gäller i dag för någon sparad adress och inte är stängda, för startsidan.
    public var visibleSourceMessages: [ActiveSourceMessage] {
        // Schemana är inte observerade, men räknaren är det.
        _ = scheduleRevision
        return activeSourceMessages().filter { !sourceMessageMemory.isDismissed($0.key) }
    }

    /// Källans namn från den sparade källistan, eller `nil` när listan inte har hämtats.
    public func sourceName(for source: String) -> String? {
        store.sources()?.response.sources.first { $0.id == source }?.name
    }

    /// Stänger kortet. Går minnet inte att läsa stängs det bara tills appen startas om, och filen skrivs inte över.
    public func dismissSourceMessage(_ item: ActiveSourceMessage) {
        sourceMessageMemory.dismiss(item.key)
        saveSourceMessageMemory()
    }

    /// Valet Meddelanden från källan. Frågar aldrig om tillstånd för notiser.
    @discardableResult
    public func setSourceMessages(_ on: Bool) -> Bool {
        var updated = settings
        updated.sourceMessagesOn = on
        return saveSettings(updated)
    }

    func loadSourceMessageMemory() {
        switch store.sourceMessageMemoryState() {
        case .value(let memory):
            sourceMessageMemory = memory
            sourceMessageMemoryKnown = true
        case .missing:
            sourceMessageMemory = SourceMessageMemory()
            sourceMessageMemoryKnown = true
        case .unreadable, .unavailable:
            sourceMessageMemoryKnown = false
        }
    }

    /// Körs efter varje uppdatering. Meddelanden som inte är sedda räknas som sedda, och i bakgrunden ges först en notis
    /// per meddelande. Går minnet inte att läsa händer ingenting, så att ingen får samma notis två gånger.
    func noteSourceMessages(context: RefreshContext) async {
        if !sourceMessageMemoryKnown { loadSourceMessageMemory() }
        guard sourceMessageMemoryKnown else { return }
        let fresh = SourceMessages.unseen(activeSourceMessages(), memory: sourceMessageMemory)
        guard !fresh.isEmpty else { return }
        // Sett först, så att en notis aldrig skickas för ett meddelande som inte gick att spara som sett.
        var updated = sourceMessageMemory
        updated.markSeen(fresh.map(\.key))
        do {
            try store.setSourceMessageMemory(updated)
        } catch {
            return
        }
        sourceMessageMemory = updated
        guard context == .background, settings.sourceMessagesOn, await scheduler.authorization() == .authorized else { return }
        for item in fresh {
            await scheduler.deliverNow(
                identifier: SourceMessages.notificationId(item.key),
                title: sourceName(for: item.source) ?? Self.sourceMessageFallbackTitle,
                body: item.message.title
            )
        }
    }

    private func activeSourceMessages() -> [ActiveSourceMessage] {
        let input = addresses.compactMap { address -> (source: String, messages: [SourceMessage])? in
            guard let response = schedules[address.key]?.response else { return nil }
            return (address.key.source, response.messages)
        }
        return SourceMessages.active(in: input, today: StockholmClock.today(now: now()))
    }

    private func saveSourceMessageMemory() {
        guard sourceMessageMemoryKnown else { return }
        try? store.setSourceMessageMemory(sourceMessageMemory)
    }
}
