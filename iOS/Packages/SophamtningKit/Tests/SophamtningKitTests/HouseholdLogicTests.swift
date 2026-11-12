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

    @Test func undertextenSagerVemOchNar() {
        let at = StockholmClock.date(on: today, minutes: 19 * 60 + 42)
        let participants = [HouseholdParticipant(id: "jag", name: "Jesper", isOwner: true), HouseholdParticipant(id: "kim", name: "Kim", isOwner: false)]
        #expect(HouseholdTexts.placedOutTitle == "Utställt")
        #expect(HouseholdTexts.placedOutSubtitle(mark(home, "2026-11-11", by: "kim", at: at), participants: participants, myId: "jag") == "av Kim · kl. 19:42")
        #expect(HouseholdTexts.placedOutSubtitle(mark(home, "2026-11-11", by: "jag", at: at), participants: participants, myId: "jag") == "av dig · kl. 19:42")
        #expect(HouseholdTexts.placedOutSubtitle(mark(home, "2026-11-11", by: "okand", at: at), participants: participants, myId: "jag") == "av någon · kl. 19:42")
        #expect(HouseholdTexts.pendingSubtitle == "skickas när nätet finns")
    }

    @Test func radenHarUndertextenOchVantandeText() {
        let at = StockholmClock.date(on: today, minutes: 19 * 60 + 42)
        var placed = mark(home, "2026-11-11", by: "kim", at: at)
        let address = HouseholdAddress(address: SavedAddress.fixture(key: home, isPrimary: true), addedBy: "kim")
        let participants = [HouseholdParticipant(id: "kim", name: "Kim", isOwner: true)]
        var state = HouseholdState(role: .member, myId: "jag", participants: participants, addresses: [address], marks: [placed], status: .synced)
        let line = HouseholdLine.make(household: state, key: home, nextPickup: DayDate("2026-11-11")!, today: today)
        #expect(line?.placedOutSubtitle == "av Kim · kl. 19:42")
        placed.isPending = true
        state.marks = [placed]
        let pending = HouseholdLine.make(household: state, key: home, nextPickup: DayDate("2026-11-11")!, today: today)
        #expect(pending?.placedOutSubtitle == HouseholdTexts.pendingSubtitle)
        // VoiceOver läser fortfarande hela meningen.
        #expect(pending?.placedOutText == "Utställt av Kim, kl. 19:42")
    }

    @Test func radenSagerVilkaAdressenDelasMed() {
        let address = HouseholdAddress(address: SavedAddress.fixture(key: home, isPrimary: true), addedBy: "jag")
        let jag = HouseholdParticipant(id: "jag", name: "Jesper", isOwner: true)
        var state = HouseholdState(role: .owner, myId: "jag", participants: [jag], addresses: [address], marks: [], status: .synced)
        // Ingen annan har gått med än.
        #expect(HouseholdLine.make(household: state, key: home, nextPickup: nil, today: today)?.sharedText == "Delas med hushållet")
        state.participants.append(HouseholdParticipant(id: "sofie", name: "Sofie", isOwner: false))
        #expect(HouseholdLine.make(household: state, key: home, nextPickup: nil, today: today)?.sharedText == "Delas med Sofie")
        state.participants.append(HouseholdParticipant(id: "kim", name: "Kim", isOwner: false))
        #expect(HouseholdLine.make(household: state, key: home, nextPickup: nil, today: today)?.sharedText == "Delas med Sofie och Kim")
        // En adress som inte delas har ingen rad.
        #expect(HouseholdLine.make(household: state, key: work, nextPickup: nil, today: today)?.sharedText == nil)
        #expect(HouseholdTexts.sharedWith(["Sofie", "Kim", "Alex"]) == "Delas med Sofie, Kim och Alex")
    }

    @Test func egenUtstalldUtanBockVantar() {
        // Knappen i Live Activity har skrivit min utställda, men bocken har inte skickats till hushållet än.
        let address = HouseholdAddress(address: SavedAddress.fixture(key: home, isPrimary: true), addedBy: "jag")
        let state = HouseholdState(role: .member, myId: "jag", participants: [], addresses: [address], marks: [], status: .failed)
        let next = DayDate("2026-11-11")!
        let line = HouseholdLine.make(household: state, key: home, nextPickup: next, today: today, ownPlacedOut: [PlacedOut(key: home, date: next)])
        #expect(line?.showsButton == false)
        #expect(line?.isPending == true)
        #expect(line?.placedOutText == "Utställt av dig")
        #expect(line?.placedOutSubtitle == HouseholdTexts.pendingSubtitle)
        // En utställd för en annan tömning räknas inte.
        let later = HouseholdLine.make(household: state, key: home, nextPickup: next, today: today, ownPlacedOut: [PlacedOut(key: home, date: DayDate("2026-11-18")!)])
        #expect(later?.showsButton == true)
        // Hushållets bock går före min egen post.
        var marked = state
        marked.marks = [mark(home, "2026-11-11", by: "kim", at: StockholmClock.date(on: today, minutes: 19 * 60 + 42))]
        let kims = HouseholdLine.make(household: marked, key: home, nextPickup: next, today: today, ownPlacedOut: [PlacedOut(key: home, date: next)])
        #expect(kims?.isPending == false)
        #expect(kims?.placedOutText == "Utställt av någon, kl. 19:42")
    }

    @Test func fullLagringUtanNamn() {
        #expect(HouseholdTexts.status(.quotaExceeded(ownerName: "")) == "iCloud-lagringen är full, så hushållet kan inte uppdateras.")
        #expect(HouseholdTexts.status(.quotaExceeded(ownerName: "  ")) == "iCloud-lagringen är full, så hushållet kan inte uppdateras.")
    }

    // MARK: Nya deltagare

    @Test func nyaDeltagareJamfortMedKanda() {
        let jag = HouseholdParticipant(id: "jag", name: "Jesper", isOwner: true)
        let sofie = HouseholdParticipant(id: "sofie", name: "Sofie", isOwner: false)
        // Inga kända deltagare än: ingen är ny, inte heller de som redan var med när jag gick med.
        #expect(HouseholdLogic.newParticipants([jag, sofie], known: nil, myId: "jag").isEmpty)
        #expect(HouseholdLogic.newParticipants([jag, sofie], known: ["jag"], myId: "jag") == [sofie])
        #expect(HouseholdLogic.newParticipants([jag, sofie], known: ["jag", "sofie"], myId: "jag").isEmpty)
        // Jag själv är aldrig ny, även när mitt id saknas bland de kända.
        #expect(HouseholdLogic.newParticipants([jag, sofie], known: ["sofie"], myId: "jag").isEmpty)
    }

    @Test func textenForNyaDeltagare() {
        #expect(HouseholdTexts.joined(["Sofie"]) == "Sofie gick med i hushållet")
        #expect(HouseholdTexts.joined(["Sofie", "Kim"]) == "Sofie och Kim gick med i hushållet")
        #expect(HouseholdTexts.joined(["Sofie", "Kim", "Alex"]) == "Sofie, Kim och Alex gick med i hushållet")
        #expect(HouseholdTexts.welcome(ownerName: "Jesper") == "Du är med i Jespers hushåll. Adresser som delas visas på hemskärmen.")
        #expect(HouseholdTexts.welcome(ownerName: "Lars") == "Du är med i Lars hushåll. Adresser som delas visas på hemskärmen.")
        #expect(HouseholdTexts.notify == "Notiser från hushållet")
    }

    @Test func gamlaValUtanKandaDeltagare() throws {
        let old = #"{"silenceWhenOthersPlaceOut":true,"notifyWhenOthersPlaceOut":true,"receivedKeys":[],"notifiedMarks":[]}"#
        let decoded = try JSONDecoder().decode(HouseholdPreferences.self, from: Data(old.utf8))
        #expect(decoded.knownParticipants == nil)
        #expect(decoded.joinedNames.isEmpty)
        #expect(decoded.notifyWhenOthersPlaceOut)
    }

    @Test func widgetensRadOmVem() {
        let mark = HouseholdMark(placedOut: PlacedOut(key: home, date: today), by: "sofie", at: Date(), isPending: false)
        let sofie = HouseholdParticipant(id: "sofie", name: "Sofie", isOwner: false)
        #expect(HouseholdTexts.widgetPlacedOut == "Utställda")
        #expect(HouseholdTexts.placedOutBy(mark, participants: [sofie], myId: "jag") == "av Sofie")
        #expect(HouseholdTexts.placedOutBy(mark, participants: [sofie], myId: "sofie") == "av dig")
        #expect(HouseholdTexts.placedOutBy(mark, participants: [], myId: "jag") == "av någon")
    }

    // MARK: Ställa ut utan hushåll

    @Test func knappenVisasForEgenAdressMedPaminnelser() {
        #expect(HouseholdLogic.showsPlaceOutButton(isShared: false, remindersOn: true, nextPickup: DayDate("2026-11-10")!, today: today))
        #expect(HouseholdLogic.showsPlaceOutButton(isShared: false, remindersOn: true, nextPickup: DayDate("2026-11-11")!, today: today))
        #expect(!HouseholdLogic.showsPlaceOutButton(isShared: false, remindersOn: true, nextPickup: DayDate("2026-11-12")!, today: today))
        #expect(!HouseholdLogic.showsPlaceOutButton(isShared: false, remindersOn: false, nextPickup: DayDate("2026-11-10")!, today: today))
    }

    /// Efter Ångra på tömningsdagen ska kärlen gå att ställa ut igen, också utan hushåll.
    @Test func egenAdressUtanBockFarKnappenNarPaminnelserArPa() throws {
        let line = try #require(HouseholdLine.make(household: .empty, key: home, nextPickup: today, today: today, remindersOn: true))
        #expect(line.showsButton)
        #expect(!line.isShared)
        #expect(line.placedOutText == nil)
        #expect(line.sharedText == nil)
    }

    @Test func egenAdressUtanPaminnelserFarIngenKnapp() {
        #expect(HouseholdLine.make(household: .empty, key: home, nextPickup: today, today: today, remindersOn: false) == nil)
    }

    @Test func egenAdressLangtTillTomningFarIngenKnapp() {
        #expect(HouseholdLine.make(household: .empty, key: home, nextPickup: DayDate("2026-11-12")!, today: today, remindersOn: true) == nil)
    }

    @Test func egenUtstalldAdressVisarBockenUtanKnapp() throws {
        let line = try #require(HouseholdLine.make(household: .empty, key: home, nextPickup: today, today: today, ownPlacedOut: [PlacedOut(key: home, date: today)], remindersOn: true))
        #expect(!line.showsButton)
        #expect(line.placedOutText == HouseholdTexts.ownPlacedOut)
    }

    @Test func egenAdressIHushalletFarKnappenNarPaminnelserArPa() throws {
        let state = HouseholdState(role: .owner, myId: "jag", participants: [], addresses: [], marks: [], status: .synced)
        let line = try #require(HouseholdLine.make(household: state, key: home, nextPickup: today, today: today, remindersOn: true))
        #expect(line.showsButton)
        #expect(!line.isShared)
    }
}
