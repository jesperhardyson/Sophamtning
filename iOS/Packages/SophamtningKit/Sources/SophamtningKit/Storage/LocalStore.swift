import Foundation

/// Resultatet av att läsa en fil. `missing` är en fil som inte finns, vilket är ett normalt läge. Finns den men går inte att läsa
/// får appen aldrig skriva över den. `unavailable`: själva läsningen misslyckades (till exempel skyddad data före upplåsning),
/// så innehållet kan vara helt i sin ordning. `unreadable`: läsningen gick bra men innehållet går inte att tolka, alltså skadat.
public enum StoreRead<Value: Sendable>: Sendable {
    case missing
    case value(Value)
    case unavailable
    case unreadable
}

/// Lokal lagring som JSON-filer, delad mellan appen och widgeten via App Group.
/// Skrivningar är atomiska, och en fil som saknas eller är skadad läses som saknad.
/// Skrivfel kastas, så att anroparen kan visa dem.
///
/// Varje fil skrivs om i sin helhet. Skriver två processer samtidigt till samma fil kan en uppdatering gå förlorad.
/// `placed-out.json` skrivs också utanför appen, av knappen **Utställt**, och den läses och skrivs därför med
/// `NSFileCoordinator`. `shown-activities.json` och `ended-activities.json` hanteras på samma sätt.
public final class LocalStore: Sendable {
    public static let appGroup = "group.se.hardyson.sophamtning"
    private static let placedOutFile = "placed-out.json"
    private static let shownFile = "shown-activities.json"
    private static let endedFile = "ended-activities.json"
    private static let householdFile = "household.json"
    private static let householdPreferencesFile = "household-preferences.json"

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// App Group-behållaren, eller Application Support om behållaren saknas.
    public static func shared() -> LocalStore {
        let manager = FileManager.default
        if let container = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return LocalStore(directory: container.appendingPathComponent("Sophamtning", isDirectory: true))
        }
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        return LocalStore(directory: support.appendingPathComponent("Sophamtning", isDirectory: true))
    }

    // MARK: Adresser, inställningar, utställda och källor

    public func addresses() -> [SavedAddress] {
        read([SavedAddress].self, from: "addresses.json") ?? []
    }

    /// Som `addresses()`, men skiljer en fil som saknas från en som inte går att läsa.
    public func addressesState() -> StoreRead<[SavedAddress]> {
        readState([SavedAddress].self, from: "addresses.json")
    }

    public func settingsState() -> StoreRead<ReminderSettings> {
        readState(ReminderSettings.self, from: "settings.json")
    }

    public func scheduleState(for key: AddressKey) -> StoreRead<CachedSchedule> {
        readState(CachedSchedule.self, from: scheduleFile(key))
    }

    public func setAddresses(_ addresses: [SavedAddress]) throws {
        try write(addresses, to: "addresses.json")
    }

    public func settings() -> ReminderSettings {
        read(ReminderSettings.self, from: "settings.json") ?? ReminderSettings()
    }

    public func setSettings(_ settings: ReminderSettings) throws {
        try write(settings, to: "settings.json")
    }

    public func placedOut() -> [PlacedOut] {
        if case .value(let saved) = placedOutState() { return saved }
        return []
    }

    public func placedOutState() -> StoreRead<[PlacedOut]> {
        readCoordinated(Self.placedOutFile)
    }

    public func setPlacedOut(_ placedOut: [PlacedOut]) throws {
        try updateCoordinated(Self.placedOutFile) { _ in placedOut }
    }

    /// Lägger till en post utan att tappa någon som en annan process skriver samtidigt. Passerade poster rensas samtidigt.
    public func markPlacedOut(_ entry: PlacedOut, today: DayDate) throws {
        try updateCoordinated(Self.placedOutFile) { saved in
            let current = saved.filter { $0.date >= today }
            return current.contains(entry) ? current : current + [entry]
        }
    }

    /// Tar bort en enskild post, till exempel när jag ångrar min bock. Finns den inte skrivs ingenting.
    public func unmarkPlacedOut(_ entry: PlacedOut) throws {
        try updateCoordinated(Self.placedOutFile) { saved in saved.filter { $0 != entry } }
    }

    /// Tar bort poster vars datum har passerat. Finns inget att ta bort skrivs ingenting.
    public func prunePlacedOut(today: DayDate) throws {
        try updateCoordinated(Self.placedOutFile) { saved in saved.filter { $0.date >= today } }
    }

    // MARK: Hushåll

    /// Det senast kända hushållet. En fil som saknas är `missing`, och en som inte går att läsa är aldrig ett tomt hushåll.
    public func householdState() -> StoreRead<HouseholdState> {
        readState(HouseholdState.self, from: Self.householdFile)
    }

    public func setHouseholdState(_ state: HouseholdState) throws {
        try write(state, to: Self.householdFile)
    }

    public func householdPreferences() -> HouseholdPreferences {
        read(HouseholdPreferences.self, from: Self.householdPreferencesFile) ?? HouseholdPreferences()
    }

    public func setHouseholdPreferences(_ preferences: HouseholdPreferences) throws {
        try write(preferences, to: Self.householdPreferencesFile)
    }

    // MARK: Visade och avslutade aktiviteter

    /// Tömningar vars Live Activity bevisligen har visats: pågående sedd eller lyckad direktstart. Bara de släcker reservnotisen.
    /// Går filen inte att läsa är listan tom, och reservnotisen behålls: det är den säkra riktningen.
    public func shownActivities() -> [PlacedOut] {
        if case .value(let saved) = readCoordinated(Self.shownFile) { return saved }
        return []
    }

    /// Lägger till poster och rensar passerade. Finns inget nytt skrivs ingenting.
    public func markShown(_ entries: [PlacedOut], today: DayDate) throws {
        try mark(entries, in: Self.shownFile, today: today)
    }

    public func clearShown() throws {
        try updateCoordinated(Self.shownFile) { _ in [] }
    }

    /// Tömningar vars aktivitet har avslutats eller svepts bort efter sin start. De startas inte om, men det är inget bevis för att
    /// aktiviteten syntes, så reservnotisen står kvar. Går filen inte att läsa är listan tom, och aktiviteten startas.
    public func endedActivities() -> [PlacedOut] {
        if case .value(let saved) = readCoordinated(Self.endedFile) { return saved }
        return []
    }

    public func markEnded(_ entries: [PlacedOut], today: DayDate) throws {
        try mark(entries, in: Self.endedFile, today: today)
    }

    public func clearEnded() throws {
        try updateCoordinated(Self.endedFile) { _ in [] }
    }

    private func mark(_ entries: [PlacedOut], in file: String, today: DayDate) throws {
        try updateCoordinated(file) { saved in
            var current = saved.filter { $0.date >= today }
            for entry in entries where entry.date >= today && !current.contains(entry) { current.append(entry) }
            return current
        }
    }

    // MARK: Samordnade filer

    private func readCoordinated(_ file: String) -> StoreRead<[PlacedOut]> {
        let url = directory.appendingPathComponent(file)
        var result: StoreRead<[PlacedOut]> = .unavailable
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { current in
            result = decodePlacedOut(at: current)
        }
        return result
    }

    /// Läser och skriver under samma samordning, så att ingen annan skrivning hamnar mellan läsningen och skrivningen.
    /// Filen går att ersätta om den är skadad, eftersom det värsta som går förlorat är att en tömning kan startas igen.
    /// Går den inte att läsa just nu skrivs den aldrig över.
    private func updateCoordinated(_ file: String, _ change: ([PlacedOut]) -> [PlacedOut]) throws {
        let url = directory.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var failure: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { current in
            do {
                let saved: [PlacedOut]
                switch decodePlacedOut(at: current) {
                case .value(let value): saved = value
                case .missing, .unreadable: saved = []
                case .unavailable: throw CocoaError(.fileReadNoPermission)
                }
                let updated = change(saved)
                // En oförändrad fil skrivs inte, och en rensning utan fil skapar ingen.
                if updated != saved { try encode(updated, to: current) }
            } catch {
                failure = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
    }

    private func decodePlacedOut(at url: URL) -> StoreRead<[PlacedOut]> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unavailable }
        guard let value = try? JSONDecoder().decode([PlacedOut].self, from: data) else { return .unreadable }
        return .value(value)
    }

    public func sources() -> CachedSources? {
        read(CachedSources.self, from: "sources.json")
    }

    public func setSources(_ sources: CachedSources) throws {
        try write(sources, to: "sources.json")
    }

    // MARK: Scheman

    public func schedule(for key: AddressKey) -> CachedSchedule? {
        read(CachedSchedule.self, from: scheduleFile(key))
    }

    public func setSchedule(_ schedule: CachedSchedule, for key: AddressKey) throws {
        try write(schedule, to: scheduleFile(key))
    }

    public func removeSchedule(for key: AddressKey) throws {
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(scheduleFile(key)))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Ett schema som redan saknas är inte ett fel.
        }
    }

    /// Flyttar en fil som inte går att läsa åt sidan (`<namn>.skadad-<tid>`) i stället för att radera den.
    public func moveAsideAddresses(at date: Date) throws { try moveAside("addresses.json", at: date) }
    public func moveAsideSettings(at date: Date) throws { try moveAside("settings.json", at: date) }

    private func moveAside(_ path: String, at date: Date) throws {
        let source = directory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = Int(date.timeIntervalSince1970)
        try FileManager.default.moveItem(at: source, to: directory.appendingPathComponent("\(path).skadad-\(stamp)"))
    }

    // MARK: Filer

    private func scheduleFile(_ key: AddressKey) -> String {
        "schedules/\(key.fileName).json"
    }

    private func readState<T: Decodable & Sendable>(_ type: T.Type, from path: String) -> StoreRead<T> {
        let url = directory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unavailable }
        guard let value = try? JSONDecoder().decode(type, from: data) else { return .unreadable }
        return .value(value)
    }

    private func read<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(path)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to path: String) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(value, to: url)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        // Filerna ska gå att läsa i bakgrunden och från widgeten efter första upplåsningen. Med strängare skydd ger
        // de bakgrundsuppdateringen och widgeten tomma läsningar medan telefonen är låst.
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
