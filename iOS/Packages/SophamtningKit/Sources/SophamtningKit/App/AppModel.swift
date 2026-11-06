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
    /// Om några väntande notiser inte gick att lägga in, annars `nil`. Försöket upprepas vid nästa körning.
    public private(set) var reminderError: String?
    @ObservationIgnored private let scheduler: any NotificationScheduling
    /// Ett tunt anrop som laddar om widgeten, till exempel `WidgetCenter.shared.reloadAllTimelines()` i appen.
    /// Paketet känner inte till WidgetKit. Widgeten läser bara från lagringen, så den laddas om när lagringen ändrats.
    @ObservationIgnored private let widgetReloader: @MainActor () -> Void
    /// Varför `addresses.json` eller `settings.json` inte går att läsa, annars `nil`. Då skrivs filen aldrig över och inga
    /// notiser tas bort. `corrupt`: innehållet går inte att tolka. `unavailable`: läsningen misslyckades, till exempel skyddad data.
    private enum StoreIssue { case corrupt, unavailable }
    private var addressesIssue: StoreIssue?
    private var settingsIssue: StoreIssue?
    private var addressesReadable: Bool { addressesIssue == nil }
    private var settingsReadable: Bool { settingsIssue == nil }
    /// Den senaste köade påminnelseuppdateringen, så att två aldrig körs samtidigt.
    @ObservationIgnored private var reminderQueue: Task<Void, Never>?
    /// Räknar om vyn när ett schema ändrats. `schedules` är ignorerat, och den här räknaren ersätter det.
    private var scheduleRevision = 0

    public init(api: any SoporAPI, store: LocalStore, now: @escaping @Sendable () -> Date = { Date() }, scheduler: any NotificationScheduling = DisabledNotifications(), widgetReloader: @escaping @MainActor () -> Void = {}) {
        self.scheduler = scheduler
        self.widgetReloader = widgetReloader
        self.store = store
        self.now = now
        self.api = api
        refresher = ScheduleRefresher(api: api, store: store)
        let addresses: [SavedAddress]
        switch store.addressesState() {
        case .value(let saved): addresses = saved
        case .missing: addresses = []
        case .unreadable:
            addresses = []
            addressesIssue = .corrupt
        case .unavailable:
            addresses = []
            addressesIssue = .unavailable
        }
        self.addresses = addresses
        switch store.settingsState() {
        case .value(let saved): settings = saved
        case .missing: settings = ReminderSettings()
        case .unreadable:
            settings = ReminderSettings()
            settingsIssue = .corrupt
        case .unavailable:
            settings = ReminderSettings()
            settingsIssue = .unavailable
        }
        schedules = Dictionary(addresses.compactMap { address in
            store.schedule(for: address.key).map { (address.key, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Läser om adresser och inställningar som inte gick att läsa vid uppstart, till exempel skyddad data efter omstart.
    /// Först när läsningen lyckats ändras något, och dessförinnan skrivs ingen fil över.
    private func reloadStorageIfNeeded() {
        if !addressesReadable {
            switch store.addressesState() {
            case .value(let saved): adopt(saved)
            case .missing: adopt([])
            case .unreadable: addressesIssue = .corrupt
            case .unavailable: addressesIssue = .unavailable
            }
        }
        if !settingsReadable {
            switch store.settingsState() {
            case .value(let saved):
                settings = saved
                settingsIssue = nil
            case .missing:
                settings = ReminderSettings()
                settingsIssue = nil
            case .unreadable: settingsIssue = .corrupt
            case .unavailable: settingsIssue = .unavailable
            }
        }
    }

    private func adopt(_ saved: [SavedAddress]) {
        addresses = saved
        addressesIssue = nil
        schedules = Dictionary(saved.compactMap { address in
            store.schedule(for: address.key).map { (address.key, $0) }
        }, uniquingKeysWith: { first, _ in first })
        scheduleRevision += 1
        widgetReloader()
    }

    /// Filen som inte går att läsa, om någon. Hemskärmen visar då ett eget läge i stället för det tomma.
    /// `...Unreadable`: innehållet är skadat, och Börja om erbjuds. `...Unavailable`: filen går inte att läsa just nu,
    /// till exempel före upplåsning, och bara Försök igen erbjuds.
    public enum StorageProblem: Equatable, Sendable {
        case addressesUnreadable
        case addressesUnavailable
        case settingsUnreadable
        case settingsUnavailable
    }

    public var storageProblem: StorageProblem? {
        switch addressesIssue {
        case .corrupt: return .addressesUnreadable
        case .unavailable: return .addressesUnavailable
        case nil: break
        }
        switch settingsIssue {
        case .corrupt: return .settingsUnreadable
        case .unavailable: return .settingsUnavailable
        case nil: return nil
        }
    }

    /// "Försök igen": läser om filerna som inte gick att läsa.
    public func retryStorage() {
        reloadStorageIfNeeded()
        scheduleRevision += 1
        applyReminders()
    }

    /// "Börja om", efter bekräftelse, och bara för en fil vars innehåll är skadat. Filerna läses om först, och är de
    /// fungerande eller bara tillfälligt otillgängliga flyttas inget. Den skadade filen flyttas åt sidan och raderas inte.
    /// Är det adresserna börjar appen utan sparade adresser, och appens väntande notiser tas bort. Är det inställningarna
    /// används standardinställningarna. Går det inte att flytta filen ändras inget och `lastStorageError` är satt.
    public func startOver() async {
        reloadStorageIfNeeded()
        let date = now()
        if addressesIssue == .corrupt {
            do {
                try store.moveAsideAddresses(at: date)
            } catch {
                lastStorageError = "Kunde inte flytta den skadade filen. Inget har ändrats."
                return
            }
            addresses = []
            schedules = [:]
            addressesIssue = nil
            scheduleRevision += 1
            widgetReloader()
            let own = await scheduler.pending().map(\.identifier).filter { NotificationDiff.isOwn(identifier: $0) }
            if !own.isEmpty { await scheduler.cancel(identifiers: own) }
        }
        if settingsIssue == .corrupt {
            do {
                try store.moveAsideSettings(at: date)
            } catch {
                lastStorageError = "Kunde inte flytta den skadade filen. Inget har ändrats."
                return
            }
            settings = ReminderSettings()
            settingsIssue = nil
        }
        applyReminders()
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
        reloadStorageIfNeeded()
        var fetchedAny = false
        var savedAny = false
        for address in addresses {
            // En adress som tagits bort under tiden hämtas inte.
            guard addresses.contains(where: { $0.key == address.key }) else { continue }
            let outcome = await refresher.refresh(address, now: now(), manual: manual)
            if outcome == .fetched { fetchedAny = true }
            // Både ett nytt svar och ett noterat misslyckande ändrar det widgeten visar. `skipped` ändrar inget.
            if outcome != .skipped { savedAny = true }
            if addresses.contains(where: { $0.key == address.key }) {
                // En schemafil som inte går att läsa ersätter inte det som redan finns i minnet.
                var current: CachedSchedule?
                switch store.scheduleState(for: address.key) {
                case .value(let saved): current = saved
                case .missing: current = nil
                case .unreadable, .unavailable: current = schedules[address.key]
                }
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
        if savedAny { widgetReloader() }
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
        guard saveAddresses(AddressList.add(address, to: addresses)) else { return false }
        widgetReloader()
        return true
    }

    /// Tar bort adressen och dess sparade schema. Går sparandet av listan fel är allt kvar.
    public func remove(_ key: AddressKey) {
        guard saveAddresses(AddressList.remove(key, from: addresses)) else { return }
        schedules[key] = nil
        scheduleRevision += 1
        removeStoredSchedule(for: key)
        widgetReloader()
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
        guard addressesReadable else {
            lastStorageError = "Adresserna går inte att läsa just nu. Inget har ändrats."
            return false
        }
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
        guard saveAddresses(AddressList.rename(key, to: name, in: addresses)) else { return false }
        // Widgeten visar namnet.
        widgetReloader()
        return true
    }

    public func setPrimary(_ key: AddressKey) {
        guard saveAddresses(AddressList.setPrimary(key, in: addresses)) else { return }
        widgetReloader()
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
        guard settingsReadable else {
            lastStorageError = "Inställningarna går inte att läsa just nu. Inget har ändrats."
            return false
        }
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

    /// Notiser är på för adressen och iOS tillåter dem. `notificationsOn` är användarens val och ändras aldrig av systemets
    /// tillstånd, så den här är det visade läget.
    public func remindersOn(for address: SavedAddress) -> Bool {
        address.notificationsOn && notificationAuthorization == .authorized
    }

    /// "Tömning i morgon. Påminnelsen för i kväll har redan passerat." när en adress med påminnelser på har tömning i morgon
    /// och påminnelsetiden redan passerat. Ingen ersättningsnotis skickas, eftersom varje planering annars kunde skicka en ny.
    public var missedReminderText: String? {
        _ = scheduleRevision
        for address in addresses where remindersOn(for: address) {
            if let text = AddressDetail.missedReminder(events: schedules[address.key]?.response?.events ?? [], settings: settings, now: now()) {
                return text
            }
        }
        return nil
    }

    /// Ersätter en adress som källan inte längre känner igen med en nyss sparad. Namn, huvudadress och notisval följer med,
    /// och den gamla tas bort först när den nya är sparad. Allt sparas i ett steg, så inga dubbla notiser blir kvar.
    @discardableResult
    public func replace(_ old: AddressKey, with new: AddressKey) -> Bool {
        guard old != new,
              let oldAddress = addresses.first(where: { $0.key == old }),
              let newAddress = addresses.first(where: { $0.key == new })
        else { return false }
        var merged = newAddress
        merged.displayName = oldAddress.displayName
        merged.isPrimary = oldAddress.isPrimary
        merged.notificationsOn = oldAddress.notificationsOn
        let updated = addresses.compactMap { address -> SavedAddress? in
            if address.key == old { return nil }
            return address.key == new ? merged : address
        }
        guard saveAddresses(updated) else { return false }
        schedules[old] = nil
        scheduleRevision += 1
        removeStoredSchedule(for: old)
        widgetReloader()
        applyReminders()
        return true
    }

    /// Slår notiser för en adress på eller av. Frågan om tillstånd ställs först när de slås på och tillståndet
    /// inte är avgjort. `denied` betyder att iOS nekar. `failed` betyder att valet inte gick att spara eller att adressen
    /// inte finns, och då är `lastStorageError` satt. Att stänga av kräver inget tillstånd.
    public func setNotifications(_ on: Bool, for key: AddressKey) async -> PermissionResult {
        guard on else {
            return setNotificationsOn(false, for: key) ? .granted : .failed
        }
        guard addresses.contains(where: { $0.key == key }) else { return .failed }
        var status = await scheduler.authorization()
        if status == .notDetermined {
            status = await scheduler.requestAuthorization() ? .authorized : .denied
        }
        notificationAuthorization = status
        // Nekas tillstånd ändras aldrig `notificationsOn`. Valet är kvar och visas som av, så att notiserna planeras igen
        // när tillståndet kommer tillbaka.
        guard status == .authorized else { return .denied }
        return setNotificationsOn(true, for: key) ? .granted : .failed
    }

    private func setNotificationsOn(_ on: Bool, for key: AddressKey) -> Bool {
        guard addresses.contains(where: { $0.key == key }) else { return false }
        let updated = addresses.map { address in
            var copy = address
            if address.key == key { copy.notificationsOn = on }
            return copy
        }
        guard updated == addresses || saveAddresses(updated) else { return false }
        applyReminders()
        return true
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
        reloadStorageIfNeeded()
        // Går adresserna eller inställningarna inte att läsa vet appen inte vad användaren valt, så inget ändras.
        guard addressesReadable, settingsReadable else { return }
        let status = await scheduler.authorization()
        notificationAuthorization = status
        // Utan tillstånd rörs inget: `notificationsOn` är kvar, och när tillståndet kommer tillbaka planeras notiserna igen.
        guard status == .authorized else { return }
        // Bara notiser som appen själv skapat räknas, även om schemaläggaren skulle lämna fler.
        let pending = await scheduler.pending().filter { NotificationDiff.isOwn(identifier: $0.identifier) }
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
        let desired = ReminderPlanner.plan(input).notifications
        let changes = NotificationDiff.diff(
            desired: desired,
            pendingIds: Set(pending.map(\.identifier)),
            pendingFireDates: Dictionary(pending.compactMap { p in p.fireDate.map { (p.identifier, $0) } }, uniquingKeysWith: { first, _ in first }),
            pendingBodies: Dictionary(pending.map { ($0.identifier, $0.body) }, uniquingKeysWith: { first, _ in first })
        )
        // En adress med påminnelser på men utan läsbart schema behåller sina väntande notiser tills ett schema finns.
        let protected = addresses.filter { $0.notificationsOn && schedules[$0.key]?.response == nil }.map { "\($0.key.fileName)-" }
        // En ersatt notis läggs in med samma identifierare, som ersätter den gamla. Den tas därför inte bort först.
        let replaced = Set(changes.add.map(\.identifier))
        let removals = changes.removeIds.filter { id in
            !replaced.contains(id) && !protected.contains { id.hasPrefix($0) }
        }
        if !removals.isEmpty { await scheduler.cancel(identifiers: removals) }
        let failed = changes.add.isEmpty ? [] : await scheduler.schedule(changes.add)
        reminderError = failed.isEmpty ? nil : "Några påminnelser kunde inte läggas in. Appen försöker igen nästa gång den öppnas."
    }
}
