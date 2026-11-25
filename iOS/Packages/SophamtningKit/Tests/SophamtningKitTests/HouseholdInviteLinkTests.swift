import Foundation
import Testing
@testable import SophamtningKit

private let key = Data((0..<32).map { UInt8($0) })
private let id = Data((0..<16).map { UInt8($0) }).base64URL
private let token = Data((0..<32).map { UInt8(255 - $0) }).base64URL

@Test func lankTillOchFran() throws {
    let link = HouseholdInviteLink(householdId: id, inviteToken: token, householdKey: key)
    #expect(link.url.absoluteString == "https://sopor.hardyson.se/hushall#1.\(id).\(token).\(key.base64URL)")
    #expect(HouseholdInviteLink(url: link.url) == link)
}

@Test(arguments: [
    "https://sopor.hardyson.se/hushall",
    "https://sopor.hardyson.se/hushall#",
    "https://sopor.hardyson.se/hushall#2.ID.TOKEN.KEY",
    "https://sopor.hardyson.se/annat#1.ID.TOKEN.KEY",
    "https://sopor.hardyson.se.example.com/hushall#1.ID.TOKEN.KEY",
    "https://example.com/hushall#1.ID.TOKEN.KEY",
    "http://sopor.hardyson.se/hushall#1.ID.TOKEN.KEY",
    "https://sopor.hardyson.se/hushall#1.ID.TOKEN",
    "https://sopor.hardyson.se/hushall#1.ID.TOKEN.KEY.mer",
    "https://sopor.hardyson.se/hushall#1.kort.TOKEN.KEY",
    "https://sopor.hardyson.se/hushall#1.ID.kort.KEY",
    "https://sopor.hardyson.se/hushall#1.ID.TOKEN.AAAA",
    "https://sopor.hardyson.se/hushall#1.ID.TOKEN.KEY=",
])
func lankMedFelVersionEllerVardEllerDelarGerNil(_ text: String) throws {
    let filled = text
        .replacingOccurrences(of: "KEY", with: key.base64URL)
        .replacingOccurrences(of: "TOKEN", with: token)
        .replacingOccurrences(of: "ID", with: id)
    #expect(HouseholdInviteLink(url: try #require(URL(string: filled))) == nil)
}

@Test func lankenMedSnedstreckSistGarAttLasa() throws {
    let url = try #require(URL(string: "https://sopor.hardyson.se/hushall/#1.\(id).\(token).\(key.base64URL)"))
    #expect(HouseholdInviteLink(url: url)?.householdId == id)
}

/// Nyckeln får aldrig hamna i en logg av misstag.
@Test func lankenSkriverInteUtNyckeln() {
    let link = HouseholdInviteLink(householdId: id, inviteToken: token, householdKey: key)
    for text in ["\(link)", String(reflecting: link)] {
        #expect(!text.contains(token))
        #expect(!text.contains(key.base64URL))
    }
}
