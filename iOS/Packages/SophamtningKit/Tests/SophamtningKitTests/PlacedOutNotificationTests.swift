import Foundation
import Testing
@testable import SophamtningKit

private let key = AddressKey(source: "avesta", id: "Kaplansgården|Jularbo m.fl.")
private let day = DayDate("2026-11-11")!

@Test func notisenBärTömningen() {
    let info = PlacedOutNotification.userInfo(key: key, date: day)
    #expect(PlacedOutNotification.entry(from: info) == PlacedOut(key: key, date: day))
}

@Test func adressIdAnvändsSomDetÄr() {
    // Id:t tolkas och byggs aldrig om, också med tecken som | och mellanslag.
    let info = PlacedOutNotification.userInfo(key: key, date: day)
    #expect(info["adressId"] as? String == "Kaplansgården|Jularbo m.fl.")
}

@Test func trasigNotisGerIngenTömning() {
    #expect(PlacedOutNotification.entry(from: [:]) == nil)
    #expect(PlacedOutNotification.entry(from: ["kalla": "avesta", "adressId": "x", "datum": "11 nov"]) == nil)
    #expect(PlacedOutNotification.entry(from: ["kalla": "avesta", "datum": "2026-11-11"]) == nil)
}

@Test func knappenOchKategorin() {
    #expect(PlacedOutNotification.actionTitle == "Utställt")
    #expect(PlacedOutNotification.categoryIdentifier == "paminnelse")
    #expect(PlacedOutNotification.actionIdentifier == "utstallt")
}
