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
/// Varje fil skrivs om i sin helhet. Skriver två processer samtidigt till samma fil kan en
/// uppdatering gå förlorad. Uppgift 14 hanterar det för `placed-out.json`.
public final class LocalStore: Sendable {
    public static let appGroup = "group.se.hardyson.sophamtning"

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
        read([PlacedOut].self, from: "placed-out.json") ?? []
    }

    public func setPlacedOut(_ placedOut: [PlacedOut]) throws {
        try write(placedOut, to: "placed-out.json")
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
        // Filerna ska gå att läsa i bakgrunden och från widgeten efter första upplåsningen. Med strängare skydd ger
        // de bakgrundsuppdateringen och widgeten tomma läsningar medan telefonen är låst.
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
