import Foundation
import Security
import SophamtningKit

/// Hushållets nycklar i nyckelringen. Med `synchronizable` följer de med iCloud-nyckelringen till mina andra enheter och
/// till en ny iPhone. Utan den stannar kopian på den här telefonen.
struct KeychainCredentialStore: HouseholdCredentialStore {
    let synchronizable: Bool

    private var item: KeychainItem {
        KeychainItem(account: "nycklar", synchronizable: synchronizable)
    }

    func load() throws -> HouseholdCredentials? {
        guard let data = try item.load() else { return nil }
        return try JSONDecoder().decode(HouseholdCredentials.self, from: data)
    }

    func save(_ credentials: HouseholdCredentials) throws {
        try item.save(JSONEncoder().encode(credentials))
    }

    func delete() throws {
        try item.delete()
    }

    /// Telefonens id mot brevlådan. Det hör till telefonen och följer aldrig med till en annan.
    static let deviceId: @Sendable () -> String = {
        let item = KeychainItem(account: "enhet", synchronizable: false)
        if let data = try? item.load(), let id = String(data: data, encoding: .utf8) { return id }
        // Går nyckelringen inte att läsa blir id:t tillfälligt, och servern behåller bara de senaste enheterna.
        let id = newDeviceId
        try? item.save(Data(id.utf8))
        return id
    }

    private static let newDeviceId = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

/// En post i nyckelringen. `load` svarar `nil` bara när posten säkert saknas, och kastar när den inte går att läsa, till
/// exempel innan telefonen har låsts upp.
struct KeychainItem {
    let account: String
    let synchronizable: Bool

    struct Failure: Error {
        let status: OSStatus
    }

    private var query: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "se.hardyson.sophamtning.hushall",
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable,
        ]
    }

    func load() throws -> Data? {
        var query = query
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }

    func save(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw Failure(status: status) }
        var item = query
        item[kSecValueData] = data
        // Synken körs i bakgrunden med telefonen låst, men bara efter första upplåsningen.
        item[kSecAttrAccessible] = synchronizable ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure(status: added) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
