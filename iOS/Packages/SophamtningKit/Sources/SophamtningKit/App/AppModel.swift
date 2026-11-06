import Foundation
import Observation

/// Appens tillstånd: sparade adresser, inställningar och hämtade scheman.
///
/// Ligger i paketet och inte i appmålet, så att uppdateringen och lagringsfelen går att testa med `swift test`.
@MainActor
@Observable
public final class AppModel {
    public private(set) var addresses: [SavedAddress]
    public private(set) var settings: ReminderSettings
    /// Det senaste lagringsfelet, tills det rensas med `clearStorageError()`. Då är det tidigare läget kvar.
    public private(set) var lastStorageError: String?

    @ObservationIgnored private var schedules: [AddressKey: CachedSchedule]
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let refresher: ScheduleRefresher
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Den senaste köade uppdateringen. Nästa väntar på den, så att två anrop aldrig hämtar samtidigt.
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// Räknar om vyn när ett schema ändrats. `schedules` är ignorerat, och den här räknaren ersätter det.
    private var scheduleRevision = 0

    public init(api: any SoporAPI, store: LocalStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
        refresher = ScheduleRefresher(api: api, store: store)
        let addresses = store.addresses()
        self.addresses = addresses
        settings = store.settings()
        schedules = Dictionary(addresses.compactMap { address in
            store.schedule(for: address.key).map { (address.key, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Alla sparade scheman, för `HomeContent`. Läser `scheduleRevision`, så att vyer följer ändringar.
    public var cachedSchedules: [AddressKey: CachedSchedule] {
        _ = scheduleRevision
        return schedules
    }

    public func schedule(for key: AddressKey) -> CachedSchedule? {
        _ = scheduleRevision
        return schedules[key]
    }

    public var currentDate: Date { now() }

    public func clearStorageError() {
        lastStorageError = nil
    }

    // MARK: Uppdatering

    /// Uppdaterar alla adresser, en i taget. Anrop köas efter varandra: ett anrop som kommer medan
    /// ett annat pågår väntar, och adresser som då är nyss hämtade hoppas över av `RefreshPolicy`.
    public func refreshAll(manual: Bool) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await self.performRefresh(manual: manual)
        }
        queue = task
        // Avbryts anroparen (dra för att uppdatera lämnar skärmen) fortsätter köplatsen ändå.
        await task.value
    }

    private func performRefresh(manual: Bool) async {
        var fetchedAny = false
        for address in addresses {
            // En adress som tagits bort under tiden hämtas inte.
            guard addresses.contains(where: { $0.key == address.key }) else { continue }
            let outcome = await refresher.refresh(address, now: now(), manual: manual)
            if outcome == .fetched { fetchedAny = true }
            if addresses.contains(where: { $0.key == address.key }) {
                var current = store.schedule(for: address.key)
                if outcome == .storageFailed {
                    lastStorageError = "Kunde inte spara schemat."
                    // Försöket gick inte att spara. Utan en markering i minnet skulle en ny adress stå kvar som "hämtar".
                    var attempted = current ?? CachedSchedule()
                    attempted.lastAttemptAt = now()
                    attempted.lastError = .unexpected(0)
                    current = attempted
                }
                schedules[address.key] = current
            } else {
                // Adressen togs bort medan hämtningen pågick, så schemat ska inte bli kvar.
                removeStoredSchedule(for: address.key)
            }
            scheduleRevision += 1
        }
        if fetchedAny { applyReminders() }
    }

    // MARK: Adresser

    /// Sparar adressen. En adress som redan finns läggs inte till igen. Går sparandet fel är
    /// det tidigare läget kvar och `lastStorageError` är satt.
    public func add(_ hit: SearchHit) {
        let key = AddressKey(source: hit.source, id: hit.id)
        guard !addresses.contains(where: { $0.key == key }) else { return }
        // Tillfälligt namn tills uppgift 11 låter användaren välja: "Hemma" för den första, annars gatan.
        let address = SavedAddress(
            key: key,
            url: hit.url,
            street: hit.street,
            locality: hit.locality,
            kommun: hit.kommun,
            detail: hit.detail,
            selection: hit.selection,
            displayName: addresses.isEmpty ? "Hemma" : hit.street,
            isPrimary: false,
            addedAt: now()
        )
        saveAddresses(AddressList.add(address, to: addresses))
    }

    /// Tar bort adressen och dess sparade schema. Går sparandet av listan fel är allt kvar.
    public func remove(_ key: AddressKey) {
        guard saveAddresses(AddressList.remove(key, from: addresses)) else { return }
        schedules[key] = nil
        scheduleRevision += 1
        removeStoredSchedule(for: key)
        applyReminders()
    }

    private func removeStoredSchedule(for key: AddressKey) {
        do {
            try store.removeSchedule(for: key)
        } catch {
            lastStorageError = "Kunde inte ta bort det sparade schemat."
        }
    }

    @discardableResult
    private func saveAddresses(_ updated: [SavedAddress]) -> Bool {
        do {
            try store.setAddresses(updated)
        } catch {
            lastStorageError = "Kunde inte spara adressen. Inget har ändrats."
            return false
        }
        addresses = updated
        return true
    }

    // MARK: Påminnelser

    /// Tom tills uppgift 12 kopplar påminnelserna.
    public func applyReminders() {}
}
