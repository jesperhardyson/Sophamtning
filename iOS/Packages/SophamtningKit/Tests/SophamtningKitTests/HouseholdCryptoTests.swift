import Foundation
import Testing
@testable import SophamtningKit

/// Formatet som servern, iOS och Android delar. Se `Server/test/vectors.json`.
struct HouseholdVectors: Decodable {
    struct Record: Decodable {
        var title: String, kind: RelayRecordKind, logical: String, name: String, plaintext: String, nonce: String, data: String
    }
    struct Name: Decodable {
        var title: String, participantId: String, plaintext: String, nonce: String, data: String
    }
    var householdId: String, householdKey: String, records: [Record], names: [Name]

    static func load() throws -> HouseholdVectors {
        let url = try #require(Bundle.module.url(forResource: "hushall-vectors", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(HouseholdVectors.self, from: Data(contentsOf: url))
    }

    var crypto: HouseholdCrypto {
        get throws { try HouseholdCrypto(householdId: householdId, householdKey: #require(Data(base64URL: householdKey))) }
    }
}

@Test func vektorernaStammer() throws {
    let vectors = try HouseholdVectors.load()
    let crypto = try vectors.crypto
    #expect(vectors.records.count == 4)
    for vector in vectors.records {
        #expect(crypto.recordName(vector.logical) == vector.name, "\(vector.title)")
        let nonce = try #require(Data(base64URL: vector.nonce))
        #expect(try crypto.seal(Data(vector.plaintext.utf8), name: vector.name, kind: vector.kind, nonce: nonce) == vector.data, "\(vector.title)")
        #expect(try crypto.open(vector.data, name: vector.name, kind: vector.kind) == Data(vector.plaintext.utf8), "\(vector.title)")
    }
    for vector in vectors.names {
        let nonce = try #require(Data(base64URL: vector.nonce))
        #expect(try crypto.sealName(Data(vector.plaintext.utf8), participantId: vector.participantId, nonce: nonce) == vector.data)
        #expect(try crypto.openName(vector.data, participantId: vector.participantId) == Data(vector.plaintext.utf8))
    }
}

@Test func vektorfilenArSammaSomServerns() throws {
    let copy = try #require(Bundle.module.url(forResource: "hushall-vectors", withExtension: "json", subdirectory: "Fixtures"))
    var root = URL(filePath: #filePath)
    for _ in 0..<6 { root.deleteLastPathComponent() }
    let original = root.appending(path: "Server/test/vectors.json")
    #expect(try Data(contentsOf: copy) == Data(contentsOf: original))
}

@Test func adresserFranVektorernaGarAttLasa() throws {
    let vectors = try HouseholdVectors.load()
    let addresses = try vectors.records.filter { $0.kind == .address }.map {
        try JSONDecoder().decode(AddressPlaintext.self, from: Data($0.plaintext.utf8)).address
    }
    #expect(addresses.map(\.url.absoluteString) == [
        "https://sopor.hardyson.se/api/v1/adresser/avesta-vatten/%C3%96vre%20%C3%85gatan%203%7C12",
        "https://sopor.hardyson.se/api/v1/adresser/vafab/77",
    ])
    #expect(addresses.map(\.key.fileName) == vectors.records.filter { $0.kind == .address }.map(\.logical))
    #expect(addresses.map(\.detail) == ["Lägenhet", nil])
    #expect(addresses.map(\.notificationsOn) == [true, false])
}

@Test func bockarnaFranVektorernaGarAttLasa() throws {
    let marks = try HouseholdVectors.load().records.filter { $0.kind == .mark }.map {
        try JSONDecoder().decode(MarkPlaintext.self, from: Data($0.plaintext.utf8))
    }
    #expect(marks.map(\.date.iso) == ["2026-11-27", "2026-11-30"])
    #expect(marks[0].legacy == nil)
    #expect(marks[1].legacy?.by == "_0123456789abcdef")
    #expect(marks[1].legacy?.at == Date(timeIntervalSince1970: 1_795_459_327))
}

@Test func felAADGerFel() throws {
    let vectors = try HouseholdVectors.load()
    let crypto = try vectors.crypto
    let vector = vectors.records[0]
    #expect(throws: (any Error).self) { try crypto.open(vector.data, name: vectors.records[1].name, kind: vector.kind) }
    #expect(throws: (any Error).self) { try crypto.open(vector.data, name: vector.name, kind: .mark) }
    let other = try HouseholdCrypto(householdId: "annat", householdKey: #require(Data(base64URL: vectors.householdKey)))
    #expect(throws: (any Error).self) { try other.open(vector.data, name: vector.name, kind: vector.kind) }
    let otherKey = HouseholdCrypto(householdId: vectors.householdId, householdKey: HouseholdCrypto.newKey())
    #expect(throws: (any Error).self) { try otherKey.open(vector.data, name: vector.name, kind: vector.kind) }
    #expect(throws: (any Error).self) { try crypto.open("AAAA", name: vector.name, kind: vector.kind) }
    #expect(throws: (any Error).self) { try crypto.open("inte base64url!", name: vector.name, kind: vector.kind) }
}

@Test func sammaTextKrypterasOlika() throws {
    let crypto = HouseholdCrypto(householdId: "h", householdKey: HouseholdCrypto.newKey())
    let text = Data("hej".utf8)
    let first = try crypto.seal(text, name: "n", kind: .mark)
    let second = try crypto.seal(text, name: "n", kind: .mark)
    #expect(first != second)
    #expect(try crypto.open(first, name: "n", kind: .mark) == text)
    #expect(HouseholdCrypto.newKey().count == 32)
}

@Test func base64URLTillOchFran() {
    for count in 0..<40 {
        let data = Data((0..<count).map { UInt8(($0 * 37 + 251) % 256) })
        #expect(!data.base64URL.contains { "+/=".contains($0) })
        #expect(Data(base64URL: data.base64URL) == data)
    }
    #expect(Data(base64URL: "AA==") == nil)
    #expect(Data(base64URL: "A+/A") == nil)
    #expect(Data(base64URL: "å") == nil)
}
