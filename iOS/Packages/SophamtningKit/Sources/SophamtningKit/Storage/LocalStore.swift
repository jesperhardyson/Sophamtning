import Foundation

/// Lokal lagring som JSON-filer, delad mellan appen och widgeten via App Group.
/// Skrivningar är atomiska, och en fil som saknas eller är skadad läses som saknad.
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

    public func setAddresses(_ addresses: [SavedAddress]) {
        write(addresses, to: "addresses.json")
    }

    public func settings() -> ReminderSettings {
        read(ReminderSettings.self, from: "settings.json") ?? ReminderSettings()
    }

    public func setSettings(_ settings: ReminderSettings) {
        write(settings, to: "settings.json")
    }

    public func placedOut() -> [PlacedOut] {
        read([PlacedOut].self, from: "placed-out.json") ?? []
    }

    public func setPlacedOut(_ placedOut: [PlacedOut]) {
        write(placedOut, to: "placed-out.json")
    }

    public func sources() -> CachedSources? {
        read(CachedSources.self, from: "sources.json")
    }

    public func setSources(_ sources: CachedSources) {
        write(sources, to: "sources.json")
    }

    // MARK: Scheman

    public func schedule(for key: AddressKey) -> CachedSchedule? {
        read(CachedSchedule.self, from: scheduleFile(key))
    }

    public func setSchedule(_ schedule: CachedSchedule, for key: AddressKey) {
        write(schedule, to: scheduleFile(key))
    }

    public func removeSchedule(for key: AddressKey) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(scheduleFile(key)))
    }

    // MARK: Filer

    private func scheduleFile(_ key: AddressKey) -> String {
        "schedules/\(key.fileName).json"
    }

    private func read<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(path)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Ett skrivfel ger ingen krasch. Nästa läsning ger då det som låg där förut.
    private func write<T: Encodable>(_ value: T, to path: String) {
        let url = directory.appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Kunde inte skriva \(path): \(error)")
        }
    }
}
