import Foundation
import Testing
@testable import SophamtningKit

@Suite("Hushållets logik och texter")
struct HouseholdLogicTests {
    let today = DayDate("2026-11-10")!
    let home = AddressKey(source: "avesta", id: "hemma")
    let work = AddressKey(source: "avesta", id: "jobbet")

    func address(_ key: AddressKey, name: String = "Adress", primary: Bool = false, notifications: Bool = false) -> SavedAddress {
        SavedAddress(key: key, url: URL(string: "https://sopor.hardyson.se/api/v1/adress/\(key.source)/\(key.id)")!, street: "Storgatan 3", locality: "Avesta", kommun: "Avesta kommun", detail: nil, selection: "address", displayName: name, isPrimary: primary, notificationsOn: notifications, addedAt: Date(timeIntervalSince1970: 0))
    }

    func mark(_ key: AddressKey, _ iso: String, by: String = "kim", at: Date = Date(timeIntervalSince1970: 0)) -> HouseholdMark {
        HouseholdMark(placedOut: PlacedOut(key: key, date: DayDate(iso)!), by: by, at: at, isPending: false)
    }

    @Test func knappenVisasDagenForeOchTomningsdagen() {
        #expect(HouseholdLogic.showsPlaceOutButton(isShared: true, nextPickup: DayDate("2026-11-10")!, today: today))
        #expect(HouseholdLogic.showsPlaceOutButton(isShared: true, nextPickup: DayDate("2026-11-11")!, today: today))
        #expect(!HouseholdLogic.showsPlaceOutButton(isShared: true, nextPickup: DayDate("2026-11-12")!, today: today))
        #expect(!HouseholdLogic.showsPlaceOutButton(isShared: true, nextPickup: nil, today: today))
        #expect(!HouseholdLogic.showsPlaceOutButton(isShared: false, nextPickup: DayDate("2026-11-10")!, today: today))
        #expect(!HouseholdLogic.showsPlaceOutButton(isShared: false, nextPickup: DayDate("2026-11-11")!, today: today))
    }

    @Test func bockGallerStockholmsDatum() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let pressed = newYork.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 30))!
        // Samma ögonblick är 05:30 den 11:e i Stockholm.
        #expect(StockholmClock.today(now: pressed) == DayDate("2026-11-11"))
        let marks = [mark(home, "2026-11-11", by: "jag", at: pressed)]
        let next = DayDate("2026-11-11")!
        #expect(HouseholdLogic.currentMark(for: home, nextPickup: next, in: marks)?.placedOut.date == next)
        #expect(HouseholdLogic.expired(marks, today: next).isEmpty)
        #expect(HouseholdLogic.currentMark(for: home, nextPickup: nil, in: marks) == nil)
        #expect(HouseholdLogic.currentMark(for: work, nextPickup: next, in: marks) == nil)
    }

    @Test func bockForbrukasDagenEfter() {
        let marks = [mark(home, "2026-11-10")]
        #expect(HouseholdLogic.expired(marks, today: DayDate("2026-11-11")!) == marks)
        #expect(HouseholdLogic.expired(marks, today: DayDate("2026-11-10")!).isEmpty)
    }

    @Test func egnaBockarRaknasInteSomAndras() {
        let mine = mark(home, "2026-11-11", by: "jag")
        let kims = mark(work, "2026-11-11", by: "kim")
        #expect(HouseholdLogic.othersActive([mine, kims], myId: "jag", today: today) == [kims])
    }

    @Test func passeradeBockarArInteAktiva() {
        let old = mark(work, "2026-11-09", by: "kim")
        #expect(HouseholdLogic.othersActive([old], myId: "jag", today: today).isEmpty)
    }

    @Test func sammaAdressSlasIhopOchBehallerEgnaVal() {
        let mine = address(home, name: "Hemma", primary: true, notifications: true)
        let shared = [HouseholdAddress(address: address(home, name: "Kims namn"), addedBy: "kim")]
        let result = HouseholdLogic.merge(shared: shared, into: [mine], received: [])
        #expect(result.list.count == 1)
        #expect(result.list[0].displayName == "Hemma")
        #expect(result.list[0].notificationsOn)
        #expect(result.received.isEmpty)
    }

    @Test func mottagenAdressHarNotisAv() {
        let mine = address(home, primary: true)
        let incoming = address(work, primary: true, notifications: true)
        let result = HouseholdLogic.merge(shared: [HouseholdAddress(address: incoming, addedBy: "kim")], into: [mine], received: [])
        let added = result.list.first { $0.key == work }
        #expect(result.list.count == 2)
        #expect(added?.notificationsOn == false)
        #expect(added?.isPrimary == false)
        #expect(result.received == [work])
    }

    @Test func slutarDelasTarBaraBortMottagna() {
        let list = [address(home, primary: true), address(work)]
        let other = AddressKey(source: "avesta", id: "egen")
        let both = list + [address(other)]
        // Hemma och jobbet slutar delas; bara jobbet är mottaget.
        let result = HouseholdLogic.merge(shared: [], into: both, received: [work])
        #expect(Set(result.list.map(\.key)) == [home, other])
        #expect(result.received.isEmpty)
    }

    @Test func texten() {
        // 19:42 svensk tid den 10 november är 18:42 UTC.
        let at = StockholmClock.date(on: today, minutes: 19 * 60 + 42)
        let participants = [HouseholdParticipant(id: "jag", name: "Jesper", isOwner: true), HouseholdParticipant(id: "kim", name: "Kim", isOwner: false)]
        #expect(HouseholdTexts.placedOut(mark(home, "2026-11-11", by: "kim", at: at), participants: participants, myId: "jag") == "Utställt av Kim, kl. 19:42")
        #expect(HouseholdTexts.placedOut(mark(home, "2026-11-11", by: "jag", at: at), participants: participants, myId: "jag") == "Utställt av dig, kl. 19:42")
        #expect(HouseholdTexts.othersPlacedOutNotification(name: "Kim", address: "Storgatan 3") == "Kim ställde ut kärlen för Storgatan 3")
        #expect(HouseholdTexts.status(.quotaExceeded(ownerName: "Kim")) == "Kims iCloud-lagring är full, så hushållet kan inte uppdateras.")
        #expect(HouseholdTexts.status(.quotaExceeded(ownerName: "Lars")) == "Lars iCloud-lagring är full, så hushållet kan inte uppdateras.")
        #expect(HouseholdTexts.status(.notSignedIn) == "Synkar inte just nu")
        #expect(HouseholdTexts.status(.failed) == "Hushållet kunde inte uppdateras just nu")
        #expect(HouseholdTexts.status(.removed) == HouseholdTexts.leftNote)
        #expect(HouseholdTexts.status(.synced) == nil)
    }

    @Test func okandDeltagareHeterNagon() {
        let at = StockholmClock.date(on: today, minutes: 19 * 60 + 42)
        #expect(HouseholdTexts.placedOut(mark(home, "2026-11-11", by: "okand", at: at), participants: [], myId: "jag") == "Utställt av någon, kl. 19:42")
    }
}
