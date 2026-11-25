import CryptoKit
import Foundation

public enum RelayRecordKind: String, Codable, Sendable {
    case address, mark
}

/// Hushållets kryptering. Allt innehåll krypteras på telefonen, och servern ser bara chiffertext och postnamn som är en HMAC.
/// Formatet prövas mot `hushall-vectors.json`, som Android och servern också läser.
public struct HouseholdCrypto: Sendable {
    private let householdId: String
    private let contentKey: SymmetricKey
    private let nameKey: SymmetricKey

    public init(householdId: String, householdKey: Data) {
        self.householdId = householdId
        contentKey = Self.derive(householdKey, info: "sophamtning-hushall-innehall-v1")
        nameKey = Self.derive(householdKey, info: "sophamtning-hushall-postnamn-v1")
    }

    /// En ny hushållsnyckel, 32 slumpade byte.
    public static func newKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// Postens namn hos servern, som inte avslöjar vilken adress det gäller.
    public func recordName(_ logical: String) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Data(logical.utf8), using: nameKey)).base64URL
    }

    public func seal(_ plaintext: Data, name: String, kind: RelayRecordKind) throws -> String {
        try seal(plaintext, aad: aad(name, kind), nonce: AES.GCM.Nonce())
    }

    public func open(_ data: String, name: String, kind: RelayRecordKind) throws -> Data {
        try open(data, aad: aad(name, kind))
    }

    public func sealName(_ plaintext: Data, participantId: String) throws -> String {
        try seal(plaintext, aad: nameAAD(participantId), nonce: AES.GCM.Nonce())
    }

    public func openName(_ data: String, participantId: String) throws -> Data {
        try open(data, aad: nameAAD(participantId))
    }

    // MARK: Fast nonce, bara för testvektorerna

    func seal(_ plaintext: Data, name: String, kind: RelayRecordKind, nonce: Data) throws -> String {
        try seal(plaintext, aad: aad(name, kind), nonce: AES.GCM.Nonce(data: nonce))
    }

    func sealName(_ plaintext: Data, participantId: String, nonce: Data) throws -> String {
        try seal(plaintext, aad: nameAAD(participantId), nonce: AES.GCM.Nonce(data: nonce))
    }

    // MARK: Internt

    /// Posten hör till sitt hushåll, sitt namn och sin sort, och kan inte flyttas av servern.
    private func aad(_ name: String, _ kind: RelayRecordKind) -> Data {
        Data("\(householdId).\(name).\(kind.rawValue)".utf8)
    }

    private func nameAAD(_ participantId: String) -> Data {
        Data("\(householdId).\(participantId).name".utf8)
    }

    private func seal(_ plaintext: Data, aad: Data, nonce: AES.GCM.Nonce) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: contentKey, nonce: nonce, authenticating: aad)
        // `combined` är nonce, chiffertext och tagg, och finns alltid med 12 byte nonce.
        return box.combined!.base64URL
    }

    private func open(_ data: String, aad: Data) throws -> Data {
        guard let combined = Data(base64URL: data) else { throw CryptoKitError.incorrectParameterSize }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: contentKey, authenticating: aad)
    }

    private static func derive(_ key: Data, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), info: Data(info.utf8), outputByteCount: 32)
    }
}
