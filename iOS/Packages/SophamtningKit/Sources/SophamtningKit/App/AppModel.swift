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
    @ObservationIgnored public let api: any SoporAPI
    /// När källistan senast försökte hämtas utan att lyckas, så att inte varje tangenttryck hämtar på nytt.
    @ObservationIgnored private var failedSourcesAt: Date?
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Den senaste köade uppdateringen. Nästa väntar på den, så att två anrop aldrig hämtar samtidigt.
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// Systemets tillstånd för notiser, senast läst. Läses om av `applyReminders()`.
    public private(set) var notificationAuthorization: NotificationAuthorization = .notDetermined
    @ObservationIgnored private let scheduler: any NotificationScheduling
    /// Den senaste köade påminnelseuppdateringen, så att två aldrig körs samtidigt.
    @ObservationIgnored private var reminderQueue: Task<Void, Never>?
    /// Räknar om vyn när ett schema ändrats. `schedules` är ignorerat, och den här räknaren ersätter det.
    private var scheduleRevision = 0

    public init(api: any SoporAPI, store: LocalStore, now: @escaping @Sendable () -> Date = { Date() }, scheduler: any NotificationScheduling = DisabledNotifications()) {
        self.scheduler = scheduler
        self.store = store
        self.now = now
        self.api = api
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

    // MARK: Källor

    static let sourcesMaxAge: TimeInterval = 24 * 3600
    static let sourcesRetryAfter: TimeInterval = 3600

    /// Källistan för kommunfrågan: den sparade om den är högst ett dygn gammal, annars hämtas en ny.
    /// Misslyckas hämtningen används den sparade listan, även om den är äldre. `nil` när inget är sparat och
    /// hämtningen misslyckas, och det betyder "okänt", aldrig "inga källor".
    public func sourceList() async -> [Source]? {
        let saved = store.sources()
        let current = now()
        if let saved, current.timeIntervalSince(saved.fetchedAt) < Self.sourcesMaxAge {
            return saved.response.sources
        }
        // Finns en gammal lista väntar vi med nästa försök. Utan lista försöker vi varje gång, för Försök igen.
        if let saved, let failedSourcesAt, current.timeIntervalSince(failedSourcesAt) < Self.sourcesRetryAfter {
            return saved.response.sources
        }
        do {
            let fresh = try await api.sources()
            failedSourcesAt = nil
            // Listan är bara en cache. Går den inte att spara hämtas den på nytt nästa gång.
            try? store.setSources(CachedSources(response: fresh, fetchedAt: current))
            return fresh.sources
        } catch {
            // Ett avbrott (texten ändrades, skärmen stängdes) är inget misslyckande och skjuter inte upp nästa hämtning.
            if !(error is CancellationError) { failedSourcesAt = current }
            return saved?.response.sources
        }
    }

    // MARK: Adresser

    /// Sparar adressen. En adress som redan finns läggs inte till igen men räknas som sparad. Går sparandet
    /// fel är det tidigare läget kvar, `lastStorageError` är satt och svaret är `false`.
    @discardableResult
    public func add(_ hit: SearchHit) -> Bool {
        let key = AddressKey(source: hit.source, id: hit.id)
        guard !addresses.contains(where: { $0.key == key }) else { return true }
        // Den första adressen heter "Hemma", ett område får områdets namn och övriga gatan.
        let name = addresses.isEmpty ? "Hemma" : hit.street
        let address = SavedAddress(
            key: key,
            url: hit.url,
            street: hit.street,
            locality: hit.locality,
            kommun: hit.kommun,
            detail: hit.detail,
            selection: hit.selection,
            displayName: name,
            isPrimary: false,
            addedAt: now()
        )
        return saveAddresses(AddressList.add(address, to: addresses))
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

    /// Byter namn. Ogiltigt namn (tomt eller över 60 tecken) eller lagringsfel ger `false` och ändrar ingenting.
    @discardableResult
    public func rename(_ key: AddressKey, to name: String) -> Bool {
        guard AddressList.validName(name) != nil else { return false }
        // Notisernas text innehåller namnet.
        defer { applyReminders() }
        return saveAddresses(AddressList.rename(key, to: name, in: addresses))
    }

    public func setPrimary(_ key: AddressKey) {
        guard saveAddresses(AddressList.setPrimary(key, in: addresses)) else { return }
        applyReminders()
    }

    // MARK: Inställningar

    /// Valet sparas men planerar inget än, eftersom Live Activity kopplas i uppgift 14.
    public func setLiveActivity(_ on: Bool) {
        var updated = settings
        updated.liveActivityOn = on
        guard saveSettings(updated) else { return }
        applyReminders()
    }

    /// Giltig tid är 15:00 till 23:00 i steg om 15 minuter. Annars, eller vid lagringsfel, är allt kvar som förut.
    @discardableResult
    public func setReminderMinutes(_ minutes: Int) -> Bool {
        guard ReminderSettings.isValid(minutes: minutes) else { return false }
        var updated = settings
        updated.reminderMinutes = minutes
        guard saveSettings(updated) else { return false }
        applyReminders()
        return true
    }

    @discardableResult
    private func saveSettings(_ updated: ReminderSettings) -> Bool {
        do {
            try store.setSettings(updated)
        } catch {
            lastStorageError = "Kunde inte spara inställningen. Inget har ändrats."
            return false
        }
        settings = updated
        return true
    }

    // MARK: Påminnelser

    /// Slår notiser för en adress på eller av. Frågan om tillstånd ställs först när de slås på och tillståndet
    /// inte är avgjort. `denied` betyder att tillstånd saknas, och då är notiserna av. Att stänga av ger alltid `granted`.
    /// Går sparandet fel är `notificationsOn` oförändrad och `lastStorageError` satt.
    public func setNotifications(_ on: Bool, for key: AddressKey) async -> PermissionResult {
        guard on else {
            setNotificationsOn(false, for: key)
            return .granted
        }
        var status = await scheduler.authorization()
        if status == .notDetermined {
            status = await scheduler.requestAuthorization() ? .authorized : .denied
        }
        notificationAuthorization = status
        guard status == .authorized else {
            setNotificationsOn(false, for: key)
            return .denied
        }
        setNotificationsOn(true, for: key)
        return .granted
    }

    private func setNotificationsOn(_ on: Bool, for key: AddressKey) {
        guard addresses.contains(where: { $0.key == key }) else { return }
        let updated = addresses.map { address in
            var copy = address
            if address.key == key { copy.notificationsOn = on }
            return copy
        }
        guard updated == addresses || saveAddresses(updated) else { return }
        applyReminders()
    }

    /// Läser tillståndet, kör planeraren och ändrar bara skillnaden mot det som redan är schemalagt.
    /// Körs vid lyckad hämtning, när appen öppnas och när ett påminnelseval ändras. Uppdateringarna köas.
    public func applyReminders() {
        let previous = reminderQueue
        reminderQueue = Task { @MainActor in
            await previous?.value
            await self.performApplyReminders()
        }
    }

    /// Väntar tills köade påminnelseuppdateringar är klara.
    public func settleReminders() async {
        await reminderQueue?.value
    }

    private func performApplyReminders() async {
        let status = await scheduler.authorization()
        notificationAuthorization = status
        // Har användaren stängt av notiser i iOS Inställningar går reglagen tillbaka till av.
        if status == .denied, addresses.contains(where: \.notificationsOn) {
            let updated = addresses.map { address in
                var copy = address
                copy.notificationsOn = false
                return copy
            }
            saveAddresses(updated)
        }
        let pending = await scheduler.pending()
        var desired: [PlannedNotification] = []
        if status == .authorized {
            let input = PlannerInput(
                addresses: addresses.map { PlannerAddress(address: $0, schedule: schedules[$0.key]) },
                settings: settings,
                placedOut: Set(store.placedOut()),
                now: now(),
                // Live Activity kopplas i uppgift 14. Tills dess är de avstängda i planeringen och inga aktiviteter
                // finns, så att den vanliga notisen alltid skickas och ingen tömning blir utan påminnelse.
                liveActivitiesAllowed: false,
                existingActivities: []
            )
            desired = ReminderPlanner.plan(input).notifications
        }
        let changes = NotificationDiff.diff(
            desired: desired,
            pendingIds: Set(pending.map(\.identifier)),
            pendingFireDates: Dictionary(pending.compactMap { p in p.fireDate.map { (p.identifier, $0) } }, uniquingKeysWith: { first, _ in first }),
            pendingBodies: Dictionary(pending.map { ($0.identifier, $0.body) }, uniquingKeysWith: { first, _ in first })
        )
        if !changes.removeIds.isEmpty { await scheduler.cancel(identifiers: changes.removeIds) }
        if !changes.add.isEmpty { await scheduler.schedule(changes.add) }
    }
}
