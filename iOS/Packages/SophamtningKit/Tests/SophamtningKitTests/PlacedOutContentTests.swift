import Foundation
import Testing
import SophamtningKit

@Suite struct PlacedOutContentTests {
    private func content(placedOut: Bool = false) -> PickupActivityContent {
        PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [ActivityFraction(id: "rest", name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")], estimated: false, warning: nil, placedOut: placedOut)
    }

    @Test func standardarFalse() {
        #expect(content().placedOut == false)
    }

    @Test func aldreJsonUtanFaltetGerFalse() throws {
        // Innehåll som en schemalagd aktivitet från en äldre version kan ha sparat.
        let old = """
        {"addressName":"Hemma","dateText":"Måndag 9 november","shortDateText":"Mån 9 nov","fractions":[],"estimated":false}
        """
        let decoded = try JSONDecoder().decode(PickupActivityContent.self, from: Data(old.utf8))
        #expect(decoded.placedOut == false)
        #expect(decoded.addressName == "Hemma")
    }

    @Test func kodningBehallerVardet() throws {
        for value in [true, false] {
            let data = try JSONEncoder().encode(content(placedOut: value))
            let decoded = try JSONDecoder().decode(PickupActivityContent.self, from: data)
            #expect(decoded.placedOut == value)
            #expect(decoded == content(placedOut: value))
        }
    }

    @Test func markeratSomUtstalltAndrarBaraFaltet() {
        let marked = content().markedPlacedOut()
        #expect(marked.placedOut)
        #expect(marked == content(placedOut: true))
        #expect(marked != content())
    }

    @Test func rubrikenOchRadenNarKarlenArUtstallda() {
        #expect(content().title == "Ställ ut kärlen")
        #expect(content().detailLine == "Hemma · måndag 9 november")
        // Mitt eget tryck: vem och när är okänt, så adressen och datumet står kvar.
        #expect(content().markedPlacedOut().title == "Kärlen är utställda")
        #expect(content().markedPlacedOut().detailLine == "Hemma · måndag 9 november")
        let marked = content().markedPlacedOut(detail: "av Sofie · kl. 19:42")
        #expect(marked.detailLine == "av Sofie · kl. 19:42")
        #expect(PickupActivityContent.doneButton == "Klart")
    }

    @Test func vemOchNarFoljerMedKodningenOchBaraNarUtstallt() throws {
        let marked = content().markedPlacedOut(detail: "av Sofie · kl. 19:42")
        let decoded = try JSONDecoder().decode(PickupActivityContent.self, from: JSONEncoder().encode(marked))
        #expect(decoded == marked)
        #expect(decoded.placedOutDetail == "av Sofie · kl. 19:42")
        // Utan bock finns ingen rad om vem.
        let unmarked = PickupActivityContent(addressName: "Hemma", dateText: "Måndag 9 november", shortDateText: "Mån 9 nov", fractions: [], estimated: false, warning: nil, placedOut: false, placedOutDetail: "av Sofie · kl. 19:42")
        #expect(unmarked.placedOutDetail == nil)
    }

    // MARK: Hushåll

    private let homeKey = AddressKey(source: "kallor", id: "hem")
    private let monday = DayDate("2026-11-09")!

    private func input() -> PlannerInput {
        let address = SavedAddress(key: homeKey, url: URL(string: "https://example.com/hem")!, street: "Gatan 1", locality: "Orten", kommun: "Kommunen", detail: nil, selection: "address", displayName: "Hemma", isPrimary: true, addedAt: Date(timeIntervalSince1970: 0))
        let response = AddressResponse(
            today: DayDate("2026-11-06")!,
            address: Address(id: "hem", street: "Gatan 1", locality: "Orten", kommun: "Kommunen", source: "kallor", detail: nil, selection: "address", notice: nil),
            next: [], summary: "",
            events: [PickupEvent(date: monday, fractions: ["rest"], estimated: false, deviation: nil, warning: nil, labels: [:])],
            bins: [], fractions: ["rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#111111", icon: "trash")],
            links: Links(ics: URL(string: "https://example.com/a.ics")!, web: URL(string: "https://example.com/a")!),
            updatedAt: DayDate("2026-11-06")!
        )
        let schedule = CachedSchedule(response: response, fetchedAt: Date(timeIntervalSince1970: 0))
        return PlannerInput(addresses: [PlannerAddress(address: address, schedule: schedule)], settings: ReminderSettings(liveActivityOn: true), placedOut: [], now: StockholmClock.date(on: monday, minutes: 7 * 60), liveActivitiesAllowed: true, existingActivities: [], shownActivities: [])
    }

    private func household(markDate: DayDate, by: String = "kim") -> HouseholdState {
        let mark = HouseholdMark(placedOut: PlacedOut(key: homeKey, date: markDate), by: by, at: Date(timeIntervalSince1970: 0), isPending: false)
        return HouseholdState(role: .member, myId: "jag", participants: [], addresses: [], marks: [mark], status: .synced)
    }

    @Test func liveActivityVisarAndrasBock() {
        let content = ReminderPlanner.activityContent(on: monday, input: input(), household: household(markDate: monday))
        #expect(content?.placedOut == true)
        // Kim saknas bland deltagarna och visas som "någon". Klockslaget är 01:00 svensk tid för tidpunkten 0.
        #expect(content?.placedOutDetail == "av någon · kl. 01:00")
    }

    @Test func liveActivityUtanBockEllerMedAnnatDatumVisarInteBocken() {
        #expect(ReminderPlanner.activityContent(on: monday, input: input())?.placedOut == false)
        #expect(ReminderPlanner.activityContent(on: monday, input: input(), household: household(markDate: monday.adding(days: 7)))?.placedOut == false)
    }
}
